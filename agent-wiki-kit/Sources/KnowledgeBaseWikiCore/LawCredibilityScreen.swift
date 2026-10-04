import Foundation
import WikiLedgerKit

// 모델 신빙성 화면 표시 모델 — 실행 도구 × 모델 × 추론 강도별 공포 수와 개정·폐지·뒤집힌 비율(`report models` 와 같은 계산,
// `LawModelReport`), 기간(전체·최근 30일), 줄 펼침 = 그 조합이 쓴 기록 중 개정·폐지·뒤집힌 기록.
// 측정만 하고 자동 가중치로 쓰지 않는다(이 값을 읽는 판단 코드는 없다).
// 근거: docs/business-rules.md "드리밍"(보고와 `report models`).

public enum LawCredibilityPeriod: String, CaseIterable, Sendable, Equatable {
    case all
    case last30Days

    public static let recentDays = 30

    /// 이 기간의 시작(전체면 nil).
    public func since(now: Date) -> Date? {
        switch self {
        case .all: return nil
        case .last30Days: return now.addingTimeInterval(-Double(Self.recentDays) * 86_400)
        }
    }
}

/// 줄을 펼쳤을 때 보이는 기록 하나.
public struct LawCredibilityItem: Sendable, Equatable, Identifiable {
    public let record: LawStoredRecord
    public let amended: Bool
    public let repealed: Bool
    public let overturned: Bool

    public var id: String { record.id }
}

public struct LawCredibilityScreen: Sendable {
    public let period: LawCredibilityPeriod
    public let rows: [LawModelReportRow]
    let outcomes: [LawModelReport.Outcome]

    public init(records: [LawStoredRecord], period: LawCredibilityPeriod, now: Date) {
        self.period = period
        let since = period.since(now: now)
        rows = LawModelReport.rows(records: records, since: since)
        outcomes = LawModelReport.outcomes(records: records, since: since)
    }

    public var isEmpty: Bool { rows.isEmpty }

    /// 줄 펼침 — 그 조합이 쓴 기록 중 개정·폐지·뒤집힌 기록(공포 순).
    public func items(for row: LawModelReportRow) -> [LawCredibilityItem] {
        let key = LawModelReport.groupKey(runtime: row.runtime, model: row.model, effort: row.effort)
        return outcomes.filter { $0.groupKey == key && ($0.amended || $0.repealed || $0.overturned) }.map {
            LawCredibilityItem(record: $0.record, amended: $0.amended, repealed: $0.repealed, overturned: $0.overturned)
        }
    }

    /// 원장 하나를 읽어 만든다. 화면은 배경에서 부른다.
    public static func load(target: LawLedgerTarget, period: LawCredibilityPeriod, now: Date = Date()) -> LawCredibilityScreen {
        LawCredibilityScreen(records: target.store.scan(), period: period, now: now)
    }
}
