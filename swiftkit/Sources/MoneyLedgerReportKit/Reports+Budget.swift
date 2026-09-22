import Foundation
import MoneyLedgerModels

extension Reports {
    // MARK: - 예산 소진율 집계

    /// 카테고리별 예산 소진율 및 잔여액 진행 상황.
    public struct BudgetProgress: Sendable, Equatable, Codable {
        public let category: String
        public let budgetMinor: Int64
        public let spentMinor: Int64
        public let remainingMinor: Int64
        public let progressRatio: Double
        public let isExceeded: Bool

        public init(
            category: String,
            budgetMinor: Int64,
            spentMinor: Int64,
            remainingMinor: Int64,
            progressRatio: Double,
            isExceeded: Bool
        ) {
            self.category = category
            self.budgetMinor = budgetMinor
            self.spentMinor = spentMinor
            self.remainingMinor = remainingMinor
            self.progressRatio = progressRatio
            self.isExceeded = isExceeded
        }
    }

    /// 카테고리별 월간 예산 대비 실제 지출 소진율 및 잔여액을 집계합니다.
    public static func budgetProgress(
        budgets: [MoneyBudget],
        transactions: [MoneyTransaction],
        month: String
    ) -> [BudgetProgress] {
        var effectiveBudgets: [String: MoneyBudget] = [:]
        for budget in budgets {
            if budget.month == month {
                effectiveBudgets[budget.category] = budget
            } else if budget.month == nil && effectiveBudgets[budget.category] == nil {
                effectiveBudgets[budget.category] = budget
            }
        }

        var spentByCategory: [String: Int64] = [:]
        for tx in transactions {
            guard tx.date.hasPrefix(month) else { continue }
            if tx.kind == .transfer || tx.kind == .settlement { continue }
            guard tx.amountMinor < 0 || tx.kind == .expense else { continue }

            let category = (tx.category?.isEmpty == false ? tx.category : nil) ?? uncategorizedLabel
            let spent = abs(tx.amountMinor)
            spentByCategory[category, default: 0] += spent
        }

        return effectiveBudgets.values.map { budget in
            let spent = spentByCategory[budget.category] ?? 0
            let remaining = budget.amountMinor - spent
            let ratio = budget.amountMinor > 0 ? (Double(spent) / Double(budget.amountMinor)) : (spent > 0 ? 1.0 : 0.0)
            let exceeded = spent > budget.amountMinor

            return BudgetProgress(
                category: budget.category,
                budgetMinor: budget.amountMinor,
                spentMinor: spent,
                remainingMinor: remaining,
                progressRatio: ratio,
                isExceeded: exceeded
            )
        }.sorted { $0.category < $1.category }
    }
}
