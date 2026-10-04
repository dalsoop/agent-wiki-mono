import Foundation
import WikiLedgerKit

/// 원장에 놓인 ledger 3 기록(저장된 id 와 기록).
public struct LawStoredRecord: Sendable, Equatable {
    public let id: String
    public let record: LawRecord

    public init(id: String, record: LawRecord) {
        self.id = id
        self.record = record
    }
}

/// ledger 3 원장 저장소. 쓰기 연산은 공포(`enact`)뿐이다 — 개정·폐지·원상회복도 공포로 한다.
/// 형식(직렬화·파싱)은 WikiLedgerKit 이 정본이다. 옛 `LedgerStore`(ledger 1·2)와 따로 둔다.
/// 근거: docs/business-rules.md "agent-law(ledger 3)", docs/standards.md "agent-law (ledger 3)", 결정 0007.
public struct LawStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    var objectsDir: URL { root.appendingPathComponent("objects") }
    var exhibitsDir: URL { root.appendingPathComponent("exhibits") }

    /// `<원장 루트>/objects/YYYY/MM/<id>.md`(공포일의 UTC 연·월).
    public func objectURL(id: String, promulgated: Date) -> URL {
        let utc = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        let components = Calendar(identifier: .gregorian).dateComponents(in: utc, from: promulgated)
        return objectsDir
            .appendingPathComponent(String(format: "%04d", components.year ?? 0))
            .appendingPathComponent(String(format: "%02d", components.month ?? 0))
            .appendingPathComponent("\(id).md")
    }

    /// `<원장 루트>/exhibits/<sha256 앞 2자>/<sha256>`.
    public func exhibitURL(sha256: String) -> URL {
        exhibitsDir.appendingPathComponent(String(sha256.prefix(2))).appendingPathComponent(sha256)
    }

    // MARK: - 공포 (유일한 쓰기 연산)

    /// 공포. 규칙을 모두 통과하면 `objects/YYYY/MM/<id>.md` 에 덮어쓰기 없이 쓴다.
    /// 같은 id 파일이 있으면 바이트가 같을 때만 성공(멱등), 다르면 `duplicateID`.
    @discardableResult
    public func enact(_ draft: LawDraft, now: Date = Date(), context: LawEnactContext = LawEnactContext()) throws
        -> LawStoredRecord {
        try enact(draft, now: now, context: context, revival: nil)
    }

    /// 공포(원상회복 표지 포함). `revival` 은 `restore` 만 만든다(`LawRestoreRevival`).
    func enact(_ draft: LawDraft, now: Date, context: LawEnactContext, revival: LawRestoreRevival?) throws
        -> LawStoredRecord {
        try write(prepare(draft, now: now, context: context, existing: scan(), revival: revival))
    }

    /// 검증을 마친, 쓸 차례의 기록.
    struct PreparedRecord {
        let stored: LawStoredRecord
        let url: URL
        let payload: Data
    }

    /// 쓰지 않고 공포 검증 전체(증언·관계·참조·화자)와 같은 id 충돌을 본다.
    func prepare(
        _ draft: LawDraft, now: Date, context: LawEnactContext, existing: [LawStoredRecord], revival: LawRestoreRevival?
    ) throws -> PreparedRecord {
        var context = context
        if context.promotions == nil { context.promotions = LawPromotionWitness(records: existing) }
        let record = try LawEnactValidator(
            store: self, context: context, sameLedger: LawSameLedgerResolver(records: existing)
        ).validatedRecord(draft, promulgated: LawTime.truncatedToMilliseconds(now), revival: revival)
        let id = record.contentID()
        let url = objectURL(id: id, promulgated: record.promulgated)
        let payload = Data(record.serialize(id: id).utf8)
        if let present = try? Data(contentsOf: url), present != payload { throw LawEnactError.duplicateID(id) }
        return PreparedRecord(stored: LawStoredRecord(id: id, record: record), url: url, payload: payload)
    }

    func write(_ prepared: PreparedRecord) throws -> LawStoredRecord {
        let (url, payload, id) = (prepared.url, prepared.payload, prepared.stored.id)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let present = try? Data(contentsOf: url) {
            guard present == payload else { throw LawEnactError.duplicateID(id) }
            return prepared.stored
        }
        do {
            try payload.write(to: url, options: [.withoutOverwriting])
        } catch {
            // 경합으로 그 사이 같은 id 가 쓰였으면 바이트 비교로 멱등 판정.
            if let present = try? Data(contentsOf: url) {
                guard present == payload else { throw LawEnactError.duplicateID(id) }
                return prepared.stored
            }
            throw error
        }
        return prepared.stored
    }

    // MARK: - 원상회복

    /// `restore <batch>` — 묶음의 기록마다 새 기록을 공포한다. 개정이었으면 이전 판을 다시 공포(`amends`),
    /// 신규였으면 폐지(`repeals`). 파일은 지우지 않는다. 새 기록들은 새 묶음 id 하나를 공유한다.
    /// 전부 아니면 전무: 만들 기록 하나하나를 쓰기 전에 그 기록의 경로(`LawRestorePaths` — 일반 묶음은 `path`, 드리밍 묶음의
    /// 드리밍 기록은 `dream`·`court`)의 `admit` 과 공포 검증 전체(증언·관계·참조·화자)에 넣고, 하나라도 거부되면 아무것도
    /// 쓰지 않고 거부 이유 목록과 함께 `restoreRefused` 를 던진다.
    /// 되살린 이전 판은 원래 화자를 그대로 가진다(`LawRestoreRevival` — 사람 작성자의 화자 고정을 이 기록에만 열지 않는다).
    /// 검사와 쓰기 사이에 상태가 바뀌어 쓰는 도중 실패하면 쓴 기록은 지우지 않고(덧붙이기 전용)
    /// `restorePartiallyApplied` 로 쓴 기록과 남은 대상을 보고한다.
    /// - Parameter perRuling: 결정에 따른 원상회복이면 그 결정(`ruling`) id — `per-ruling` 으로 인용한다.
    /// - Parameter path: 원상회복을 부른 경로(CLI·화면은 `general`, 결정의 조치는 `court`).
    /// - Parameter lookup: 같은 원장 밖 대상 기록을 찾는 함수(허용 범위). 같은 원장은 항상 먼저 본다.
    @discardableResult
    public func restore(
        batch: String, actor: LawActor, now: Date = Date(), context: LawEnactContext = LawEnactContext(),
        perRuling: String? = nil, path: LawEnactPath = .general, lookup: (String) -> LawRecord? = { _ in nil }
    ) throws -> [LawStoredRecord] {
        let plan = try planRestore(
            batch: batch, actor: actor, now: now, context: context, perRuling: perRuling, path: path, lookup: lookup)
        return try applyRestore(plan)
    }

    /// 원상회복 계획 — 쓸 기록과 그 검사 결과. `planRestore` 가 만들고 `applyRestore` 가 쓴다.
    struct RestorePlan {
        typealias Item = (target: LawStoredRecord, draft: LawDraft, revival: LawRestoreRevival?)
        let items: [Item]
        let now: Date
        let context: LawEnactContext
    }

    /// 원상회복의 검사 단계 — 아무것도 쓰지 않는다. 만들 기록 하나하나를 그 경로의 `admit` 과 공포 검증 전체에 넣고,
    /// 하나라도 거부되면 거부 이유 목록과 함께 `restoreRefused` 를 던진다.
    /// - Parameter restoreBatch: 새 기록들이 공유할 묶음 id(여러 원장을 한꺼번에 되돌릴 때 같은 값을 준다). 비우면 새로 만든다.
    func planRestore(
        batch: String, actor: LawActor, now: Date, context: LawEnactContext,
        perRuling: String? = nil, path: LawEnactPath = .general, lookup: (String) -> LawRecord? = { _ in nil },
        restoreBatch: String? = nil
    ) throws -> RestorePlan {
        let records = scan()
        let byID = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let targets = records.filter { $0.record.batch == batch }
        guard !targets.isEmpty else { throw LawEnactError.batchNotFound(batch) }
        let restoreBatch = restoreBatch ?? LedgerID.generate(now: now)
        let rulingCite = perRuling.map { [LawCite(id: $0, rel: LawRelation.perRuling.rawValue)] } ?? []
        let drafts: [RestorePlan.Item] = targets.map { target in
            if let previousID = target.record.amends, let previous = byID[previousID]?.record {
                return (target, LawDraft(
                    actor: actor, speaker: previous.speaker, title: previous.title,
                    type: previous.type ?? LawRecordType.record.rawValue, origin: previous.origin,
                    batch: restoreBatch, tags: previous.tags, cites: previous.cites + rulingCite,
                    exhibits: previous.exhibits, amends: target.id, source: previous.source,
                    body: previous.body), LawRestoreRevival())
            }
            return (target, LawDraft(
                actor: actor, title: target.record.title.map { "폐지: \($0)" },
                type: target.record.type ?? LawRecordType.record.rawValue, batch: restoreBatch,
                cites: rulingCite, repeals: target.id, body: "restore \(batch)"), nil)
        }
        let find: (String) -> LawRecord? = { byID[$0]?.record ?? lookup($0) }
        var planned: [RestorePlan.Item] = []
        var refusals: [String] = []
        let paths = LawRestorePaths(records: records)
        for (target, draft, revival) in drafts {
            do {
                let recordPath = try paths.path(for: target, batch: batch, caller: path)
                let admitted = try recordPath.admit(draft, target: find)
                _ = try prepare(admitted, now: now, context: context, existing: records, revival: revival)
                planned.append((target, admitted, revival))
            } catch let error as LawEnactError {
                refusals.append("\(String(target.id.prefix(8))): \(error.description)")
            }
        }
        guard refusals.isEmpty else { throw LawEnactError.restoreRefused(refusals) }
        return RestorePlan(items: planned, now: now, context: context)
    }

    /// 원상회복의 쓰기 단계 — 검사를 통과한 계획을 공포한다. 쓰는 도중 실패하면 쓴 기록은 지우지 않고(덧붙이기 전용)
    /// `restorePartiallyApplied` 로 쓴 기록과 남은 대상을 보고한다.
    func applyRestore(_ plan: RestorePlan) throws -> [LawStoredRecord] {
        var written: [LawStoredRecord] = []
        for (index, item) in plan.items.enumerated() {
            do {
                written.append(try enact(item.draft, now: plan.now, context: plan.context, revival: item.revival))
            } catch {
                throw LawEnactError.restorePartiallyApplied(
                    applied: written, remaining: plan.items[index...].map(\.target.id),
                    reason: (error as? LawEnactError)?.description ?? "\(error)")
            }
        }
        return written
    }

    // MARK: - 조회

    /// 파싱되는 ledger 3 기록 전부(공포일, id 순). id 재해시는 검사하지 않는다 — 무결성은 `audit()` 로만 본다.
    public func scan() -> [LawStoredRecord] {
        objectFiles().compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = LawRecordParser.parse(text) else { return nil }
            return LawStoredRecord(id: parsed.storedID, record: parsed.record)
        }.sorted { ($0.record.promulgated, $0.id) < ($1.record.promulgated, $1.id) }
    }

    func objectFiles() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var urls: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "md" { urls.append(url) }
        return urls.sorted { $0.path < $1.path }
    }
}

/// 원상회복 경로 표지 — `LawStore.restore` 가 되살리는 이전 판(개정이었던 기록의 원상회복)에만 붙인다.
/// 이 파일 밖에서는 만들 수 없어 일반 공포가 흉내 내지 못한다. 공포 검증은 이 표지가 있을 때만
/// 사람 작성자의 화자 고정(`humanSpeakerFixed`)을 적용하지 않고 원래 화자를 그대로 둔다(`LawEnactValidator.resolvedSpeaker`).
/// 근거: docs/business-rules.md "공포·개정·폐지·원상회복".
struct LawRestoreRevival: Sendable {
    fileprivate init() {}
}

/// `objects/` 의 변화 표지 — 파일 수·크기 합·가장 늦은 수정 시각(파싱하지 않고 stat 만).
/// 원장 파일은 덧붙이기 전용이라 새 기록은 이 값을 바꾼다. 화면은 이 값이 같으면 원장을 다시 읽지 않는다.
public struct LawObjectsFingerprint: Sendable, Equatable {
    public let count: Int
    public let totalSize: Int
    public let latestModification: Date?
}

extension LawStore {
    public func objectsFingerprint() -> LawObjectsFingerprint {
        var count = 0
        var size = 0
        var latest: Date?
        if let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.pathExtension == "md" {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                count += 1
                size += values?.fileSize ?? 0
                if let date = values?.contentModificationDate, date > (latest ?? .distantPast) { latest = date }
            }
        }
        return LawObjectsFingerprint(count: count, totalSize: size, latestModification: latest)
    }
}
