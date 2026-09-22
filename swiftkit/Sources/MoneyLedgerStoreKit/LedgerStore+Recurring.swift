import Foundation
import MoneyLedgerModels
import SQLite3

extension LedgerStore {
    // MARK: - 반복 고정비 템플릿 (Recurring Templates)

    public func save(recurringTemplate template: RecurringTemplate) throws {
        var templateToSave = template
        templateToSave.updatedAt = .now
        let payload = try encode(templateToSave)
        try executeMutation("""
            INSERT INTO recurring_templates(
              id, name, day_of_month, amount_minor, currency, kind, category,
              account_id, transfer_target_account_id, memo, is_active, created_at, updated_at, payload
            )
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              name=excluded.name, day_of_month=excluded.day_of_month, amount_minor=excluded.amount_minor,
              currency=excluded.currency, kind=excluded.kind, category=excluded.category,
              account_id=excluded.account_id, transfer_target_account_id=excluded.transfer_target_account_id,
              memo=excluded.memo, is_active=excluded.is_active, created_at=excluded.created_at,
              updated_at=excluded.updated_at, payload=excluded.payload
            """) { statement in
            bind(templateToSave.id, at: 1, to: statement)
            bind(templateToSave.name, at: 2, to: statement)
            sqlite3_bind_int(statement, 3, Int32(templateToSave.dayOfMonth))
            sqlite3_bind_int64(statement, 4, templateToSave.amountMinor)
            bind(templateToSave.currency, at: 5, to: statement)
            bind(templateToSave.kind.rawValue, at: 6, to: statement)
            bindOptional(templateToSave.category, at: 7, to: statement)
            bindOptional(templateToSave.accountID, at: 8, to: statement)
            bindOptional(templateToSave.transferTargetAccountID, at: 9, to: statement)
            bindOptional(templateToSave.memo, at: 10, to: statement)
            sqlite3_bind_int(statement, 11, templateToSave.isActive ? 1 : 0)
            sqlite3_bind_double(statement, 12, templateToSave.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 13, templateToSave.updatedAt.timeIntervalSince1970)
            bind(payload, at: 14, to: statement)
        }
        try removeTombstone(entityType: "recurring_template", entityID: templateToSave.id)
    }

    public func recurringTemplates(activeOnly: Bool = false) throws -> [RecurringTemplate] {
        let sql = activeOnly
            ? "SELECT payload FROM recurring_templates WHERE is_active = 1 ORDER BY day_of_month, name, id"
            : "SELECT payload FROM recurring_templates ORDER BY day_of_month, name, id"
        return try listPayloads(RecurringTemplate.self, sql: sql)
    }

    public func recurringTemplate(idPrefix: String) throws -> RecurringTemplate {
        try requireOne(RecurringTemplate.self, table: "recurring_templates", idPrefix: idPrefix)
    }

    public func deleteRecurringTemplate(id: String) throws {
        try executeMutation("DELETE FROM recurring_templates WHERE id = ?") { bind(id, at: 1, to: $0) }
        try recordTombstone(entityType: "recurring_template", entityID: id)
    }

    // MARK: - 고정비 일괄 적용 엔진

    @discardableResult
    public func applyRecurringTemplates(
        month: String,
        from accountID: String? = nil
    ) throws -> [MoneyTransaction] {
        let (year, m) = try parseYearMonth(month)
        let maxDays = calculateMaxDays(year: year, month: m)
        let activeTemplates = try recurringTemplates(activeOnly: true)
        guard !activeTemplates.isEmpty else { return [] }

        let monthStart = String(format: "%04d-%02d-01", year, m)
        let monthEnd = String(format: "%04d-%02d-%02d", year, m, maxDays)
        let existingTxs = try transactions(TransactionQuery(fromDate: monthStart, toDate: monthEnd))

        return try inTransaction {
            try executeTemplateGeneration(
                templates: activeTemplates,
                existingTxs: existingTxs,
                accountFilter: accountID,
                year: year,
                monthNum: m,
                monthStr: month,
                maxDays: maxDays
            )
        }
    }

    private func parseYearMonth(_ month: String) throws -> (Int, Int) {
        let parts = month.components(separatedBy: "-")
        guard parts.count == 2, let year = Int(parts[0]), let m = Int(parts[1]), (1...12).contains(m) else {
            throw LedgerDateError.unparsable(month)
        }
        return (year, m)
    }

    private func calculateMaxDays(year: Int, month: Int) -> Int {
        let calendar = Calendar.current
        var comp = DateComponents()
        comp.year = year
        comp.month = month
        guard let monthDate = calendar.date(from: comp),
              let dayRange = calendar.range(of: .day, in: .month, for: monthDate) else {
            return 31
        }
        return dayRange.count
    }

    private func executeTemplateGeneration(
        templates: [RecurringTemplate],
        existingTxs: [MoneyTransaction],
        accountFilter: String?,
        year: Int,
        monthNum: Int,
        monthStr: String,
        maxDays: Int
    ) throws -> [MoneyTransaction] {
        var createdTxs: [MoneyTransaction] = []
        for template in templates {
            guard !isAccountFiltered(template: template, filter: accountFilter) else { continue }
            let recurringTag = "[recurring:\(template.id):\(monthStr)]"
            guard !isAlreadyApplied(tag: recurringTag, in: existingTxs) else { continue }

            let actualDay = min(template.dayOfMonth, maxDays)
            let txDate = String(format: "%04d-%02d-%02d", year, monthNum, actualDay)
            let memoPrefix = template.memo.map { $0.isEmpty ? "" : "\($0) " } ?? ""
            let txMemo = memoPrefix + recurringTag
            let effectiveAccountID = template.accountID ?? accountFilter

            let txs = try processTemplate(
                template: template,
                txDate: txDate,
                txMemo: txMemo,
                effectiveAccountID: effectiveAccountID
            )
            createdTxs.append(contentsOf: txs)
        }
        return createdTxs
    }

    private func isAccountFiltered(template: RecurringTemplate, filter: String?) -> Bool {
        guard let filter else { return false }
        guard let tplAccount = template.accountID else { return false }
        return tplAccount != filter
    }

    private func isAlreadyApplied(tag: String, in existingTxs: [MoneyTransaction]) -> Bool {
        existingTxs.contains { tx in tx.memo?.contains(tag) == true }
    }

    private func processTemplate(
        template: RecurringTemplate,
        txDate: String,
        txMemo: String,
        effectiveAccountID: String?
    ) throws -> [MoneyTransaction] {
        let absAmount = abs(template.amountMinor)
        switch template.kind {
        case .expense:
            guard let tx = try createExpenseTransaction(
                template: template,
                txDate: txDate,
                txMemo: txMemo,
                absAmount: absAmount,
                effectiveAccountID: effectiveAccountID
            ) else { return [] }
            return [tx]
        case .transfer:
            return try createTransferTransactions(
                template: template,
                txDate: txDate,
                txMemo: txMemo,
                absAmount: absAmount,
                effectiveAccountID: effectiveAccountID
            )
        default:
            return []
        }
    }

    private func createExpenseTransaction(
        template: RecurringTemplate,
        txDate: String,
        txMemo: String,
        absAmount: Int64,
        effectiveAccountID: String?
    ) throws -> MoneyTransaction? {
        let amountMinor = -absAmount
        let occurrence = try nextOccurrence(
            date: txDate,
            amountMinor: amountMinor,
            currency: template.currency,
            instrumentID: effectiveAccountID ?? "",
            description: template.name
        )
        let hash = ContentHash.transactionHash(
            date: txDate,
            time: nil,
            amountMinor: amountMinor,
            currency: template.currency,
            instrumentID: effectiveAccountID ?? "",
            description: template.name,
            balanceAfterMinor: nil,
            occurrence: occurrence
        )
        let tx = MoneyTransaction(
            id: UUID().uuidString.lowercased(),
            stamp: .init(date: txDate),
            amount: .init(amountMinor: amountMinor, currency: template.currency),
            parties: .init(accountID: effectiveAccountID),
            narrative: .init(description: template.name, category: template.category, memo: txMemo),
            kind: .expense,
            contentHash: hash
        )
        let outcome = try insert(transaction: tx)
        guard !outcome.duplicate else { return nil }
        return outcome.transaction
    }

    private func createTransferTransactions(
        template: RecurringTemplate,
        txDate: String,
        txMemo: String,
        absAmount: Int64,
        effectiveAccountID: String?
    ) throws -> [MoneyTransaction] {
        guard let fromAcc = effectiveAccountID,
              let toAcc = template.transferTargetAccountID,
              fromAcc != toAcc else {
            return []
        }
        let wDesc = "\(template.name) (출금)"
        let dDesc = "\(template.name) (입금)"
        let wID = UUID().uuidString.lowercased()
        let dID = UUID().uuidString.lowercased()

        let wHash = ContentHash.transactionHash(
            date: txDate,
            time: nil,
            amountMinor: -absAmount,
            currency: template.currency,
            instrumentID: fromAcc,
            description: "\(wDesc)|pair:\(wID)",
            balanceAfterMinor: nil
        )
        let withdrawal = MoneyTransaction(
            id: wID,
            stamp: .init(date: txDate),
            amount: .init(amountMinor: -absAmount, currency: template.currency),
            parties: .init(accountID: fromAcc),
            narrative: .init(description: wDesc, category: template.category ?? "이체", memo: txMemo),
            kind: .transfer,
            contentHash: wHash
        )

        let dHash = ContentHash.transactionHash(
            date: txDate,
            time: nil,
            amountMinor: absAmount,
            currency: template.currency,
            instrumentID: toAcc,
            description: "\(dDesc)|pair:\(dID)",
            balanceAfterMinor: nil
        )
        let deposit = MoneyTransaction(
            id: dID,
            stamp: .init(date: txDate),
            amount: .init(amountMinor: absAmount, currency: template.currency),
            parties: .init(accountID: toAcc),
            narrative: .init(description: dDesc, category: template.category ?? "이체", memo: txMemo),
            kind: .transfer,
            contentHash: dHash
        )

        var result: [MoneyTransaction] = []
        let wOutcome = try insert(transaction: withdrawal)
        let dOutcome = try insert(transaction: deposit)
        if !wOutcome.duplicate { result.append(wOutcome.transaction) }
        if !dOutcome.duplicate { result.append(dOutcome.transaction) }
        return result
    }
}
