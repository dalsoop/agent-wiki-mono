import Foundation
import MoneyLedgerModels

public struct SyncEntityCounts: Sendable, Equatable, Codable {
    public var accounts: Int = 0
    public var cards: Int = 0
    public var subscriptions: Int = 0
    public var budgets: Int = 0
    public var recurringTemplates: Int = 0
    public var businesses: Int = 0
    public var transactions: Int = 0

    public init(
        accounts: Int = 0,
        cards: Int = 0,
        subscriptions: Int = 0,
        budgets: Int = 0,
        recurringTemplates: Int = 0,
        businesses: Int = 0,
        transactions: Int = 0
    ) {
        self.accounts = accounts
        self.cards = cards
        self.subscriptions = subscriptions
        self.budgets = budgets
        self.recurringTemplates = recurringTemplates
        self.businesses = businesses
        self.transactions = transactions
    }
}

public struct SyncSnapshotCounts: Sendable, Equatable, Codable {
    public var accounts: Int = 0
    public var cards: Int = 0
    public var subscriptions: Int = 0
    public var budgets: Int = 0
    public var transactions: Int = 0

    public init(
        accounts: Int = 0,
        cards: Int = 0,
        subscriptions: Int = 0,
        budgets: Int = 0,
        transactions: Int = 0
    ) {
        self.accounts = accounts
        self.cards = cards
        self.subscriptions = subscriptions
        self.budgets = budgets
        self.transactions = transactions
    }
}

/// 동기화 병합 결과 리포트
public struct SyncMergeReport: Sendable, Equatable, Codable {
    public var added: SyncEntityCounts
    public var updated: SyncEntityCounts
    public var deleted: SyncEntityCounts
    public var tombstonesAdded: Int
    public var localCounts: SyncSnapshotCounts
    public var remoteCounts: SyncSnapshotCounts

    public var accountsAdded: Int { get { added.accounts } set { added.accounts = newValue } }
    public var cardsAdded: Int { get { added.cards } set { added.cards = newValue } }
    public var subscriptionsAdded: Int { get { added.subscriptions } set { added.subscriptions = newValue } }
    public var budgetsAdded: Int { get { added.budgets } set { added.budgets = newValue } }
    public var recurringTemplatesAdded: Int { get { added.recurringTemplates } set { added.recurringTemplates = newValue } }
    public var businessesAdded: Int { get { added.businesses } set { added.businesses = newValue } }
    public var transactionsAdded: Int { get { added.transactions } set { added.transactions = newValue } }

    public var accountsUpdated: Int { get { updated.accounts } set { updated.accounts = newValue } }
    public var cardsUpdated: Int { get { updated.cards } set { updated.cards = newValue } }
    public var subscriptionsUpdated: Int { get { updated.subscriptions } set { updated.subscriptions = newValue } }
    public var budgetsUpdated: Int { get { updated.budgets } set { updated.budgets = newValue } }
    public var recurringTemplatesUpdated: Int { get { updated.recurringTemplates } set { updated.recurringTemplates = newValue } }
    public var businessesUpdated: Int { get { updated.businesses } set { updated.businesses = newValue } }

    public var accountsDeleted: Int { get { deleted.accounts } set { deleted.accounts = newValue } }
    public var cardsDeleted: Int { get { deleted.cards } set { deleted.cards = newValue } }
    public var subscriptionsDeleted: Int { get { deleted.subscriptions } set { deleted.subscriptions = newValue } }
    public var budgetsDeleted: Int { get { deleted.budgets } set { deleted.budgets = newValue } }
    public var recurringTemplatesDeleted: Int { get { deleted.recurringTemplates } set { deleted.recurringTemplates = newValue } }
    public var businessesDeleted: Int { get { deleted.businesses } set { deleted.businesses = newValue } }
    public var transactionsDeleted: Int { get { deleted.transactions } set { deleted.transactions = newValue } }

    public var localAccountsCount: Int { get { localCounts.accounts } set { localCounts.accounts = newValue } }
    public var localCardsCount: Int { get { localCounts.cards } set { localCounts.cards = newValue } }
    public var localSubscriptionsCount: Int { get { localCounts.subscriptions } set { localCounts.subscriptions = newValue } }
    public var localBudgetsCount: Int { get { localCounts.budgets } set { localCounts.budgets = newValue } }
    public var localTransactionsCount: Int { get { localCounts.transactions } set { localCounts.transactions = newValue } }

    public var remoteAccountsCount: Int { get { remoteCounts.accounts } set { remoteCounts.accounts = newValue } }
    public var remoteCardsCount: Int { get { remoteCounts.cards } set { remoteCounts.cards = newValue } }
    public var remoteSubscriptionsCount: Int { get { remoteCounts.subscriptions } set { remoteCounts.subscriptions = newValue } }
    public var remoteBudgetsCount: Int { get { remoteCounts.budgets } set { remoteCounts.budgets = newValue } }
    public var remoteTransactionsCount: Int { get { remoteCounts.transactions } set { remoteCounts.transactions = newValue } }

    public var totalEntitiesAdded: Int {
        added.accounts + added.cards + added.subscriptions + added.budgets
            + added.recurringTemplates + added.businesses + added.transactions
    }

    public var totalEntitiesUpdated: Int {
        updated.accounts + updated.cards + updated.subscriptions + updated.budgets
            + updated.recurringTemplates + updated.businesses
    }

    public var totalEntitiesDeleted: Int {
        deleted.accounts + deleted.cards + deleted.subscriptions + deleted.budgets
            + deleted.recurringTemplates + deleted.businesses + deleted.transactions
    }

    public init(
        added: SyncEntityCounts = SyncEntityCounts(),
        updated: SyncEntityCounts = SyncEntityCounts(),
        deleted: SyncEntityCounts = SyncEntityCounts(),
        tombstonesAdded: Int = 0,
        localCounts: SyncSnapshotCounts = SyncSnapshotCounts(),
        remoteCounts: SyncSnapshotCounts = SyncSnapshotCounts()
    ) {
        self.added = added
        self.updated = updated
        self.deleted = deleted
        self.tombstonesAdded = tombstonesAdded
        self.localCounts = localCounts
        self.remoteCounts = remoteCounts
    }

    enum CodingKeys: String, CodingKey {
        case accountsAdded, cardsAdded, subscriptionsAdded, budgetsAdded, recurringTemplatesAdded, businessesAdded, transactionsAdded
        case accountsUpdated, cardsUpdated, subscriptionsUpdated, budgetsUpdated, recurringTemplatesUpdated, businessesUpdated
        case accountsDeleted, cardsDeleted, subscriptionsDeleted, budgetsDeleted, recurringTemplatesDeleted, businessesDeleted, transactionsDeleted
        case tombstonesAdded
        case localAccountsCount, localCardsCount, localSubscriptionsCount, localBudgetsCount, localTransactionsCount
        case remoteAccountsCount, remoteCardsCount, remoteSubscriptionsCount, remoteBudgetsCount, remoteTransactionsCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let accAdd = try container.decodeIfPresent(Int.self, forKey: .accountsAdded) ?? 0
        let cardAdd = try container.decodeIfPresent(Int.self, forKey: .cardsAdded) ?? 0
        let subAdd = try container.decodeIfPresent(Int.self, forKey: .subscriptionsAdded) ?? 0
        let budAdd = try container.decodeIfPresent(Int.self, forKey: .budgetsAdded) ?? 0
        let tmplAdd = try container.decodeIfPresent(Int.self, forKey: .recurringTemplatesAdded) ?? 0
        let bizAdd = try container.decodeIfPresent(Int.self, forKey: .businessesAdded) ?? 0
        let txAdd = try container.decodeIfPresent(Int.self, forKey: .transactionsAdded) ?? 0

        let accUp = try container.decodeIfPresent(Int.self, forKey: .accountsUpdated) ?? 0
        let cardUp = try container.decodeIfPresent(Int.self, forKey: .cardsUpdated) ?? 0
        let subUp = try container.decodeIfPresent(Int.self, forKey: .subscriptionsUpdated) ?? 0
        let budUp = try container.decodeIfPresent(Int.self, forKey: .budgetsUpdated) ?? 0
        let tmplUp = try container.decodeIfPresent(Int.self, forKey: .recurringTemplatesUpdated) ?? 0
        let bizUp = try container.decodeIfPresent(Int.self, forKey: .businessesUpdated) ?? 0

        let accDel = try container.decodeIfPresent(Int.self, forKey: .accountsDeleted) ?? 0
        let cardDel = try container.decodeIfPresent(Int.self, forKey: .cardsDeleted) ?? 0
        let subDel = try container.decodeIfPresent(Int.self, forKey: .subscriptionsDeleted) ?? 0
        let budDel = try container.decodeIfPresent(Int.self, forKey: .budgetsDeleted) ?? 0
        let tmplDel = try container.decodeIfPresent(Int.self, forKey: .recurringTemplatesDeleted) ?? 0
        let bizDel = try container.decodeIfPresent(Int.self, forKey: .businessesDeleted) ?? 0
        let txDel = try container.decodeIfPresent(Int.self, forKey: .transactionsDeleted) ?? 0

        let tombAdd = try container.decodeIfPresent(Int.self, forKey: .tombstonesAdded) ?? 0

        let locAcc = try container.decodeIfPresent(Int.self, forKey: .localAccountsCount) ?? 0
        let locCard = try container.decodeIfPresent(Int.self, forKey: .localCardsCount) ?? 0
        let locSub = try container.decodeIfPresent(Int.self, forKey: .localSubscriptionsCount) ?? 0
        let locBud = try container.decodeIfPresent(Int.self, forKey: .localBudgetsCount) ?? 0
        let locTx = try container.decodeIfPresent(Int.self, forKey: .localTransactionsCount) ?? 0

        let remAcc = try container.decodeIfPresent(Int.self, forKey: .remoteAccountsCount) ?? 0
        let remCard = try container.decodeIfPresent(Int.self, forKey: .remoteCardsCount) ?? 0
        let remSub = try container.decodeIfPresent(Int.self, forKey: .remoteSubscriptionsCount) ?? 0
        let remBud = try container.decodeIfPresent(Int.self, forKey: .remoteBudgetsCount) ?? 0
        let remTx = try container.decodeIfPresent(Int.self, forKey: .remoteTransactionsCount) ?? 0

        let added = SyncEntityCounts(
            accounts: accAdd, cards: cardAdd, subscriptions: subAdd, budgets: budAdd,
            recurringTemplates: tmplAdd, businesses: bizAdd, transactions: txAdd
        )
        let updated = SyncEntityCounts(
            accounts: accUp, cards: cardUp, subscriptions: subUp, budgets: budUp,
            recurringTemplates: tmplUp, businesses: bizUp
        )
        let deleted = SyncEntityCounts(
            accounts: accDel, cards: cardDel, subscriptions: subDel, budgets: budDel,
            recurringTemplates: tmplDel, businesses: bizDel, transactions: txDel
        )
        let localCounts = SyncSnapshotCounts(
            accounts: locAcc, cards: locCard, subscriptions: locSub, budgets: locBud, transactions: locTx
        )
        let remoteCounts = SyncSnapshotCounts(
            accounts: remAcc, cards: remCard, subscriptions: remSub, budgets: remBud, transactions: remTx
        )

        self.init(
            added: added, updated: updated, deleted: deleted,
            tombstonesAdded: tombAdd, localCounts: localCounts, remoteCounts: remoteCounts
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(accountsAdded, forKey: .accountsAdded)
        try container.encode(cardsAdded, forKey: .cardsAdded)
        try container.encode(subscriptionsAdded, forKey: .subscriptionsAdded)
        try container.encode(budgetsAdded, forKey: .budgetsAdded)
        try container.encode(recurringTemplatesAdded, forKey: .recurringTemplatesAdded)
        try container.encode(businessesAdded, forKey: .businessesAdded)
        try container.encode(transactionsAdded, forKey: .transactionsAdded)

        try container.encode(accountsUpdated, forKey: .accountsUpdated)
        try container.encode(cardsUpdated, forKey: .cardsUpdated)
        try container.encode(subscriptionsUpdated, forKey: .subscriptionsUpdated)
        try container.encode(budgetsUpdated, forKey: .budgetsUpdated)
        try container.encode(recurringTemplatesUpdated, forKey: .recurringTemplatesUpdated)
        try container.encode(businessesUpdated, forKey: .businessesUpdated)

        try container.encode(accountsDeleted, forKey: .accountsDeleted)
        try container.encode(cardsDeleted, forKey: .cardsDeleted)
        try container.encode(subscriptionsDeleted, forKey: .subscriptionsDeleted)
        try container.encode(budgetsDeleted, forKey: .budgetsDeleted)
        try container.encode(recurringTemplatesDeleted, forKey: .recurringTemplatesDeleted)
        try container.encode(businessesDeleted, forKey: .businessesDeleted)
        try container.encode(transactionsDeleted, forKey: .transactionsDeleted)

        try container.encode(tombstonesAdded, forKey: .tombstonesAdded)

        try container.encode(localAccountsCount, forKey: .localAccountsCount)
        try container.encode(localCardsCount, forKey: .localCardsCount)
        try container.encode(localSubscriptionsCount, forKey: .localSubscriptionsCount)
        try container.encode(localBudgetsCount, forKey: .localBudgetsCount)
        try container.encode(localTransactionsCount, forKey: .localTransactionsCount)

        try container.encode(remoteAccountsCount, forKey: .remoteAccountsCount)
        try container.encode(remoteCardsCount, forKey: .remoteCardsCount)
        try container.encode(remoteSubscriptionsCount, forKey: .remoteSubscriptionsCount)
        try container.encode(remoteBudgetsCount, forKey: .remoteBudgetsCount)
        try container.encode(remoteTransactionsCount, forKey: .remoteTransactionsCount)
    }
}
