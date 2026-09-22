import Foundation
import MoneyLedgerKit
import MoneyLedgerReportKit

/// budget 커맨드 — 카테고리별 예산 설정 및 소진율 조회.
enum BudgetCommands {
    static func run(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let action = sub.first ?? "list"
        switch action {
        case "set":
            try await runSet(context: context, scanner: scanner, json: json, output: output)
        case "list":
            try await runList(context: context, scanner: scanner, json: json, output: output)
        case "remove", "delete":
            if scanner.has("help") || scanner.has("h") {
                output.out("사용법: budget remove <카테고리> [--currency KRW]") // --help, -h
                return
            }
            try await runRemove(context: context, sub: Array(sub.dropFirst()), scanner: scanner, json: json, output: output)
        default:
            throw UsageError("알 수 없는 budget 명령: \(action) (set, list 지원)")
        }
    }

    private static func runSet(
        context: LedgerContext, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        guard let category = scanner.value("category"), !category.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw UsageError("--category 는 필수입니다 (예: --category 식비)")
        }
        guard let amountStr = scanner.value("amount") else {
            throw UsageError("--amount 는 필수입니다 (예: --amount 500000)")
        }
        let currency = scanner.value("currency") ?? "KRW"
        let minor = try MoneyAmount.minorUnits(from: amountStr, currency: currency)
        let budget = MoneyBudget(
            category: category.trimmingCharacters(in: .whitespaces),
            amountMinor: minor,
            currency: currency
        )

        let store = try LedgerStore(context: context)
        try await store.save(budget: budget)

        if json {
            output.okJSON([
                "category": budget.category,
                "amount": CLIFormat.amountObject(minor: budget.amountMinor, currency: budget.currency),
                "currency": budget.currency
            ])
        } else {
            output.out("예산 설정 완료: [\(budget.category)] \(MoneyAmount.format(minor: budget.amountMinor, currency: budget.currency))")
        }
    }

    private static func runList(
        context: LedgerContext, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let budgets = try await store.budgets()

        let month = String(LedgerDate.today().prefix(7))
        let range = try LedgerDate.monthRange(month)
        let monthTx = try await store.transactions(TransactionQuery(fromDate: range.from, toDate: range.to))
        let categoryTotals = Reports.categoryTotals(transactions: monthTx)

        struct BudgetRowPayload {
            let budget: MoneyBudget
            let spentMinor: Int64
            let remainingMinor: Int64
            let percentage: Double
            let isExceeded: Bool
        }

        let rows: [BudgetRowPayload] = budgets.map { b in
            let catTotal = categoryTotals.first {
                $0.category == b.category && MoneyAmount.normalizedCurrency($0.currency) == MoneyAmount.normalizedCurrency(b.currency)
            }
            let spent = catTotal.map { $0.totalMinor < 0 ? abs($0.totalMinor) : 0 } ?? 0
            let remaining = b.amountMinor - spent
            let pct = b.amountMinor > 0 ? (Double(spent) / Double(b.amountMinor) * 100.0) : 0.0
            return BudgetRowPayload(
                budget: b,
                spentMinor: spent,
                remainingMinor: remaining,
                percentage: pct,
                isExceeded: spent > b.amountMinor
            )
        }

        if json {
            let list = rows.map { r in
                [
                    "category": r.budget.category,
                    "currency": r.budget.currency,
                    "budget": CLIFormat.amountObject(minor: r.budget.amountMinor, currency: r.budget.currency),
                    "spent": CLIFormat.amountObject(minor: r.spentMinor, currency: r.budget.currency),
                    "remaining": CLIFormat.amountObject(minor: r.remainingMinor, currency: r.budget.currency),
                    "percentage": Double(round(r.percentage * 10) / 10),
                    "exceeded": r.isExceeded
                ]
            }
            output.okJSON(["month": month, "budgets": list])
        } else {
            if rows.isEmpty {
                output.out("설정된 예산이 없습니다. (budget set --category <카테고리> --amount <금액>)")
                return
            }
            output.out("================== 이번 달 예산 현황 (\(month)) ==================")
            for r in rows {
                let limitStr = MoneyAmount.format(minor: r.budget.amountMinor, currency: r.budget.currency)
                let spentStr = MoneyAmount.format(minor: r.spentMinor, currency: r.budget.currency)
                let remStr = MoneyAmount.format(minor: r.remainingMinor, currency: r.budget.currency)
                let pctStr = String(format: "%5.1f%%", r.percentage)
                let statusBadge = r.isExceeded ? " [초과!]" : ""
                let bar = renderBar(percentage: r.percentage)
                output.out("[\(r.budget.category)] 예산: \(limitStr) | 지출: \(spentStr) | 잔여: \(remStr) | \(pctStr)\(statusBadge)")
                output.out("  \(bar)")
            }
            output.out("================================================================")
        }
    }

    private static func runRemove(
        context: LedgerContext, sub: [String], scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        guard let target = sub.first ?? scanner.value("category") else {
            throw UsageError("삭제할 카테고리를 지정하세요: budget remove <카테고리>")
        }
        let currency = scanner.value("currency") ?? "KRW"
        let store = try LedgerStore(context: context)
        try await store.deleteBudget(category: target, currency: currency)
        if json {
            output.okJSON(["category": target, "currency": currency, "deleted": true])
        } else {
            output.out("예산 삭제 완료: [\(target)] (\(currency))")
        }
    }

    private static func renderBar(percentage: Double) -> String {
        let count = max(0, min(20, Int((percentage / 5.0).rounded())))
        let filled = String(repeating: "■", count: count)
        let empty = String(repeating: "□", count: max(0, 20 - count))
        return "[\(filled)\(empty)]"
    }
}
