import Foundation
import MoneyLedgerModels

/// 회계 기간 — 양끝 포함 "yyyy-MM-dd" 범위. 문자열 사전순이 날짜순이라 포함 판정이 비교 두 번이다.
public struct AccountingPeriod: Codable, Sendable, Equatable, Hashable {
    public let from: String
    public let to: String

    /// "2026.05.06"·"2026/5/6" 표기도 받되 정규화된 "yyyy-MM-dd" 로 저장한다 — 포함 판정이 사전순이라
    /// 구분자가 섞이면 조용히 틀린다.
    public init(from: String, to: String) throws {
        let normalizedFrom = try Self.normalized(from)
        let normalizedTo = try Self.normalized(to)
        guard normalizedFrom <= normalizedTo else {
            throw AccountingPeriodError.reversed(from: normalizedFrom, to: normalizedTo)
        }
        self.from = normalizedFrom
        self.to = normalizedTo
    }

    /// LedgerDate 의 해석 오류를 이 타입의 오류로 바꿔 던진다(삼키지 않는다).
    static func normalized(_ raw: String) throws -> String {
        do {
            return try LedgerDate.normalize(raw).date
        } catch {
            throw AccountingPeriodError.invalidDate(raw)
        }
    }

    private init(validFrom: String, validTo: String) {
        from = validFrom
        to = validTo
    }

    public func contains(_ date: String) -> Bool {
        from <= date && date <= to
    }

    /// "yyyy-MM" 한 달.
    public static func month(_ month: String) throws -> AccountingPeriod {
        let range = try LedgerDate.monthRange(month)
        let parts = month.components(separatedBy: "-")
        guard parts.count == 2, let year = Int(parts[0]), let monthNumber = Int(parts[1]) else {
            throw AccountingPeriodError.invalidDate(month)
        }
        let last = Self.lastDay(year: year, month: monthNumber)
        return AccountingPeriod(validFrom: range.from, validTo: String(format: "%04d-%02d-%02d", year, monthNumber, last))
    }

    public static func year(_ year: Int) -> AccountingPeriod {
        AccountingPeriod(validFrom: String(format: "%04d-01-01", year), validTo: String(format: "%04d-12-31", year))
    }

    /// 상반기(1/1~6/30)·하반기(7/1~12/31) — 부가세 과세기간과 같은 절단.
    public static func half(year: Int, first: Bool) -> AccountingPeriod {
        first
            ? AccountingPeriod(validFrom: String(format: "%04d-01-01", year), validTo: String(format: "%04d-06-30", year))
            : AccountingPeriod(validFrom: String(format: "%04d-07-01", year), validTo: String(format: "%04d-12-31", year))
    }

    /// 분기(1~4). 범위 밖 분기는 throw.
    public static func quarter(year: Int, quarter: Int) throws -> AccountingPeriod {
        guard (1...4).contains(quarter) else { throw AccountingPeriodError.invalidQuarter(quarter) }
        let firstMonth = (quarter - 1) * 3 + 1
        let lastMonth = firstMonth + 2
        let last = lastDay(year: year, month: lastMonth)
        return AccountingPeriod(
            validFrom: String(format: "%04d-%02d-01", year, firstMonth),
            validTo: String(format: "%04d-%02d-%02d", year, lastMonth, last)
        )
    }

    /// 직전 같은 길이 기간 — 월이면 전월, 연이면 전년, 임의 범위면 같은 일수만큼 앞.
    public func previous(calendar: Calendar = .current) -> AccountingPeriod? {
        guard let fromDate = LedgerDate.toDate(from, calendar: calendar),
              let toDate = LedgerDate.toDate(to, calendar: calendar) else { return nil }
        let days = (calendar.dateComponents([.day], from: fromDate, to: toDate).day ?? 0) + 1
        guard let previousTo = calendar.date(byAdding: .day, value: -1, to: fromDate),
              let previousFrom = calendar.date(byAdding: .day, value: -days, to: fromDate) else { return nil }
        return AccountingPeriod(
            validFrom: LedgerDate.format(previousFrom, calendar: calendar),
            validTo: LedgerDate.format(previousTo, calendar: calendar)
        )
    }

    public func label(korean: Bool) -> String {
        korean ? "\(from) ~ \(to)" : "\(from) to \(to)"
    }

    static func lastDay(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let first = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        let count = first.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count }
        return count ?? 31
    }
}

public enum AccountingPeriodError: Error, Equatable, CustomStringConvertible {
    case invalidDate(String)
    case reversed(from: String, to: String)
    case invalidQuarter(Int)

    public var description: String {
        switch self {
        case let .invalidDate(raw): "회계 기간 날짜를 해석할 수 없습니다: \(raw) (yyyy-MM-dd)"
        case let .reversed(from, to): "회계 기간의 시작이 끝보다 늦습니다: \(from) > \(to)"
        case let .invalidQuarter(quarter): "분기는 1~4 사이여야 합니다: \(quarter)"
        }
    }
}
