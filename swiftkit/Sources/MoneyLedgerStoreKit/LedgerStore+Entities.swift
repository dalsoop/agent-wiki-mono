import Foundation
import MoneyLedgerModels
import SQLite3

extension LedgerStore {
    // MARK: - 계좌

    public func save(account: MoneyAccount) throws {
        let payload = try encode(account)
        try executeMutation("""
            INSERT INTO accounts(id, name, bank, last4, currency, archived, payload)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name=excluded.name, bank=excluded.bank, last4=excluded.last4,
              currency=excluded.currency, archived=excluded.archived, payload=excluded.payload
            """) { statement in
            bind(account.id, at: 1, to: statement)
            bind(account.name, at: 2, to: statement)
            bind(account.bank, at: 3, to: statement)
            bind(account.last4, at: 4, to: statement)
            bind(account.currency, at: 5, to: statement)
            sqlite3_bind_int(statement, 6, account.archived ? 1 : 0)
            bind(payload, at: 7, to: statement)
        }
        try removeTombstone(entityType: "account", entityID: account.id)
    }

    public func accounts(includeArchived: Bool = false) throws -> [MoneyAccount] {
        try listPayloads(
            MoneyAccount.self,
            sql: includeArchived
                ? "SELECT payload FROM accounts ORDER BY name, id"
                : "SELECT payload FROM accounts WHERE archived = 0 ORDER BY name, id"
        )
    }

    public func account(idPrefix: String) throws -> MoneyAccount {
        try requireOne(MoneyAccount.self, table: "accounts", idPrefix: idPrefix)
    }

    /// id 접두사 또는 이름(대소문자 무시 정확 일치)으로 찾는다 — CLI 인자 편의.
    public func resolveAccount(_ ref: String) throws -> MoneyAccount {
        if let byID = try optionalOne(MoneyAccount.self, table: "accounts", idPrefix: ref) { return byID }
        let named = try accounts(includeArchived: true)
            .filter { $0.name.caseInsensitiveCompare(ref) == .orderedSame }
        if named.count > 1 { throw LedgerStoreError.ambiguousID(ref) }
        guard let match = named.first else { throw LedgerStoreError.notFound(ref) }
        return match
    }

    public func deleteAccount(id: String) throws {
        let count = try transactionCount(instrumentColumn: "account_id", id: id)
        guard count == 0 else { throw LedgerStoreError.referencedByTransactions(id: id, count: count) }
        try executeMutation("DELETE FROM accounts WHERE id = ?") { bind(id, at: 1, to: $0) }
        try recordTombstone(entityType: "account", entityID: id)
    }

    // MARK: - 카드

    public func save(card: MoneyCard) throws {
        let payload = try encode(card)
        try executeMutation("""
            INSERT INTO cards(id, name, issuer, last4, linked_account_id, archived, payload)
            VALUES(?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name=excluded.name, issuer=excluded.issuer, last4=excluded.last4,
              linked_account_id=excluded.linked_account_id, archived=excluded.archived,
              payload=excluded.payload
            """) { statement in
            bind(card.id, at: 1, to: statement)
            bind(card.name, at: 2, to: statement)
            bind(card.issuer, at: 3, to: statement)
            bind(card.last4, at: 4, to: statement)
            bindOptional(card.linkedAccountID, at: 5, to: statement)
            sqlite3_bind_int(statement, 6, card.archived ? 1 : 0)
            bind(payload, at: 7, to: statement)
        }
        try removeTombstone(entityType: "card", entityID: card.id)
    }

    public func cards(includeArchived: Bool = false) throws -> [MoneyCard] {
        try listPayloads(
            MoneyCard.self,
            sql: includeArchived
                ? "SELECT payload FROM cards ORDER BY name, id"
                : "SELECT payload FROM cards WHERE archived = 0 ORDER BY name, id"
        )
    }

    public func card(idPrefix: String) throws -> MoneyCard {
        try requireOne(MoneyCard.self, table: "cards", idPrefix: idPrefix)
    }

    public func resolveCard(_ ref: String) throws -> MoneyCard {
        if let byID = try optionalOne(MoneyCard.self, table: "cards", idPrefix: ref) { return byID }
        let named = try cards(includeArchived: true)
            .filter { $0.name.caseInsensitiveCompare(ref) == .orderedSame }
        if named.count > 1 { throw LedgerStoreError.ambiguousID(ref) }
        guard let match = named.first else { throw LedgerStoreError.notFound(ref) }
        return match
    }

    public func deleteCard(id: String) throws {
        let count = try transactionCount(instrumentColumn: "card_id", id: id)
        guard count == 0 else { throw LedgerStoreError.referencedByTransactions(id: id, count: count) }
        try executeMutation("DELETE FROM cards WHERE id = ?") { bind(id, at: 1, to: $0) }
        try recordTombstone(entityType: "card", entityID: id)
    }

    // MARK: - 구독

    public func save(subscription: MoneySubscription) throws {
        let payload = try encode(subscription)
        try executeMutation("""
            INSERT INTO subscriptions(id, name, amount_minor, currency, period, status, next_billing_at, archived, payload)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name=excluded.name, amount_minor=excluded.amount_minor, currency=excluded.currency,
              period=excluded.period, status=excluded.status, next_billing_at=excluded.next_billing_at,
              archived=excluded.archived, payload=excluded.payload
            """) { statement in
            bind(subscription.id, at: 1, to: statement)
            bind(subscription.name, at: 2, to: statement)
            sqlite3_bind_int64(statement, 3, subscription.amountMinor)
            bind(subscription.currency, at: 4, to: statement)
            bind(subscription.period.rawValue, at: 5, to: statement)
            bind(subscription.status.rawValue, at: 6, to: statement)
            bindOptional(subscription.nextBillingDate, at: 7, to: statement)
            sqlite3_bind_int(statement, 8, subscription.archived ? 1 : 0)
            bind(payload, at: 9, to: statement)
        }
        try removeTombstone(entityType: "subscription", entityID: subscription.id)
    }

    private func subscriptionWhereClause(status: SubscriptionStatus?, includeArchived: Bool) -> String {
        var clauses: [String] = []
        if !includeArchived { clauses.append("archived = 0") }
        if status != nil { clauses.append("status = ?") }
        return clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
    }

    public func subscriptions(
        status: SubscriptionStatus? = nil,
        includeArchived: Bool = false
    ) throws -> [MoneySubscription] {
        let whereSQL = subscriptionWhereClause(status: status, includeArchived: includeArchived)
        let statement = try prepare("SELECT payload FROM subscriptions\(whereSQL) ORDER BY name, id")
        defer { sqlite3_finalize(statement) }
        if let status { bind(status.rawValue, at: 1, to: statement) }
        return try collect(MoneySubscription.self, statement: statement)
    }

    public func subscription(idPrefix: String) throws -> MoneySubscription {
        try requireOne(MoneySubscription.self, table: "subscriptions", idPrefix: idPrefix)
    }

    public func resolveSubscription(_ ref: String) throws -> MoneySubscription {
        if let byID = try optionalOne(MoneySubscription.self, table: "subscriptions", idPrefix: ref) {
            return byID
        }
        let named = try subscriptions(includeArchived: true)
            .filter { $0.name.caseInsensitiveCompare(ref) == .orderedSame }
        if named.count > 1 { throw LedgerStoreError.ambiguousID(ref) }
        guard let match = named.first else { throw LedgerStoreError.notFound(ref) }
        return match
    }

    public func deleteSubscription(id: String) throws {
        try executeMutation("DELETE FROM subscriptions WHERE id = ?") { bind(id, at: 1, to: $0) }
        try recordTombstone(entityType: "subscription", entityID: id)
    }

    // MARK: - 사업자

    public func save(business: BusinessProfile) throws {
        let payload = try encode(business)
        try executeMutation("""
            INSERT INTO businesses(id, name, registration_number, archived, payload)
            VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name=excluded.name, registration_number=excluded.registration_number,
              archived=excluded.archived, payload=excluded.payload
            """) { statement in
            bind(business.id, at: 1, to: statement)
            bind(business.name, at: 2, to: statement)
            bind(business.registrationNumber, at: 3, to: statement)
            sqlite3_bind_int(statement, 4, business.archived ? 1 : 0)
            bind(payload, at: 5, to: statement)
        }
        try removeTombstone(entityType: "business", entityID: business.id)
    }

    public func businesses(includeArchived: Bool = false) throws -> [BusinessProfile] {
        try listPayloads(
            BusinessProfile.self,
            sql: includeArchived
                ? "SELECT payload FROM businesses ORDER BY name, id"
                : "SELECT payload FROM businesses WHERE archived = 0 ORDER BY name, id"
        )
    }

    public func business(idPrefix: String) throws -> BusinessProfile {
        try requireOne(BusinessProfile.self, table: "businesses", idPrefix: idPrefix)
    }

    public func resolveBusiness(_ ref: String) throws -> BusinessProfile {
        if let byID = try optionalOne(BusinessProfile.self, table: "businesses", idPrefix: ref) {
            return byID
        }
        let named = try businesses(includeArchived: true)
            .filter { $0.name.caseInsensitiveCompare(ref) == .orderedSame }
        if named.count > 1 { throw LedgerStoreError.ambiguousID(ref) }
        guard let match = named.first else { throw LedgerStoreError.notFound(ref) }
        return match
    }

    /// 사업자 삭제 — 첨부 메타 행도 함께 지우고, 파일 삭제용으로 지운 메타를 돌려준다.
    public func deleteBusiness(id: String) throws -> [AttachmentRecord] {
        try inTransaction {
            let removed = try attachments(ownerKind: .business, ownerID: id)
            try executeMutation("DELETE FROM attachments WHERE owner_kind = ? AND owner_id = ?") {
                bind(AttachmentRecord.OwnerKind.business.rawValue, at: 1, to: $0)
                bind(id, at: 2, to: $0)
            }
            try executeMutation("DELETE FROM businesses WHERE id = ?") { bind(id, at: 1, to: $0) }
            try recordTombstone(entityType: "business", entityID: id)
            return removed
        }
    }

    // MARK: - 첨부(이미지 등)

    public func insert(attachment: AttachmentRecord) throws {
        let payload = try encode(attachment)
        try executeMutation("""
            INSERT INTO attachments(id, owner_kind, owner_id, file_name, original_name, payload)
            VALUES(?, ?, ?, ?, ?, ?)
            """) { statement in
            bind(attachment.id, at: 1, to: statement)
            bind(attachment.ownerKind.rawValue, at: 2, to: statement)
            bind(attachment.ownerID, at: 3, to: statement)
            bind(attachment.fileName, at: 4, to: statement)
            bind(attachment.originalName, at: 5, to: statement)
            bind(payload, at: 6, to: statement)
        }
    }

    public func attachments(
        ownerKind: AttachmentRecord.OwnerKind,
        ownerID: String
    ) throws -> [AttachmentRecord] {
        let statement = try prepare(
            "SELECT payload FROM attachments WHERE owner_kind = ? AND owner_id = ? ORDER BY id"
        )
        defer { sqlite3_finalize(statement) }
        bind(ownerKind.rawValue, at: 1, to: statement)
        bind(ownerID, at: 2, to: statement)
        return try collect(AttachmentRecord.self, statement: statement)
    }

    public func attachment(idPrefix: String) throws -> AttachmentRecord {
        try requireOne(AttachmentRecord.self, table: "attachments", idPrefix: idPrefix)
    }

    public func deleteAttachment(id: String) throws {
        try executeMutation("DELETE FROM attachments WHERE id = ?") { bind(id, at: 1, to: $0) }
    }
}
