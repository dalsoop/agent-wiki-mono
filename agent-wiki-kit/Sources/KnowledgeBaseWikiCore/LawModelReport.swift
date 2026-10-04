import Foundation
import WikiLedgerKit

// `report models` — 모델·추론 강도·실행 도구별 공포 건수와, 그 기록이 나중에 개정된 비율·폐지된 비율·이의 제기되고
// 뒤집힌 비율. 측정만 하고 자동 가중치로 쓰지 않는다(이 값을 읽는 판단 코드는 없다).
// 근거: docs/business-rules.md "드리밍"(보고), docs/contracts.md `report models [--since <t>]`.
// 대상: 판단이 담긴 기록 — 지식 기록(record·article·judgment)과 사실인정(finding).

public struct LawModelReportRow: Codable, Sendable, Equatable {
    public var runtime: String
    public var model: String
    public var effort: String
    public var enacted: Int
    public var amended: Int
    public var repealed: Int
    /// 이의(appeal)를 받고 결정으로 뒤집힌 건수.
    public var overturned: Int

    public var amendedRate: Double { rate(amended) }
    public var repealedRate: Double { rate(repealed) }
    public var overturnedRate: Double { rate(overturned) }

    func rate(_ count: Int) -> Double { enacted == 0 ? 0 : Double(count) / Double(enacted) }

    enum CodingKeys: String, CodingKey {
        case runtime, model, effort, enacted, amended, repealed, overturned, amendedRate, repealedRate, overturnedRate
    }

    public init(runtime: String, model: String, effort: String, enacted: Int, amended: Int, repealed: Int, overturned: Int) {
        self.runtime = runtime
        self.model = model
        self.effort = effort
        self.enacted = enacted
        self.amended = amended
        self.repealed = repealed
        self.overturned = overturned
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            runtime: try c.decode(String.self, forKey: .runtime), model: try c.decode(String.self, forKey: .model),
            effort: try c.decode(String.self, forKey: .effort), enacted: try c.decode(Int.self, forKey: .enacted),
            amended: try c.decode(Int.self, forKey: .amended), repealed: try c.decode(Int.self, forKey: .repealed),
            overturned: try c.decode(Int.self, forKey: .overturned))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(runtime, forKey: .runtime)
        try c.encode(model, forKey: .model)
        try c.encode(effort, forKey: .effort)
        try c.encode(enacted, forKey: .enacted)
        try c.encode(amended, forKey: .amended)
        try c.encode(repealed, forKey: .repealed)
        try c.encode(overturned, forKey: .overturned)
        try c.encode(amendedRate, forKey: .amendedRate)
        try c.encode(repealedRate, forKey: .repealedRate)
        try c.encode(overturnedRate, forKey: .overturnedRate)
    }
}

public enum LawModelReport {
    /// 값이 없는 칸의 표기.
    public static let none = "-"

    static let judgedTypes: Set<String> = Set(LawRecordType.knowledgeTypes.map(\.rawValue) + [LawRecordType.finding.rawValue])

    /// 원장 기록에서 계산한다. `since` 가 있으면 그 뒤에 공포된 기록만 센다(개정·폐지·뒤집힘은 지금까지의 전체 기록으로 본다).
    public static func rows(records: [LawStoredRecord], since: Date? = nil) -> [LawModelReportRow] {
        let view = LawLedgerView(records: records)
        let amended = Set(records.flatMap(\.record.allAmends))
        let overturned = overturnedTargets(records: records, view: view)
        var groups: [String: LawModelReportRow] = [:]
        var order: [String] = []
        for stored in records where judgedTypes.contains(stored.record.type ?? "") && stored.record.repeals == nil {
            if let since, stored.record.promulgated < since { continue }
            let record = stored.record
            let key = [record.runtime ?? none, record.model ?? none, record.effort ?? none]
            let id = key.joined(separator: "\u{1F}")
            if groups[id] == nil {
                groups[id] = LawModelReportRow(
                    runtime: key[0], model: key[1], effort: key[2], enacted: 0, amended: 0, repealed: 0, overturned: 0)
                order.append(id)
            }
            groups[id]?.enacted += 1
            if amended.contains(stored.id) { groups[id]?.amended += 1 }
            if view.repealed.contains(stored.id) { groups[id]?.repealed += 1 }
            if overturned.contains(stored.id) { groups[id]?.overturned += 1 }
        }
        return order.compactMap { groups[$0] }
            .sorted {
                $0.enacted != $1.enacted
                    ? $0.enacted > $1.enacted : ($0.runtime, $0.model, $0.effort) < ($1.runtime, $1.model, $1.effort)
            }
    }

    /// 이의를 받고 현행 결정이 뒤집은(overturn·승인) 기록.
    static func overturnedTargets(records: [LawStoredRecord], view: LawLedgerView) -> Set<String> {
        var appealTarget: [String: String] = [:]
        for stored in records where stored.record.type == LawRecordType.appeal.rawValue {
            if let target = stored.record.cites.first(where: { $0.rel == LawRelation.appeals.rawValue })?.id {
                appealTarget[stored.id] = target
            }
        }
        var result: Set<String> = []
        for ruling in records where ruling.record.type == LawRecordType.ruling.rawValue && view.isInForce(ruling.id) {
            guard let head = LawCourtDocket.rulingHead(ruling), head.outcome == .overturn || head.outcome == .approve else {
                continue
            }
            for cite in ruling.record.cites where cite.rel == LawRelation.hears.rawValue {
                if let target = appealTarget[cite.id] { result.insert(target) }
            }
        }
        return result
    }
}
