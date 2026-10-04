import Foundation
import WikiLedgerKit

/// Claude 기억 4종류(계산한 보기, 저장하지 않음). 근거: docs/business-rules.md "사실인정과 4종류".
public enum LawMemoryKind: String, Sendable, Equatable, CaseIterable {
    /// 사람 — `subject: person`.
    case person
    /// 지적 — `speaker: user` 이고 `subject: agent-self`.
    case feedback
    /// 진행 — `subject: project`.
    case project
    /// 위치 — `subject: external`.
    case reference
    case unclassified
}

/// 원장 기록 집합에서 파생하는 보기 — 현행·연혁·현행 사실인정·4종류·갈라진 현행. 저장하지 않는다.
public struct LawLedgerView: Sendable {
    public let records: [LawStoredRecord]
    let byID: [String: LawStoredRecord]
    /// 어떤 기록이든 개정(`amends`·`amends-also`)한 대상.
    let amended: Set<String>
    /// 효력 있는 폐지 기록(스스로 폐지되지 않은 폐지 기록)이 폐지한 대상.
    let repealed: Set<String>

    public init(records: [LawStoredRecord]) {
        let sorted = records.sorted { ($0.record.promulgated, $0.id) < ($1.record.promulgated, $1.id) }
        self.records = sorted
        let byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.byID = byID
        amended = Set(sorted.flatMap(\.record.allAmends))
        // 폐지 기록 R 은 R 자신이 효력 있는 폐지 기록에 폐지되지 않았을 때만 효력이 있다(원상회복이 폐지를 폐지한다).
        // 내용 주소라 참조는 이미 있던 기록만 가리켜 순환이 없다.
        var repealersOf: [String: [String]] = [:]
        for stored in sorted { if let target = stored.record.repeals { repealersOf[target, default: []].append(stored.id) } }
        var memo: [String: Bool] = [:]
        func isRepealed(_ id: String, depth: Int) -> Bool {
            if let known = memo[id] { return known }
            // 효력 있는 폐지 기록 = 그 자신이 폐지되지 않은 폐지 기록.
            let result = depth < 1000
                && (repealersOf[id] ?? []).contains { !isRepealed($0, depth: depth + 1) }
            memo[id] = result
            return result
        }
        repealed = Set(repealersOf.keys.filter { isRepealed($0, depth: 0) })
    }

    /// 현행 — 개정·폐지되지 않았고 스스로 폐지 기록이 아닌 기록.
    public func isInForce(_ id: String) -> Bool {
        guard let stored = byID[id] else { return false }
        return stored.record.repeals == nil && !amended.contains(id) && !repealed.contains(id)
    }

    public var inForce: [LawStoredRecord] { records.filter { isInForce($0.id) } }

    /// 연혁 — 이 기록에서 `amends` 를 따라 과거로(주 사슬).
    public func history(of id: String) -> [LawStoredRecord] {
        var chain: [LawStoredRecord] = []
        var current = byID[id]
        while let stored = current, chain.count < 1000 {
            chain.append(stored)
            current = stored.record.amends.flatMap { byID[$0] }
        }
        return chain
    }

    /// 현행 사실인정 — 이 기록을 `finds` 하는 사실인정 현행판 중 가장 늦게 공포된 것.
    public func currentFinding(for id: String) -> LawStoredRecord? {
        records.filter { stored in
            stored.record.type == LawRecordType.finding.rawValue
                && stored.record.cites.contains { $0.id == id && $0.rel == LawRelation.finds.rawValue }
                && isInForce(stored.id)
        }.last
    }

    /// 4종류 — `record` 유형에만. 다른 유형이거나 없는 기록이면 nil.
    public func memoryKind(of id: String) -> LawMemoryKind? {
        guard let stored = byID[id], stored.record.type == LawRecordType.record.rawValue else { return nil }
        guard let finding = currentFinding(for: id),
              let subject = (try? LawHeadFields.parse(body: finding.record.body, type: finding.record.type))?["subject"]
                .flatMap(LawSubject.init(rawValue:))
        else { return .unclassified }
        switch subject {
        case .person: return .person
        case .project: return .project
        case .external: return .reference
        case .agentSelf:
            return stored.record.speaker == LawSpeaker.user.rawValue ? .feedback : .unclassified
        }
    }

    /// 갈라진 현행 — 같은 기록을 현행판 둘 이상이 개정한 경우. `amends-also` 병합 개정으로 푼다.
    public var divergent: [LawDivergence] {
        var heads: [String: [String]] = [:]
        for stored in records where isInForce(stored.id) {
            for target in Set(stored.record.allAmends) { heads[target, default: []].append(stored.id) }
        }
        return heads.filter { $0.value.count > 1 }
            .map { LawDivergence(amended: $0.key, heads: $0.value.sorted()) }
            .sorted { $0.amended < $1.amended }
    }
}

public struct LawDivergence: Sendable, Equatable {
    public let amended: String
    public let heads: [String]

    public init(amended: String, heads: [String]) {
        self.amended = amended
        self.heads = heads
    }
}
