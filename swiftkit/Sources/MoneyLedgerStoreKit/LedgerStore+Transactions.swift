import Foundation
import MoneyLedgerModels
import SQLite3

extension LedgerStore {
    // MARK: - 거래

    /// 중복(content_hash 충돌)이면 기존 행을 돌려주고 duplicate=true — 실패가 아니다.
    public func insert(transaction tx: MoneyTransaction) throws -> TransactionInsertOutcome {
        if let existing = try transactionByHash(tx.contentHash) {
            return TransactionInsertOutcome(transaction: existing, duplicate: true)
        }
        let payload = try encode(tx)
        try executeMutation("""
            INSERT INTO transactions(id, date, amount_minor, currency, account_id, card_id,
                                     description, category, content_hash, import_batch_id,
                                     business_id, payload)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """) { statement in
            bind(tx.id, at: 1, to: statement)
            bind(tx.date, at: 2, to: statement)
            sqlite3_bind_int64(statement, 3, tx.amountMinor)
            bind(tx.currency, at: 4, to: statement)
            bindOptional(tx.accountID, at: 5, to: statement)
            bindOptional(tx.cardID, at: 6, to: statement)
            bind(tx.description, at: 7, to: statement)
            bindOptional(tx.category, at: 8, to: statement)
            bind(tx.contentHash, at: 9, to: statement)
            bindOptional(tx.importBatchID, at: 10, to: statement)
            bindOptional(tx.businessID, at: 11, to: statement)
            bind(payload, at: 12, to: statement)
        }
        try removeTombstone(entityType: "transaction", entityID: tx.id)
        try removeTombstone(entityType: "transaction_hash", entityID: tx.contentHash)
        return TransactionInsertOutcome(transaction: tx, duplicate: false)
    }

    /// 기존 거래 갱신(카테고리·메모 등). content_hash 는 불변 계약이라 바꾸지 않는다.
    public func update(transaction tx: MoneyTransaction) throws {
        let payload = try encode(tx)
        try executeMutation("""
            UPDATE transactions SET date=?, amount_minor=?, currency=?, account_id=?, card_id=?,
                                    description=?, category=?, import_batch_id=?, business_id=?,
                                    payload=?
            WHERE id=?
            """) { statement in
            bind(tx.date, at: 1, to: statement)
            sqlite3_bind_int64(statement, 2, tx.amountMinor)
            bind(tx.currency, at: 3, to: statement)
            bindOptional(tx.accountID, at: 4, to: statement)
            bindOptional(tx.cardID, at: 5, to: statement)
            bind(tx.description, at: 6, to: statement)
            bindOptional(tx.category, at: 7, to: statement)
            bindOptional(tx.importBatchID, at: 8, to: statement)
            bindOptional(tx.businessID, at: 9, to: statement)
            bind(payload, at: 10, to: statement)
            bind(tx.id, at: 11, to: statement)
        }
    }

    public func transactions(_ query: TransactionQuery = TransactionQuery()) throws -> [MoneyTransaction] {
        let (clauses, bindings) = buildWhereClauses(query)
        let whereSQL = clauses.isEmpty ? "" : " WHERE " + clauses.joined(separator: " AND ")
        let limitSQL = query.limit.map { " LIMIT \(max(0, $0))" } ?? ""
        let statement = try prepare(
            "SELECT payload FROM transactions\(whereSQL) ORDER BY date DESC, time_sort DESC, id\(limitSQL)"
        )
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            bind(value, at: Int32(index + 1), to: statement)
        }
        return try collect(MoneyTransaction.self, statement: statement)
    }

    private func buildWhereClauses(_ query: TransactionQuery) -> ([String], [String]) {
        let filters: [(String, String?)] = [
            ("date >= ?", query.fromDate),
            ("date <= ?", query.toDate),
            ("account_id = ?", query.accountID),
            ("card_id = ?", query.cardID),
            ("category = ?", query.category),
            ("business_id = ?", query.businessID)
        ]
        var clauses: [String] = []
        var bindings: [String] = []
        for (sql, value) in filters {
            guard let value else { continue }
            clauses.append(sql)
            bindings.append(value)
        }
        return (clauses, bindings)
    }

    public func transaction(idPrefix: String) throws -> MoneyTransaction {
        try requireOne(MoneyTransaction.self, table: "transactions", idPrefix: idPrefix)
    }

    public func deleteTransaction(id: String) throws {
        let existing = try optionalOne(MoneyTransaction.self, table: "transactions", idPrefix: id)
        try executeMutation("DELETE FROM transactions WHERE id = ?") { bind(id, at: 1, to: $0) }
        try recordTombstone(entityType: "transaction", entityID: id)
        if let hash = existing?.contentHash {
            try recordTombstone(entityType: "transaction_hash", entityID: hash)
        }
    }

    public func transactionByHash(_ hash: String) throws -> MoneyTransaction? {
        let statement = try prepare("SELECT payload FROM transactions WHERE content_hash = ?")
        defer { sqlite3_finalize(statement) }
        bind(hash, at: 1, to: statement)
        return try collect(MoneyTransaction.self, statement: statement).first
    }

    public func transactionCount() throws -> Int {
        try scalarCount("SELECT COUNT(*) FROM transactions")
    }

    /// 동일 조건(날짜·시간·금액·통화·수단·적요)의 중복 충돌을 방지하는 다음 occurrence 번호.
    public func nextOccurrence(
        date: String,
        time: String? = nil,
        amountMinor: Int64,
        currency: String = "KRW",
        instrumentID: String = "",
        description: String,
        balanceAfterMinor: Int64? = nil
    ) throws -> Int {
        var occurrence = 1
        while true {
            let hash = ContentHash.transactionHash(
                date: date,
                time: time,
                amountMinor: amountMinor,
                currency: currency,
                instrumentID: instrumentID,
                description: description,
                balanceAfterMinor: balanceAfterMinor,
                occurrence: occurrence
            )
            if try transactionByHash(hash) == nil {
                return occurrence
            }
            occurrence += 1
        }
    }

    /// 계좌 잔액 계산: 기초잔액 + 거래 증감 합계.
    public func balance(forAccountID accountID: String) throws -> Int64 {
        let acct = try resolveAccount(accountID)
        let txs = try transactions(TransactionQuery(accountID: acct.id))
        let initial = acct.initialBalanceMinor ?? 0
        let normCur = MoneyAmount.normalizedCurrency(acct.currency)
        let txSum = txs
            .filter { MoneyAmount.normalizedCurrency($0.currency) == normCur }
            .map(\.amountMinor)
            .reduce(0, +)
        return initial + txSum
    }

    /// 카드 미결제 잔액(부채) 계산: 결제(음수) 및 상환/납부(양수) 합산의 미결제액.
    public func cardBalance(forCardID cardID: String, currency: String = "KRW") throws -> Int64 {
        let crd = try resolveCard(cardID)
        let txs = try transactions(TransactionQuery(cardID: crd.id))
        let normCur = MoneyAmount.normalizedCurrency(currency)
        let sum = txs
            .filter { MoneyAmount.normalizedCurrency($0.currency) == normCur }
            .map(\.amountMinor)
            .reduce(0, +)
        return sum < 0 ? abs(sum) : 0
    }

    // MARK: - 이체 및 카드 대금 결제

    /// 두 계좌 간 원자적 이체 쌍 생성.
    public func createTransfer(
        fromAccountID: String,
        toAccountID: String,
        amountMinor: Int64,
        currency: String = "KRW",
        date: String,
        description: String? = nil
    ) throws -> (withdrawal: MoneyTransaction, deposit: MoneyTransaction) {
        let fromAccount = try resolveAccount(fromAccountID)
        let toAccount = try resolveAccount(toAccountID)
        guard fromAccount.id != toAccount.id else {
            throw LedgerStoreError.sqlite("출금 계좌와 입금 계좌가 동일합니다")
        }
        let pair = buildTransferTransactions(
            fromAccount: fromAccount, toAccount: toAccount,
            amountMinor: amountMinor, currency: currency,
            date: date, description: description
        )
        return try inTransaction {
            let wOutcome = try insert(transaction: pair.withdrawal)
            let dOutcome = try insert(transaction: pair.deposit)
            return (wOutcome.transaction, dOutcome.transaction)
        }
    }

    private func buildTransferTransactions(
        fromAccount: MoneyAccount, toAccount: MoneyAccount,
        amountMinor: Int64, currency: String,
        date: String, description: String?
    ) -> (withdrawal: MoneyTransaction, deposit: MoneyTransaction) {
        let absAmount = abs(amountMinor)
        let baseDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wDesc = (baseDesc?.isEmpty == false) ? "\(baseDesc ?? "") (출금)" : "이체 -> \(toAccount.name)"
        let dDesc = (baseDesc?.isEmpty == false) ? "\(baseDesc ?? "") (입금)" : "이체 <- \(fromAccount.name)"
        let withdrawalID = UUID().uuidString.lowercased()
        let depositID = UUID().uuidString.lowercased()

        let wHash = ContentHash.transactionHash(
            date: date, time: nil, amountMinor: -absAmount, currency: currency,
            instrumentID: fromAccount.id, description: "\(wDesc)|pair:\(withdrawalID)", balanceAfterMinor: nil
        )
        let withdrawal = MoneyTransaction(
            id: withdrawalID, stamp: .init(date: date),
            amount: .init(amountMinor: -absAmount, currency: currency),
            parties: .init(accountID: fromAccount.id),
            narrative: .init(description: wDesc, category: "이체"),
            kind: .transfer, contentHash: wHash
        )

        let dHash = ContentHash.transactionHash(
            date: date, time: nil, amountMinor: absAmount, currency: currency,
            instrumentID: toAccount.id, description: "\(dDesc)|pair:\(depositID)", balanceAfterMinor: nil
        )
        let deposit = MoneyTransaction(
            id: depositID, stamp: .init(date: date),
            amount: .init(amountMinor: absAmount, currency: currency),
            parties: .init(accountID: toAccount.id),
            narrative: .init(description: dDesc, category: "이체"),
            kind: .transfer, contentHash: dHash
        )
        return (withdrawal, deposit)
    }

    /// 계좌에서 카드 대금 결제 (계좌 출금 + 카드 납부 쌍 생성).
    public func settleCard(
        fromAccountID: String,
        cardID: String,
        amountMinor: Int64,
        currency: String = "KRW",
        date: String,
        description: String? = nil
    ) throws -> (withdrawal: MoneyTransaction, settlement: MoneyTransaction) {
        let fromAccount = try resolveAccount(fromAccountID)
        let card = try resolveCard(cardID)
        let pair = buildSettleTransactions(
            fromAccount: fromAccount, card: card,
            amountMinor: amountMinor, currency: currency,
            date: date, description: description
        )
        return try inTransaction {
            let wOutcome = try insert(transaction: pair.withdrawal)
            let sOutcome = try insert(transaction: pair.settlement)
            return (wOutcome.transaction, sOutcome.transaction)
        }
    }

    private func buildSettleTransactions(
        fromAccount: MoneyAccount, card: MoneyCard,
        amountMinor: Int64, currency: String,
        date: String, description: String?
    ) -> (withdrawal: MoneyTransaction, settlement: MoneyTransaction) {
        let absAmount = abs(amountMinor)
        let baseDesc = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let wDesc = (baseDesc?.isEmpty == false) ? "\(baseDesc ?? "") (출금)" : "\(card.name) 카드대금 결제"
        let sDesc = (baseDesc?.isEmpty == false) ? "\(baseDesc ?? "") (납부)" : "\(card.name) 대금 납부"
        let withdrawalID = UUID().uuidString.lowercased()
        let settlementID = UUID().uuidString.lowercased()

        let wHash = ContentHash.transactionHash(
            date: date, time: nil, amountMinor: -absAmount, currency: currency,
            instrumentID: fromAccount.id, description: "\(wDesc)|settle:\(withdrawalID)", balanceAfterMinor: nil
        )
        let withdrawal = MoneyTransaction(
            id: withdrawalID, stamp: .init(date: date),
            amount: .init(amountMinor: -absAmount, currency: currency),
            parties: .init(accountID: fromAccount.id),
            narrative: .init(description: wDesc, category: "카드대금"),
            kind: .settlement, contentHash: wHash
        )

        let sHash = ContentHash.transactionHash(
            date: date, time: nil, amountMinor: absAmount, currency: currency,
            instrumentID: card.id, description: "\(sDesc)|settle:\(settlementID)", balanceAfterMinor: nil
        )
        let settlement = MoneyTransaction(
            id: settlementID, stamp: .init(date: date),
            amount: .init(amountMinor: absAmount, currency: currency),
            parties: .init(cardID: card.id),
            narrative: .init(description: sDesc, category: "카드대금"),
            kind: .settlement, contentHash: sHash
        )
        return (withdrawal, settlement)
    }

    // MARK: - 가져오기 배치

    public func save(batch: ImportBatch) throws {
        let payload = try encode(batch)
        try executeMutation("""
            INSERT INTO import_batches(id, created_at, source_file, inserted, payload)
            VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              created_at=excluded.created_at, source_file=excluded.source_file,
              inserted=excluded.inserted, payload=excluded.payload
            """) { statement in
            bind(batch.id, at: 1, to: statement)
            sqlite3_bind_double(statement, 2, batch.createdAt.timeIntervalSince1970)
            bind(batch.sourceFile, at: 3, to: statement)
            sqlite3_bind_int(statement, 4, Int32(batch.inserted))
            bind(payload, at: 5, to: statement)
        }
    }

    public func importBatches() throws -> [ImportBatch] {
        try listPayloads(ImportBatch.self, sql: "SELECT payload FROM import_batches ORDER BY created_at DESC, id")
    }

    public func importBatch(idPrefix: String) throws -> ImportBatch {
        try requireOne(ImportBatch.self, table: "import_batches", idPrefix: idPrefix)
    }

    /// 배치가 넣은 거래 수(undo 미리보기).
    public func transactionCount(inBatch batchID: String) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM transactions WHERE import_batch_id = ?")
        defer { sqlite3_finalize(statement) }
        bind(batchID, at: 1, to: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    /// 배치 undo — 그 배치가 넣은 거래 전부 + 배치 기록을 한 트랜잭션으로 지운다.
    public func undoImportBatch(id: String) throws -> Int {
        try inTransaction {
            let removed = try transactionCount(inBatch: id)
            try executeMutation("DELETE FROM transactions WHERE import_batch_id = ?") {
                bind(id, at: 1, to: $0)
            }
            try executeMutation("DELETE FROM import_batches WHERE id = ?") { bind(id, at: 1, to: $0) }
            return removed
        }
    }
}
