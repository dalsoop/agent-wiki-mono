import Foundation
import MoneyLedgerKit

extension SyncCommands {
    static func renderMergeJSON(report: SyncMergeReport, dryRun: Bool, output: CLIOutput) {
        output.okJSON([
            "status": "merged",
            "dryRun": dryRun,
            "added": [
                "accounts": report.accountsAdded,
                "cards": report.cardsAdded,
                "subscriptions": report.subscriptionsAdded,
                "budgets": report.budgetsAdded,
                "recurringTemplates": report.recurringTemplatesAdded,
                "businesses": report.businessesAdded,
                "transactions": report.transactionsAdded,
                "total": report.totalEntitiesAdded
            ],
            "deleted": [
                "accounts": report.accountsDeleted,
                "cards": report.cardsDeleted,
                "subscriptions": report.subscriptionsDeleted,
                "budgets": report.budgetsDeleted,
                "recurringTemplates": report.recurringTemplatesDeleted,
                "businesses": report.businessesDeleted,
                "transactions": report.transactionsDeleted,
                "total": report.totalEntitiesDeleted
            ],
            "tombstonesAdded": report.tombstonesAdded,
            "local": [
                "accounts": report.localAccountsCount,
                "cards": report.localCardsCount,
                "subscriptions": report.localSubscriptionsCount,
                "budgets": report.localBudgetsCount,
                "transactions": report.localTransactionsCount
            ],
            "remote": [
                "accounts": report.remoteAccountsCount,
                "cards": report.remoteCardsCount,
                "subscriptions": report.remoteSubscriptionsCount,
                "budgets": report.remoteBudgetsCount,
                "transactions": report.remoteTransactionsCount
            ]
        ])
    }

    static func renderMergeText(
        report: SyncMergeReport,
        dryRun: Bool,
        remoteHost: String,
        output: CLIOutput
    ) {
        output.out("=== 양방향 무손실 멱등 병합(Two-Way Lossless Idempotent Merge) 완료 ===")
        renderDryRunNotice(dryRun: dryRun, output: output)
        output.out("1. 계좌(Accounts): 로컬 \(report.localAccountsCount)개 / 원격 \(report.remoteAccountsCount)개 (+신규 \(report.accountsAdded)개)")
        output.out("2. 카드(Cards): 로컬 \(report.localCardsCount)개 / 원격 \(report.remoteCardsCount)개 (+신규 \(report.cardsAdded)개)")
        output.out("3. 구독(Subscriptions): 로컬 \(report.localSubscriptionsCount)개 / 원격 \(report.remoteSubscriptionsCount)개 (+신규 \(report.subscriptionsAdded)개)")
        output.out("4. 예산(Budgets): 로컬 \(report.localBudgetsCount)개 / 원격 \(report.remoteBudgetsCount)개 (+신규 \(report.budgetsAdded)개)")
        output.out("5. 거래(Transactions): 로컬 \(report.localTransactionsCount)건 / 원격 \(report.remoteTransactionsCount)건 (+신규 \(report.transactionsAdded)건)")
        renderOptionalMetrics(report: report, output: output)
        output.out("--------------------------------------------------")
        output.out("총 병합된 신규 엔티티: \(report.totalEntitiesAdded)건 (삭제 반영: \(report.totalEntitiesDeleted)건)")
        renderCompletionNotice(dryRun: dryRun, remoteHost: remoteHost, output: output)
    }

    private static func renderDryRunNotice(dryRun: Bool, output: CLIOutput) {
        guard dryRun else { return }
        output.out("[dry-run] 실제 파일 변경 없이 병합 시뮬레이션을 수행했습니다.")
    }

    private static func renderOptionalMetrics(report: SyncMergeReport, output: CLIOutput) {
        if [report.recurringTemplatesAdded, report.businessesAdded].contains(where: { $0 > 0 }) {
            output.out("6. 기타: 고정비 +\(report.recurringTemplatesAdded)건 / 사업자 +\(report.businessesAdded)건 병합")
        }
        if report.totalEntitiesDeleted > 0 {
            output.out("7. 툼스톤 삭제 전파(Delete Propagation): 총 \(report.totalEntitiesDeleted)건 삭제 전파 완료 (거래 \(report.transactionsDeleted)건, 계좌 \(report.accountsDeleted)개, 카드 \(report.cardsDeleted)개, 구독 \(report.subscriptionsDeleted)개, 예산 \(report.budgetsDeleted)개 등)")
        }
    }

    private static func renderCompletionNotice(dryRun: Bool, remoteHost: String, output: CLIOutput) {
        guard !dryRun else { return }
        output.out("✓ 로컬 완전체(Union) 원장이 원격(\(remoteHost))으로 안전하게 동기화되었습니다.")
    }
}
