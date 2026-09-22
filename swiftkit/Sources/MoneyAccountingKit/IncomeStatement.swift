import Foundation

/// 계정과목 한 줄의 집계 — 같은 통화·같은 기간 안의 합.
public struct AccountLine: Codable, Sendable, Equatable {
    public let accountCode: AccountCode
    public let section: AccountSection
    public let amountMinor: Int64
    public let entryCount: Int

    public init(accountCode: AccountCode, amountMinor: Int64, entryCount: Int) {
        self.accountCode = accountCode
        self.section = accountCode.section
        self.amountMinor = amountMinor
        self.entryCount = entryCount
    }
}

/// 단일 통화 손익계산서. 파생 합계(매출총이익·영업이익·세전이익)도 저장 필드로 둔다 — Codable 로
/// CLI `--json` 에 그대로 나가야 소비 앱이 다시 계산하지 않는다. 통화 버킷은 절대 합치지 않는다.
public struct IncomeStatement: Codable, Sendable, Equatable {
    public let period: AccountingPeriod
    public let currency: String
    public let revenueMinor: Int64
    public let costOfSalesMinor: Int64
    public let grossProfitMinor: Int64
    public let sellingAndAdministrativeMinor: Int64
    public let operatingIncomeMinor: Int64
    public let nonOperatingIncomeMinor: Int64
    public let nonOperatingExpenseMinor: Int64
    public let incomeBeforeTaxMinor: Int64
    /// 손익 계정 줄(구획 순 → 표준 표시 순). 자본거래는 여기 없다.
    public let lines: [AccountLine]
    /// 손익에서 제외한 자본거래 줄 — 참고용으로 따로 돌려준다.
    public let capitalTransactionLines: [AccountLine]
    public let entryCount: Int

    public init(
        period: AccountingPeriod,
        currency: String,
        lines: [AccountLine],
        capitalTransactionLines: [AccountLine],
        entryCount: Int
    ) {
        self.period = period
        self.currency = currency
        self.lines = lines
        self.capitalTransactionLines = capitalTransactionLines
        self.entryCount = entryCount
        let total: (AccountSection) -> Int64 = { section in
            lines.filter { $0.section == section }.reduce(0) { $0 + $1.amountMinor }
        }
        revenueMinor = total(.revenue)
        costOfSalesMinor = total(.costOfSales)
        grossProfitMinor = revenueMinor - costOfSalesMinor
        sellingAndAdministrativeMinor = total(.sellingAndAdministrative)
        operatingIncomeMinor = grossProfitMinor - sellingAndAdministrativeMinor
        nonOperatingIncomeMinor = total(.nonOperatingIncome)
        nonOperatingExpenseMinor = total(.nonOperatingExpense)
        incomeBeforeTaxMinor = operatingIncomeMinor + nonOperatingIncomeMinor - nonOperatingExpenseMinor
    }

    public func lines(in section: AccountSection) -> [AccountLine] {
        section == .capitalTransaction ? capitalTransactionLines : lines.filter { $0.section == section }
    }

    public func amount(of code: AccountCode) -> Int64 {
        lines(in: code.section).first { $0.accountCode == code }?.amountMinor ?? 0
    }
}
