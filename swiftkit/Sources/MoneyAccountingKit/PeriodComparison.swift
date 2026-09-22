import Foundation

/// 두 손익계산서의 기간 비교. 증감률은 basis point(1bp = 0.01%) 정수 — Double 을 쓰지 않는다.
/// 이전 값이 0 이면 증감률은 nil(무한대를 숫자로 표기하지 않는다).
public enum PeriodComparison {
    public enum MetricKey: String, Codable, Sendable, CaseIterable {
        case revenue
        case costOfSales
        case grossProfit
        case sellingAndAdministrative
        case operatingIncome
        case nonOperatingIncome
        case nonOperatingExpense
        case incomeBeforeTax

        public func label(korean: Bool) -> String {
            switch self {
            case .revenue: korean ? "매출액" : "Revenue"
            case .costOfSales: korean ? "매출원가" : "Cost of sales"
            case .grossProfit: korean ? "매출총이익" : "Gross profit"
            case .sellingAndAdministrative: korean ? "판매비와관리비" : "Selling and administrative expenses"
            case .operatingIncome: korean ? "영업이익" : "Operating income"
            case .nonOperatingIncome: korean ? "영업외수익" : "Non-operating income"
            case .nonOperatingExpense: korean ? "영업외비용" : "Non-operating expenses"
            case .incomeBeforeTax: korean ? "세전이익" : "Income before tax"
            }
        }

        func value(in statement: IncomeStatement) -> Int64 {
            switch self {
            case .revenue: statement.revenueMinor
            case .costOfSales: statement.costOfSalesMinor
            case .grossProfit: statement.grossProfitMinor
            case .sellingAndAdministrative: statement.sellingAndAdministrativeMinor
            case .operatingIncome: statement.operatingIncomeMinor
            case .nonOperatingIncome: statement.nonOperatingIncomeMinor
            case .nonOperatingExpense: statement.nonOperatingExpenseMinor
            case .incomeBeforeTax: statement.incomeBeforeTaxMinor
            }
        }
    }

    public struct Delta: Codable, Sendable, Equatable {
        public let currentMinor: Int64
        public let previousMinor: Int64
        public let deltaMinor: Int64
        public let changeBasisPoints: Int?

        public init(currentMinor: Int64, previousMinor: Int64) {
            self.currentMinor = currentMinor
            self.previousMinor = previousMinor
            deltaMinor = currentMinor - previousMinor
            changeBasisPoints = PeriodComparison.basisPoints(delta: deltaMinor, previous: previousMinor)
        }
    }

    public struct Metric: Codable, Sendable, Equatable {
        public let key: MetricKey
        public let delta: Delta
    }

    public struct LineDelta: Codable, Sendable, Equatable {
        public let accountCode: AccountCode
        public let delta: Delta
    }

    public struct Report: Codable, Sendable, Equatable {
        public let currency: String
        public let currentPeriod: AccountingPeriod
        public let previousPeriod: AccountingPeriod
        public let metrics: [Metric]
        /// 두 기간 어느 쪽에라도 등장한 손익 계정(표준 표시 순).
        public let lines: [LineDelta]
    }

    public static func compare(current: IncomeStatement, previous: IncomeStatement) throws -> Report {
        guard current.currency == previous.currency else {
            throw PeriodComparisonError.currencyMismatch(current: current.currency, previous: previous.currency)
        }
        let metrics = MetricKey.allCases.map { key in
            Metric(key: key, delta: Delta(currentMinor: key.value(in: current), previousMinor: key.value(in: previous)))
        }
        let codes = Set(current.lines.map(\.accountCode)).union(previous.lines.map(\.accountCode))
        let lines = codes
            .sorted { $0.displayOrder < $1.displayOrder }
            .map { LineDelta(accountCode: $0, delta: Delta(currentMinor: current.amount(of: $0), previousMinor: previous.amount(of: $0))) }
        return Report(
            currency: current.currency,
            currentPeriod: current.period,
            previousPeriod: previous.period,
            metrics: metrics,
            lines: lines
        )
    }

    /// delta ÷ |previous| 를 basis point 로. previous 0 → nil. 0 방향 절사. 곱셈 오버플로면 nil.
    public static func basisPoints(delta: Int64, previous: Int64) -> Int? {
        guard previous != 0 else { return nil }
        let (scaled, overflow) = delta.multipliedReportingOverflow(by: 10_000)
        guard !overflow else { return nil }
        return Int(scaled / previous.magnitude.clampedToInt64)
    }
}

public enum PeriodComparisonError: Error, Equatable, CustomStringConvertible {
    case currencyMismatch(current: String, previous: String)

    public var description: String {
        switch self {
        case let .currencyMismatch(current, previous):
            "통화가 다른 기간은 비교할 수 없습니다: \(current) vs \(previous)"
        }
    }
}

private extension UInt64 {
    /// Int64.max 를 넘는 magnitude(= Int64.min 의 절댓값)만 Int64.max 로 눌러 나눗셈을 안전하게 한다.
    var clampedToInt64: Int64 {
        self > UInt64(Int64.max) ? Int64.max : Int64(self)
    }
}
