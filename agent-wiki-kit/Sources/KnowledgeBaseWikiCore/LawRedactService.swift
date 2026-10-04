import Foundation
import WikiLedgerKit

// 가림(`redact`)과 증거물 R2 동기화.
// 근거: docs/security.md "R2 와 세션"(가림은 증거물에만, R2 객체와 모든 기기의 로컬 사본을 지우고 `redaction` 기록,
// 원장 기록은 가리지 않고 폐지만 한다, 감사의 "가림" 표시), docs/business-rules.md "본문 머리 칸"(`redaction`: target, reason),
// docs/contracts.md `redact <R2 키 또는 sha> --reason <r>`, docs/architecture.md(증거물 위치·동기화), 결정 0007.

public enum LawRedactError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyReason
    case ledgerRecord(String)
    case notEvidence(String)
    case otherLedger(String)
    case invalidTarget(String)
    case notFound(String)
    case noLedgerKey(String)
    case deletionFailed(target: String, recordID: String, detail: String)

    public var description: String {
        switch self {
        case .emptyReason: return "가림 이유가 비었음 — --reason <r>"
        case .ledgerRecord(let id): return "원장 기록은 가리지 않는다(폐지만 한다): \(id) — repeal 을 쓰세요"
        case .notEvidence(let key): return "증거물이 아닌 주소는 가리지 않는다(세션 조각·증거물만): \(key)"
        case .otherLedger(let key): return "이 원장의 주소가 아님: \(key)"
        case .invalidTarget(let raw): return "가림 대상은 R2 키 또는 sha256: \(raw)"
        case .notFound(let key): return "가릴 대상이 R2 에도 로컬에도 없음: \(key)"
        case .noLedgerKey(let world): return "원장 키가 없는 원장: \(world)"
        case .deletionFailed(let target, let recordID, let detail):
            return "가림 기록은 공포됨(\(recordID)) — 삭제 실패, 같은 명령을 다시 실행하세요: \(target): \(detail)"
        }
    }
}

/// 가림 대상 해석 결과.
public struct LawRedactionTarget: Sendable, Equatable {
    /// R2 키(`<원장 키>/sessions/…` 또는 `<원장 키>/exhibits/<앞 2자>/<sha>`).
    public let key: String
    /// 증거물이면 그 sha256(기록의 `exhibit` 칸으로도 지정).
    public let exhibitSHA256: String?
    /// 로컬 사본 경로(원장 루트 기준 상대 경로).
    public let localRelativePath: String
}

public struct LawRedactOutcome: Codable, Sendable, Equatable {
    public var recordID: String
    public var target: String
    /// 이미 가림 기록이 있어 새로 공포하지 않았다.
    public var alreadyRecorded: Bool
    public var deletedRemote: Bool
    public var deletedLocal: Bool
}

public enum LawRedactService {
    /// 대상 토큰(R2 키 또는 sha256)을 해석한다. 원장 기록·실행 요약·다른 원장 주소는 거부.
    public static func resolveTarget(_ raw: String, ledgerKey: String, store: LawStore) throws -> LawRedactionTarget {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if LawHash.isContentID(token.lowercased()) {
            let sha = token.lowercased()
            if store.scan().contains(where: { $0.id == sha }) { throw LawRedactError.ledgerRecord(sha) }
            return LawRedactionTarget(
                key: LawArchiveKeys.exhibit(ledgerKey: ledgerKey, sha256: sha), exhibitSHA256: sha,
                localRelativePath: "exhibits/\(sha.prefix(2))/\(sha)")
        }
        let segments = token.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard segments.count >= 3, !segments.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw LawRedactError.invalidTarget(token)
        }
        guard token.hasPrefix(ledgerKey + "/") else { throw LawRedactError.otherLedger(token) }
        let rest = String(token.dropFirst(ledgerKey.count + 1))
        let restSegments = rest.split(separator: "/").map(String.init)
        switch restSegments.first {
        case "exhibits":
            guard restSegments.count == 3, let sha = restSegments.last, LawHash.isContentID(sha),
                  restSegments[1] == String(sha.prefix(2))
            else { throw LawRedactError.invalidTarget(token) }
            if store.scan().contains(where: { $0.id == sha }) { throw LawRedactError.ledgerRecord(sha) }
            return LawRedactionTarget(key: token, exhibitSHA256: sha, localRelativePath: rest)
        case "sessions":
            guard restSegments.count == 5, restSegments[4].hasSuffix(".jsonl.gz") else {
                throw LawRedactError.invalidTarget(token)
            }
            return LawRedactionTarget(key: token, exhibitSHA256: nil, localRelativePath: rest)
        case "objects":
            throw LawRedactError.ledgerRecord(token)
        default:
            throw LawRedactError.notEvidence(token)
        }
    }

    /// 가림: 대상 확인 → `redaction` 기록 공포(같은 대상의 기록이 이미 있으면 건너뜀) → R2 삭제 → 로컬 삭제.
    /// 기록을 먼저 남겨, 삭제가 끊겨도 감사가 위반 대신 "가림"으로 보고 다시 실행하면 이어서 지운다.
    public static func redact(
        _ raw: String, reason: String, actor: LawActor, target: LawLedgerTarget, objectStore: any LawObjectStore,
        now: Date = Date()
    ) throws -> LawRedactOutcome {
        let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReason.isEmpty, !trimmedReason.contains(where: \.isNewline) else { throw LawRedactError.emptyReason }
        guard let ledgerKey = target.catalog.world(named: target.worldName)?.key else {
            throw LawRedactError.noLedgerKey(target.worldName)
        }
        let store = target.store
        let resolved = try resolveTarget(raw, ledgerKey: ledgerKey, store: store)
        let localURL = store.root.appendingPathComponent(resolved.localRelativePath)
        let existing = LawRedactionSweep.redactionRecords(store).first { $0.targets.contains(resolved.key) }

        let remotePresent: Bool
        do {
            remotePresent = try objectStore.exists(key: resolved.key)
        } catch {
            throw LawRedactError.deletionFailed(target: resolved.key, recordID: existing?.id ?? "-", detail: "\(error)")
        }
        let localPresent = FileManager.default.fileExists(atPath: localURL.path)
        if existing == nil, !remotePresent, !localPresent { throw LawRedactError.notFound(resolved.key) }

        let recordID: String
        if let existing {
            recordID = existing.id
        } else {
            let draft = LawDraft(
                actor: actor, title: "가림: \(resolved.key)", type: LawRecordType.redaction.rawValue,
                exhibits: resolved.exhibitSHA256.map { [$0] } ?? [],
                body: "target: \(resolved.key)\nreason: \(trimmedReason)\n")
            recordID = try LawEnactService.enact(draft, target: target, path: .redact, now: now).id
        }
        if remotePresent {
            do {
                try objectStore.delete(key: resolved.key)
            } catch {
                throw LawRedactError.deletionFailed(target: resolved.key, recordID: recordID, detail: "\(error)")
            }
        }
        if localPresent {
            do {
                try FileManager.default.removeItem(at: localURL)
            } catch {
                throw LawRedactError.deletionFailed(target: localURL.path, recordID: recordID, detail: error.localizedDescription)
            }
        }
        return LawRedactOutcome(
            recordID: recordID, target: resolved.key, alreadyRecorded: existing != nil,
            deletedRemote: remotePresent, deletedLocal: localPresent)
    }
}

// MARK: - 가림 기록에 따른 로컬 삭제(동기화)

public enum LawRedactionSweep {
    public struct Entry: Sendable, Equatable {
        public let id: String
        /// 머리 칸 `target`(R2 키 또는 sha)과 `exhibit` 칸의 증거물 주소.
        public let targets: Set<String>
        public let exhibits: Set<String>
    }

    /// `redact` 명령이 공포한 가림 기록인가 — 유형 `redaction` 이고 가림 경로의 예약 태그(`LawEnactPath.redactionMarkerTag`)가
    /// 있으며 승격본(`promoted`)이 아니다. 로컬 삭제·증거물 동기화 제외·감사의 "가림" 판정은 이 기록만 믿는다.
    public static func isTrusted(_ record: LawRecord) -> Bool {
        record.type == LawRecordType.redaction.rawValue
            && record.tags.contains(LawEnactPath.redactionMarkerTag)
            && !record.tags.contains(LawPromotionWitness.promotedTag)
    }

    /// 원장의 믿을 수 있는 가림 기록들(`isTrusted`).
    public static func redactionRecords(_ store: LawStore) -> [Entry] {
        store.scan().filter { isTrusted($0.record) }.map { stored in
            var targets: Set<String> = []
            let target = (try? LawHeadFields.parse(body: stored.record.body, type: stored.record.type))?["target"]
            if let target { targets.insert(target) }
            return Entry(id: stored.id, targets: targets, exhibits: Set(stored.record.exhibits))
        }
    }

    /// 가린 증거물 sha256 들(머리 칸 target 의 끝 조각 + exhibit 칸). 증거물 동기화가 이것을 건너뛴다.
    public static func redactedExhibits(_ store: LawStore) -> Set<String> {
        var shas: Set<String> = []
        for entry in redactionRecords(store) {
            shas.formUnion(entry.exhibits)
            for target in entry.targets {
                let last = String(target.split(separator: "/").last ?? Substring(target))
                if LawHash.isContentID(last) { shas.insert(last) }
            }
        }
        return shas
    }

    /// 가림 기록에 따른 로컬 삭제. 다른 기기가 공포한 가림 기록을 동기화로 받은 뒤 부른다.
    /// 지운 로컬 경로(원장 루트 기준)를 돌려준다. 증거물·세션 사본 밖의 경로는 건드리지 않는다.
    @discardableResult
    public static func applyLocalDeletions(store: LawStore, ledgerKey: String) -> [String] {
        var relative: Set<String> = []
        for entry in redactionRecords(store) {
            for sha in entry.exhibits where LawHash.isContentID(sha) {
                relative.insert("exhibits/\(sha.prefix(2))/\(sha)")
            }
            for target in entry.targets {
                if LawHash.isContentID(target) {
                    relative.insert("exhibits/\(target.prefix(2))/\(target)")
                } else if target.hasPrefix(ledgerKey + "/") {
                    let rest = String(target.dropFirst(ledgerKey.count + 1))
                    let parts = rest.split(separator: "/", omittingEmptySubsequences: false)
                    guard let first = parts.first, first == "exhibits" || first == "sessions",
                          !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
                    else { continue }
                    relative.insert(rest)
                }
            }
        }
        var deleted: [String] = []
        for path in relative.sorted() {
            let url = store.root.appendingPathComponent(path)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                deleted.append(path)
            } catch {
                continue  // 다음 동기화가 다시 시도한다.
            }
        }
        return deleted
    }
}

// MARK: - 증거물 R2 동기화

public struct LawExhibitSyncOutcome: Codable, Sendable, Equatable {
    public var ledgerKey: String
    public var uploaded: [String]
    public var downloaded: [String]
    /// 받은 바이트의 sha256 이 이름과 다름 — 저장하지 않았다.
    public var rejected: [String]
    public var failed: [LawArchiveFailure]

    public var ok: Bool { rejected.isEmpty && failed.isEmpty }
}

public enum LawExhibitSync {
    /// 로컬 `<원장 루트>/exhibits/` 의 증거물 sha256 들.
    public static func localExhibits(_ store: LawStore) -> [String] {
        let root = store.root.appendingPathComponent("exhibits")
        let fm = FileManager.default
        guard let shards = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        var shas: [String] = []
        for shard in shards where shard.count == 2 {
            guard let names = try? fm.contentsOfDirectory(atPath: root.appendingPathComponent(shard).path) else { continue }
            shas += names.filter { LawHash.isContentID($0) && $0.hasPrefix(shard) }
        }
        return shas.sorted()
    }

    /// 로컬과 R2 `<원장 키>/exhibits/` 의 차집합을 올리고 받는다. 받은 것은 sha256 을 다시 계산해 검증한다.
    /// 가린 증거물은 어느 쪽으로도 옮기지 않는다.
    public static func sync(store: LawStore, ledgerKey: String, objectStore: any LawObjectStore) -> LawExhibitSyncOutcome {
        var outcome = LawExhibitSyncOutcome(ledgerKey: ledgerKey, uploaded: [], downloaded: [], rejected: [], failed: [])
        let redacted = LawRedactionSweep.redactedExhibits(store)
        let remoteKeys: [String]
        do {
            remoteKeys = try objectStore.list(prefix: "\(ledgerKey)/exhibits/")
        } catch {
            outcome.failed.append(LawArchiveFailure(target: "\(ledgerKey)/exhibits/", reason: "\(error)"))
            return outcome
        }
        let remote = Set(remoteKeys.compactMap { key -> String? in
            guard let sha = key.split(separator: "/").last.map(String.init), LawHash.isContentID(sha),
                  key == LawArchiveKeys.exhibit(ledgerKey: ledgerKey, sha256: sha)
            else { return nil }
            return sha
        })
        let local = Set(localExhibits(store))

        for sha in local.subtracting(remote).subtracting(redacted).sorted() {
            let key = LawArchiveKeys.exhibit(ledgerKey: ledgerKey, sha256: sha)
            guard let data = try? store.exhibit(sha256: sha), LawHash.sha256Hex(data) == sha else {
                outcome.rejected.append(sha)  // 로컬 변조 — 올리지 않는다.
                continue
            }
            do {
                try objectStore.putImmutable(key: key, data: data)
                outcome.uploaded.append(sha)
            } catch {
                outcome.failed.append(LawArchiveFailure(target: key, reason: "\(error)"))
            }
        }
        for sha in remote.subtracting(local).subtracting(redacted).sorted() {
            let key = LawArchiveKeys.exhibit(ledgerKey: ledgerKey, sha256: sha)
            do {
                let data = try objectStore.get(key: key)
                guard LawHash.sha256Hex(data) == sha else {
                    outcome.rejected.append(sha)
                    continue
                }
                try store.putExhibit(data)
                outcome.downloaded.append(sha)
            } catch {
                outcome.failed.append(LawArchiveFailure(target: key, reason: "\(error)"))
            }
        }
        return outcome
    }
}
