import MoneyLedgerModels

extension BusinessCloudClient {
    // MARK: - Accounts

    public func listAccounts(includeArchived: Bool = false) async throws -> [MoneyAccount] {
        try await listSimple(.accounts, includeArchived: includeArchived, as: MoneyAccount.self)
    }

    public func upsertAccount(_ account: MoneyAccount) async throws -> MoneyAccount {
        try await upsertSimple(account, entity: .accounts)
    }

    public func deleteAccount(_ id: String) async throws -> BusinessCloudDeleteResult {
        try await deleteSimple(.accounts, id: id)
    }

    // MARK: - Cards

    public func listCards(includeArchived: Bool = false) async throws -> [MoneyCard] {
        try await listSimple(.cards, includeArchived: includeArchived, as: MoneyCard.self)
    }

    public func upsertCard(_ card: MoneyCard) async throws -> MoneyCard {
        try await upsertSimple(card, entity: .cards)
    }

    public func deleteCard(_ id: String) async throws -> BusinessCloudDeleteResult {
        try await deleteSimple(.cards, id: id)
    }

    // MARK: - Subscriptions

    public func listSubscriptions(includeArchived: Bool = false) async throws -> [MoneySubscription] {
        try await listSimple(.subscriptions, includeArchived: includeArchived, as: MoneySubscription.self)
    }

    public func upsertSubscription(_ subscription: MoneySubscription) async throws -> MoneySubscription {
        try await upsertSimple(subscription, entity: .subscriptions)
    }

    public func deleteSubscription(_ id: String) async throws -> BusinessCloudDeleteResult {
        try await deleteSimple(.subscriptions, id: id)
    }

    // MARK: - Businesses

    public func listBusinesses(includeArchived: Bool = false) async throws -> [BusinessProfile] {
        try await listSimple(.businesses, includeArchived: includeArchived, as: BusinessProfile.self)
    }

    public func upsertBusiness(_ business: BusinessProfile) async throws -> BusinessProfile {
        try await upsertSimple(business, entity: .businesses)
    }

    public func deleteBusiness(_ id: String) async throws -> BusinessCloudDeleteResult {
        try await deleteSimple(.businesses, id: id)
    }

    // MARK: - Import Batches

    public func listImportBatches() async throws -> [ImportBatch] {
        try await listSimple(.importBatches, includeArchived: false, as: ImportBatch.self)
    }

    public func upsertImportBatch(_ batch: ImportBatch) async throws -> ImportBatch {
        try await upsertSimple(batch, entity: .importBatches)
    }

    public func deleteImportBatch(_ id: String) async throws -> BusinessCloudDeleteResult {
        try await deleteSimple(.importBatches, id: id)
    }

    // MARK: - Attachments

    public func listAttachments() async throws -> [AttachmentRecord] {
        try await listSimple(.attachments, includeArchived: false, as: AttachmentRecord.self)
    }

    public func upsertAttachment(_ attachment: AttachmentRecord) async throws -> AttachmentRecord {
        try await upsertSimple(attachment, entity: .attachments)
    }

    public func deleteAttachment(_ id: String) async throws -> BusinessCloudDeleteResult {
        try await deleteSimple(.attachments, id: id)
    }
}
