import Foundation
import MoneyLedgerModels

/// 계정 붙은 금액들 → 손익계산서. 저장소 없이 입력 배열 위의 순수 함수다.
public struct IncomeStatementBuilder: Sendable {
    public let amounts: [AccountedAmount]

    public init(amounts: [AccountedAmount]) {
        self.amounts = amounts
    }

    /// 한 통화의 손익계산서. 기간 밖·다른 통화 항목은 제외한다(환율 없음 원칙 — 통화를 섞지 않는다).
    public func build(period: AccountingPeriod, currency: String = "KRW") -> IncomeStatement {
        let wanted = MoneyAmount.normalizedCurrency(currency)
        let selected = amounts.filter { $0.currency == wanted && period.contains($0.date) }
        let lines = Self.aggregate(selected)
        return IncomeStatement(
            period: period,
            currency: wanted,
            lines: lines.filter { $0.section.affectsIncome },
            capitalTransactionLines: lines.filter { !$0.section.affectsIncome },
            entryCount: selected.count
        )
    }

    /// 기간 안에 등장한 통화마다 한 장씩(통화 사전순). 항목이 없는 통화는 만들지 않는다.
    public func buildAll(period: AccountingPeriod) -> [IncomeStatement] {
        let currencies = Set(amounts.filter { period.contains($0.date) }.map(\.currency))
        return currencies.sorted().map { build(period: period, currency: $0) }
    }

    /// 계정별 합계 → 구획 순, 표준 표시 순으로 정렬한 줄.
    static func aggregate(_ selected: [AccountedAmount]) -> [AccountLine] {
        var totals: [AccountCode: (amount: Int64, count: Int)] = [:]
        for item in selected {
            var bucket = totals[item.accountCode] ?? (0, 0)
            bucket.amount += item.amountMinor
            bucket.count += 1
            totals[item.accountCode] = bucket
        }
        return totals
            .map { AccountLine(accountCode: $0.key, amountMinor: $0.value.amount, entryCount: $0.value.count) }
            .sorted { $0.accountCode.displayOrder < $1.accountCode.displayOrder }
    }
}
