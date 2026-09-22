import Foundation
import os
import MoneyLedgerModels

struct SyncTombstoneContext: Sendable {
    let remoteAccounts: Set<String>
    let remoteCards: Set<String>
    let remoteSubscriptions: Set<String>
    let remoteBudgets: Set<String>
    let remoteTemplates: Set<String>
    let remoteBusinesses: Set<String>
    let remoteTxIDs: Set<String>
    let remoteTxHashes: Set<String>

    let combinedAccounts: Set<String>
    let combinedCards: Set<String>
    let combinedSubscriptions: Set<String>
    let combinedBudgets: Set<String>
    let combinedTemplates: Set<String>
    let combinedBusinesses: Set<String>
    let combinedTxIDs: Set<String>
    let combinedTxHashes: Set<String>

    let remoteTombstones: [TombstoneRecord]
    let localTombstones: [TombstoneRecord]
}

/// 양방향 무손실 멱등 원장 동기화 엔진.
public enum LedgerSyncEngine {
    private static let logger = Logger(subsystem: "MoneyLedgerStoreKit", category: "LedgerSyncEngine")

    @discardableResult
    public static func merge(
        from source: LedgerStore,
        into target: LedgerStore,
        dryRun: Bool = false
    ) async throws -> SyncMergeReport {
        let context = try await collectTombstones(source: source, target: target)
        let deletions = try await applyRemoteDeletions(target: target, context: context, dryRun: dryRun)

        let bizResult = try await mergeBusinesses(source: source, target: target, context: context, dryRun: dryRun)
        let accResult = try await mergeAccounts(source: source, target: target, context: context, dryRun: dryRun)
        let cardResult = try await mergeCards(source: source, target: target, context: context, dryRun: dryRun)
        let subResult = try await mergeSubscriptions(source: source, target: target, context: context, dryRun: dryRun)
        let budgetResult = try await mergeBudgets(source: source, target: target, context: context, dryRun: dryRun)
        let tmplResult = try await mergeTemplates(source: source, target: target, context: context, dryRun: dryRun)
        let txsAdded = try await mergeTransactions(source: source, target: target, context: context, dryRun: dryRun)
        let tombstonesAdded = try await mergeTombstones(target: target, context: context, dryRun: dryRun)

        let added = SyncEntityCounts(
            accounts: accResult.added,
            cards: cardResult.added,
            subscriptions: subResult.added,
            budgets: budgetResult.added,
            recurringTemplates: tmplResult.added,
            businesses: bizResult.added,
            transactions: txsAdded
        )
        let updated = SyncEntityCounts(
            accounts: accResult.updated,
            cards: cardResult.updated,
            subscriptions: subResult.updated,
            budgets: budgetResult.updated,
            recurringTemplates: tmplResult.updated,
            businesses: bizResult.updated
        )
        return try await buildReport(
            target: target,
            source: source,
            added: added,
            updated: updated,
            deleted: deletions,
            tombstonesAdded: tombstonesAdded
        )
    }

    private static func collectTombstones(source: LedgerStore, target: LedgerStore) async throws -> SyncTombstoneContext {
        let localTombstones = try await target.tombstones()
        let remoteTombstones = try await source.tombstones()
        let localMap = Dictionary(grouping: localTombstones, by: \.entityType)
        let remoteMap = Dictionary(grouping: remoteTombstones, by: \.entityType)

        func setFor(_ map: [String: [TombstoneRecord]], _ key: String) -> Set<String> {
            Set(map[key]?.map(\.entityID) ?? [])
        }

        let remAcc = setFor(remoteMap, "account")
        let remCard = setFor(remoteMap, "card")
        let remSub = setFor(remoteMap, "subscription")
        let remBud = setFor(remoteMap, "budget")
        let remTmpl = setFor(remoteMap, "recurring_template")
        let remBiz = setFor(remoteMap, "business")
        let remTxID = setFor(remoteMap, "transaction")
        let remTxHash = setFor(remoteMap, "transaction_hash")

        let locAcc = setFor(localMap, "account")
        let locCard = setFor(localMap, "card")
        let locSub = setFor(localMap, "subscription")
        let locBud = setFor(localMap, "budget")
        let locTmpl = setFor(localMap, "recurring_template")
        let locBiz = setFor(localMap, "business")
        let locTxID = setFor(localMap, "transaction")
        let locTxHash = setFor(localMap, "transaction_hash")

        return SyncTombstoneContext(
            remoteAccounts: remAcc,
            remoteCards: remCard,
            remoteSubscriptions: remSub,
            remoteBudgets: remBud,
            remoteTemplates: remTmpl,
            remoteBusinesses: remBiz,
            remoteTxIDs: remTxID,
            remoteTxHashes: remTxHash,
            combinedAccounts: locAcc.union(remAcc),
            combinedCards: locCard.union(remCard),
            combinedSubscriptions: locSub.union(remSub),
            combinedBudgets: locBud.union(remBud),
            combinedTemplates: locTmpl.union(remTmpl),
            combinedBusinesses: locBiz.union(remBiz),
            combinedTxIDs: locTxID.union(remTxID),
            combinedTxHashes: locTxHash.union(remTxHash),
            remoteTombstones: remoteTombstones,
            localTombstones: localTombstones
        )
    }

    private static func applyRemoteDeletions(
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> SyncEntityCounts {
        var counts = SyncEntityCounts()
        let localTxs = try await target.transactions(TransactionQuery())
        for tx in localTxs where context.remoteTxIDs.contains(tx.id) || context.remoteTxHashes.contains(tx.contentHash) {
            guard !dryRun else { counts.transactions += 1; continue }
            try await target.deleteTransaction(id: tx.id)
            counts.transactions += 1
        }

        let localTemplates = try await target.recurringTemplates(activeOnly: false)
        for tmpl in localTemplates where context.remoteTemplates.contains(tmpl.id) {
            guard !dryRun else { counts.recurringTemplates += 1; continue }
            try await target.deleteRecurringTemplate(id: tmpl.id)
            counts.recurringTemplates += 1
        }

        let localBudgets = try await target.budgets(month: nil)
        for budget in localBudgets where context.remoteBudgets.contains(budget.id) {
            guard !dryRun else { counts.budgets += 1; continue }
            try await target.deleteBudget(id: budget.id)
            counts.budgets += 1
        }

        let localSubs = try await target.subscriptions(includeArchived: true)
        for sub in localSubs where context.remoteSubscriptions.contains(sub.id) {
            guard !dryRun else { counts.subscriptions += 1; continue }
            try await target.deleteSubscription(id: sub.id)
            counts.subscriptions += 1
        }

        counts.cards = try await deleteCardsWithTombstones(target: target, tombstones: context.remoteCards, dryRun: dryRun)
        counts.accounts = try await deleteAccountsWithTombstones(target: target, tombstones: context.remoteAccounts, dryRun: dryRun)

        let localBiz = try await target.businesses(includeArchived: true)
        for b in localBiz where context.remoteBusinesses.contains(b.id) {
            guard !dryRun else { counts.businesses += 1; continue }
            _ = try await target.deleteBusiness(id: b.id)
            counts.businesses += 1
        }
        return counts
    }

    private static func deleteCardsWithTombstones(target: LedgerStore, tombstones: Set<String>, dryRun: Bool) async throws -> Int {
        var count = 0
        let localCards = try await target.cards(includeArchived: true)
        for card in localCards where tombstones.contains(card.id) {
            guard !dryRun else { count += 1; continue }
            do {
                try await target.deleteCard(id: card.id)
                count += 1
            } catch {
                logger.notice("카드 삭제 건너뜀 (참조 거래 존재): \(error.localizedDescription)")
            }
        }
        return count
    }

    private static func deleteAccountsWithTombstones(target: LedgerStore, tombstones: Set<String>, dryRun: Bool) async throws -> Int {
        var count = 0
        let localAccounts = try await target.accounts(includeArchived: true)
        for acc in localAccounts where tombstones.contains(acc.id) {
            guard !dryRun else { count += 1; continue }
            do {
                try await target.deleteAccount(id: acc.id)
                count += 1
            } catch {
                logger.notice("계좌 삭제 건너뜀 (참조 거래/카드 존재): \(error.localizedDescription)")
            }
        }
        return count
    }

    private static func buildReport(
        target: LedgerStore,
        source: LedgerStore,
        added: SyncEntityCounts,
        updated: SyncEntityCounts,
        deleted: SyncEntityCounts,
        tombstonesAdded: Int
    ) async throws -> SyncMergeReport {
        let localCounts = SyncSnapshotCounts(
            accounts: (try await target.accounts(includeArchived: true)).count,
            cards: (try await target.cards(includeArchived: true)).count,
            subscriptions: (try await target.subscriptions(includeArchived: true)).count,
            budgets: (try await target.budgets(month: nil)).count,
            transactions: (try await target.transactions(TransactionQuery())).count
        )
        let remoteCounts = SyncSnapshotCounts(
            accounts: (try await source.accounts(includeArchived: true)).count,
            cards: (try await source.cards(includeArchived: true)).count,
            subscriptions: (try await source.subscriptions(includeArchived: true)).count,
            budgets: (try await source.budgets(month: nil)).count,
            transactions: (try await source.transactions(TransactionQuery())).count
        )
        return SyncMergeReport(
            added: added,
            updated: updated,
            deleted: deleted,
            tombstonesAdded: tombstonesAdded,
            localCounts: localCounts,
            remoteCounts: remoteCounts
        )
    }
}
