import Foundation
import MoneyLedgerKit
import MoneyLedgerReportKit

typealias NetWorthReport = Reports.NetWorthReport
typealias AssetGroupShare = Reports.NetWorthReport.GroupBreakdown

/// net-worth 커맨드 — 순자산 요약 및 자산군별 비중 출력.
enum NetWorthCommand {
    static func run(
        context: LedgerContext, scanner: ArgScanner, json: Bool, output: CLIOutput
    ) async throws {
        let store = try LedgerStore(context: context)
        let accounts = try await store.accounts(includeArchived: false)
        let cards = try await store.cards(includeArchived: false)
        let transactions = try await store.transactions(TransactionQuery())

        let reports = Reports.netWorth(accounts: accounts, cards: cards, transactions: transactions)

        if json {
            renderJSON(reports: reports, output: output)
        } else {
            renderText(reports: reports, output: output)
        }
    }

    private static func renderJSON(reports: [NetWorthReport], output: CLIOutput) {
        let reportsPayload = reports.map { report -> [String: Any] in
            let assetGroups = report.assetGroups.map { g -> [String: Any] in
                [
                    "type": g.type,
                    "label": g.label,
                    "amount": CLIFormat.amountObject(minor: g.amountMinor, currency: report.currency),
                    "percentage": Double(round(g.percentage * 10) / 10),
                ]
            }
            let liabilityGroups = report.liabilityGroups.map { g -> [String: Any] in
                [
                    "type": g.type,
                    "label": g.label,
                    "amount": CLIFormat.amountObject(minor: g.amountMinor, currency: report.currency),
                    "percentage": Double(round(g.percentage * 10) / 10),
                ]
            }
            return [
                "currency": report.currency,
                "totalAssets": CLIFormat.amountObject(minor: report.totalAssetsMinor, currency: report.currency),
                "totalLiabilities": CLIFormat.amountObject(minor: report.totalLiabilitiesMinor, currency: report.currency),
                "netWorth": CLIFormat.amountObject(minor: report.netWorthMinor, currency: report.currency),
                "assetGroups": assetGroups,
                "liabilityGroups": liabilityGroups,
            ]
        }
        output.okJSON(["reports": reportsPayload])
    }

    private static func renderText(reports: [NetWorthReport], output: CLIOutput) {
        for (idx, report) in reports.enumerated() {
            if idx > 0 { output.out("") }
            output.out("================== 순자산 요약 [\(report.currency)] ==================")
            output.out("총자산:    \(MoneyAmount.format(minor: report.totalAssetsMinor, currency: report.currency))")
            output.out("총부채:    \(MoneyAmount.format(minor: report.totalLiabilitiesMinor, currency: report.currency))")
            output.out("순자산:    \(MoneyAmount.format(minor: report.netWorthMinor, currency: report.currency))")

            renderGroups(title: "--- 자산군별 구성 ---", groups: report.assetGroups, currency: report.currency, output: output)
            renderGroups(title: "--- 부채 구성 ---", groups: report.liabilityGroups, currency: report.currency, output: output)
            output.out("=======================================================")
        }
    }

    private static func renderGroups(title: String, groups: [AssetGroupShare], currency: String, output: CLIOutput) {
        guard !groups.isEmpty else { return }
        output.out("")
        output.out(title)
        for group in groups {
            let formatted = MoneyAmount.format(minor: group.amountMinor, currency: currency)
            let pctStr = String(format: "%5.1f%%", group.percentage)
            let bars = renderBar(percentage: group.percentage)
            output.out("  [\(group.label)]  \(formatted) (\(pctStr))  \(bars)")
        }
    }

    private static func renderBar(percentage: Double) -> String {
        let count = max(0, min(20, Int((percentage / 5.0).rounded())))
        return String(repeating: "■", count: count)
    }
}
