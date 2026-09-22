import Foundation
import MoneyLedgerModels

extension LedgerSyncEngine {
    static func mergeBusinesses(
        source: LedgerStore,
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> (added: Int, updated: Int) {
        let local = Dictionary(uniqueKeysWithValues: (try await target.businesses(includeArchived: true)).map { ($0.id, $0) })
        let remote = try await source.businesses(includeArchived: true)
        var added = 0, updated = 0
        for b in remote where !context.combinedBusinesses.contains(b.id) {
            guard let loc = local[b.id] else {
                if !dryRun { try await target.save(business: b) }
                added += 1
                continue
            }
            let isNewer = isRemoteNewer(
                remoteUpdated: b.updatedAt, remoteCreated: b.createdAt,
                localUpdated: loc.updatedAt, localCreated: loc.createdAt
            )
            guard loc != b, isNewer else { continue }
            if !dryRun { try await target.save(business: b) }
            updated += 1
        }
        return (added, updated)
    }

    static func mergeAccounts(
        source: LedgerStore,
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> (added: Int, updated: Int) {
        let local = Dictionary(uniqueKeysWithValues: (try await target.accounts(includeArchived: true)).map { ($0.id, $0) })
        let remote = try await source.accounts(includeArchived: true)
        var added = 0, updated = 0
        for acc in remote where !context.combinedAccounts.contains(acc.id) {
            guard let loc = local[acc.id] else {
                if !dryRun { try await target.save(account: acc) }
                added += 1
                continue
            }
            let isNewer = isRemoteNewer(
                remoteUpdated: acc.updatedAt, remoteCreated: acc.createdAt,
                localUpdated: loc.updatedAt, localCreated: loc.createdAt
            )
            guard loc != acc, isNewer else { continue }
            if !dryRun { try await target.save(account: acc) }
            updated += 1
        }
        return (added, updated)
    }

    static func mergeCards(
        source: LedgerStore,
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> (added: Int, updated: Int) {
        let local = Dictionary(uniqueKeysWithValues: (try await target.cards(includeArchived: true)).map { ($0.id, $0) })
        let remote = try await source.cards(includeArchived: true)
        var added = 0, updated = 0
        for card in remote where !context.combinedCards.contains(card.id) {
            guard let loc = local[card.id] else {
                if !dryRun { try await target.save(card: card) }
                added += 1
                continue
            }
            let isNewer = isRemoteNewer(
                remoteUpdated: card.updatedAt, remoteCreated: card.createdAt,
                localUpdated: loc.updatedAt, localCreated: loc.createdAt
            )
            guard loc != card, isNewer else { continue }
            if !dryRun { try await target.save(card: card) }
            updated += 1
        }
        return (added, updated)
    }

    static func mergeSubscriptions(
        source: LedgerStore,
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> (added: Int, updated: Int) {
        let local = Dictionary(uniqueKeysWithValues: (try await target.subscriptions(includeArchived: true)).map { ($0.id, $0) })
        let remote = try await source.subscriptions(includeArchived: true)
        var added = 0, updated = 0
        for sub in remote where !context.combinedSubscriptions.contains(sub.id) {
            guard let loc = local[sub.id] else {
                if !dryRun { try await target.save(subscription: sub) }
                added += 1
                continue
            }
            let isNewer = isRemoteNewer(
                remoteUpdated: sub.updatedAt, remoteCreated: sub.createdAt,
                localUpdated: loc.updatedAt, localCreated: loc.createdAt
            )
            guard loc != sub, isNewer else { continue }
            if !dryRun { try await target.save(subscription: sub) }
            updated += 1
        }
        return (added, updated)
    }

    static func mergeBudgets(
        source: LedgerStore,
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> (added: Int, updated: Int) {
        let local = Dictionary(uniqueKeysWithValues: (try await target.budgets(month: nil)).map { ($0.id, $0) })
        let remote = try await source.budgets(month: nil)
        var added = 0, updated = 0
        for budget in remote where !context.combinedBudgets.contains(budget.id) {
            guard let loc = local[budget.id] else {
                if !dryRun { try await target.save(budget: budget) }
                added += 1
                continue
            }
            let isNewer = isRemoteNewer(
                remoteUpdated: budget.updatedAt, remoteCreated: budget.createdAt,
                localUpdated: loc.updatedAt, localCreated: loc.createdAt
            )
            guard loc != budget, isNewer else { continue }
            if !dryRun { try await target.save(budget: budget) }
            updated += 1
        }
        return (added, updated)
    }

    static func mergeTemplates(
        source: LedgerStore,
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> (added: Int, updated: Int) {
        let local = Dictionary(uniqueKeysWithValues: (try await target.recurringTemplates(activeOnly: false)).map { ($0.id, $0) })
        let remote = try await source.recurringTemplates(activeOnly: false)
        var added = 0, updated = 0
        for tmpl in remote where !context.combinedTemplates.contains(tmpl.id) {
            guard let loc = local[tmpl.id] else {
                if !dryRun { try await target.save(recurringTemplate: tmpl) }
                added += 1
                continue
            }
            let isNewer = isRemoteNewer(
                remoteUpdated: tmpl.updatedAt, remoteCreated: tmpl.createdAt,
                localUpdated: loc.updatedAt, localCreated: loc.createdAt
            )
            guard loc != tmpl, isNewer else { continue }
            if !dryRun { try await target.save(recurringTemplate: tmpl) }
            updated += 1
        }
        return (added, updated)
    }

    static func mergeTransactions(
        source: LedgerStore,
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> Int {
        let localTxs = try await target.transactions(TransactionQuery())
        let remoteTxs = try await source.transactions(TransactionQuery())
        let localContentHashes = Set(localTxs.map(\.contentHash))
        var added = 0

        for tx in remoteTxs {
            guard !context.combinedTxIDs.contains(tx.id) else { continue }
            guard !context.combinedTxHashes.contains(tx.contentHash) else { continue }
            guard !localContentHashes.contains(tx.contentHash) else { continue }

            if !dryRun {
                _ = try await target.insert(transaction: tx)
            }
            added += 1
        }
        return added
    }

    static func mergeTombstones(
        target: LedgerStore,
        context: SyncTombstoneContext,
        dryRun: Bool
    ) async throws -> Int {
        let localKeys = Set(context.localTombstones.map { "\($0.entityType):\($0.entityID)" })
        var added = 0
        for tomb in context.remoteTombstones {
            let key = "\(tomb.entityType):\(tomb.entityID)"
            guard !localKeys.contains(key) else { continue }
            if !dryRun {
                try await target.recordTombstone(
                    entityType: tomb.entityType,
                    entityID: tomb.entityID,
                    deletedAt: tomb.deletedAt
                )
            }
            added += 1
        }
        return added
    }

    /// 원격 엔티티가 로컬 엔티티보다 최신인지 판별한다.
    static func isRemoteNewer(
        remoteUpdated: Date?,
        remoteCreated: Date,
        localUpdated: Date?,
        localCreated: Date
    ) -> Bool {
        let remoteTime = remoteUpdated ?? remoteCreated
        let localTime = localUpdated ?? localCreated
        return remoteTime >= localTime
    }
}
