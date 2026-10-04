import Foundation
import WikiLedgerKit

/// 가림 기록이 있어 부재가 위반이 아닌 증거물.
public struct LawRedactedExhibit: Sendable, Equatable {
    public let recordID: String
    public let sha256: String

    public init(recordID: String, sha256: String) {
        self.recordID = recordID
        self.sha256 = sha256
    }
}

/// ledger 3 감사 결과. `violations` 가 비어야 통과(명령 계약의 종료 코드 2 는 위반이 있을 때).
public struct LawAuditReport: Sendable, Equatable {
    public var violations: [LedgerStore.Violation]
    /// 사실인정이 없는 현행 지식 기록 — "판단 대기"(위반 아님).
    public var pendingJudgment: [String]
    /// 가림 기록이 있는 증거물의 부재 — "가림"(위반 아님).
    public var redactedExhibits: [LawRedactedExhibit]
    /// 갈라진 현행 — 보고(위반 아님).
    public var divergent: [LawDivergence]

    public var passed: Bool { violations.isEmpty }
}

extension LawStore {
    /// 감사 — 파일 읽기·형식, id 중복, 파일명-id, 본문 sha256(본문 변조), 코어 재해시(코어 변조),
    /// 참조 무결성, 관계 규칙, 승격본 주장(원본 원장의 영수증·원본 증거 대조), 증거물 부재(가림 기록이 있으면 "가림")를 검사하고,
    /// 판단 대기와 갈라진 현행을 보고한다. 근거: docs/business-rules.md "사실인정과 4종류"·
    /// "공포·개정·폐지·원상회복", docs/security.md "R2 와 세션"(가림 감사).
    /// - Parameter context: `resolver` 로 같은 원장 밖 참조를 푼다(없으면 같은 원장 안만).
    public func audit(context: LawEnactContext = LawEnactContext()) -> LawAuditReport {
        typealias Violation = LedgerStore.Violation
        var violations: [Violation] = []
        var seen: Set<String> = []
        var records: [LawStoredRecord] = []
        for url in objectFiles() {
            let name = url.deletingPathExtension().lastPathComponent
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                violations.append(Violation(id: name, problem: "읽기 실패"))
                continue
            }
            guard let parsed = LawRecordParser.parse(text) else {
                violations.append(Violation(id: name, problem: "ledger 3 형식 아님 또는 필수 필드 누락"))
                continue
            }
            let id = parsed.storedID
            if seen.contains(id) { violations.append(Violation(id: id, problem: "id 중복")) }
            seen.insert(id)
            if name != id { violations.append(Violation(id: id, problem: "파일명-id 불일치")) }
            if parsed.storedSHA256 != parsed.record.bodySHA256 {
                violations.append(Violation(id: id, problem: "본문 변조 — sha256 불일치"))
            }
            if parsed.record.contentID() != id {
                violations.append(Violation(id: id, problem: "코어 변조 — 코어 재해시가 id 와 다름"))
            }
            records.append(LawStoredRecord(id: id, record: parsed.record))
        }

        let sameLedger = LawSameLedgerResolver(records: records)
        func resolve(_ id: String) -> LawResolvedReference? {
            sameLedger.resolve(id) ?? context.resolver?.resolve(id)
        }
        for stored in records {
            let record = stored.record
            for ref in record.allAmends + [record.repeals].compactMap({ $0 }) where resolve(ref) == nil {
                violations.append(Violation(id: stored.id, problem: "없는 기록 참조: \(ref)"))
            }
            for cite in record.cites {
                let target = resolve(cite.id)
                if target == nil {
                    violations.append(Violation(id: stored.id, problem: "없는 기록 참조: \(cite.id)"))
                }
                guard let relation = LawRelation(rawValue: cite.rel) else {
                    violations.append(Violation(id: stored.id, problem: "관계 규칙 위반 — 관계 집합 밖: \(cite.rel)"))
                    continue
                }
                if !relation.allowsSource(type: record.type, origin: record.origin, amendsOrRepeals: record.amendsOrRepeals) {
                    violations.append(Violation(id: stored.id, problem: "관계 규칙 위반 — \(cite.rel) 출발 유형 \(record.type ?? "-")"))
                }
                if let target, !relation.allowsTarget(type: target.type, isPredecessor: target.scope == .predecessor) {
                    violations.append(Violation(id: stored.id, problem: "관계 규칙 위반 — \(cite.rel) 도착 \(cite.id)"))
                }
            }
        }

        // 승격본이라고 주장하는 증거(`promoted` 태그·대상 영수증)는 원본 원장의 영수증과 원본 증거로 확인한다.
        // 확인된 승격본은 세션 증언 없이도 위반이 아니다.
        let promotions = context.promotions ?? LawPromotionWitness(records: records)
        for stored in records where stored.record.type == LawRecordType.evidence.rawValue {
            if case .unproven(let reason) = promotions.status(of: stored.id) {
                violations.append(Violation(id: stored.id, problem: "승격본 미확인 — \(reason)"))
            }
        }

        // 증거물: 가림 기록(redaction)의 머리 칸 target(sha256 또는 그것으로 끝나는 주소)과 exhibit 칸이 대상을 정한다.
        var redactedTargets: Set<String> = []
        for stored in records where stored.record.type == LawRecordType.redaction.rawValue {
            redactedTargets.formUnion(stored.record.exhibits)
            if let target = (try? LawHeadFields.parse(body: stored.record.body, type: stored.record.type))?["target"] {
                redactedTargets.insert(String(target.split(separator: "/").last ?? Substring(target)))
            }
        }
        var redacted: [LawRedactedExhibit] = []
        for stored in records where stored.record.type != LawRecordType.redaction.rawValue {
            for sha in stored.record.exhibits
            where !FileManager.default.fileExists(atPath: exhibitURL(sha256: sha).path) {
                if redactedTargets.contains(sha) {
                    redacted.append(LawRedactedExhibit(recordID: stored.id, sha256: sha))
                } else {
                    violations.append(Violation(id: stored.id, problem: "증거물 누락(가림 기록 없음): \(sha)"))
                }
            }
        }

        let view = LawLedgerView(records: records)
        let pending = view.inForce
            .filter { LawRecordType.isKnowledge($0.record.type) && view.currentFinding(for: $0.id) == nil }
            .map(\.id)
        return LawAuditReport(
            violations: violations, pendingJudgment: pending, redactedExhibits: redacted,
            divergent: view.divergent)
    }
}
