import Foundation
import MoneyLedgerModels
import SQLite3

extension LedgerStore {
    // MARK: - 예산 (Budgets)

    public func save(budget: MoneyBudget) throws {
        var budgetToSave = budget
        budgetToSave.updatedAt = .now
        let payload = try encode(budgetToSave)
        try executeMutation("""
            INSERT INTO budgets(id, category, month, amount_minor, currency, created_at, updated_at, payload)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              category=excluded.category, month=excluded.month, amount_minor=excluded.amount_minor,
              currency=excluded.currency, created_at=excluded.created_at, updated_at=excluded.updated_at,
              payload=excluded.payload
            """) { statement in
            bind(budgetToSave.id, at: 1, to: statement)
            bind(budgetToSave.category, at: 2, to: statement)
            bindOptional(budgetToSave.month, at: 3, to: statement)
            sqlite3_bind_int64(statement, 4, budgetToSave.amountMinor)
            bind(budgetToSave.currency, at: 5, to: statement)
            sqlite3_bind_double(statement, 6, budgetToSave.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 7, budgetToSave.updatedAt.timeIntervalSince1970)
            bind(payload, at: 8, to: statement)
        }
        try removeTombstone(entityType: "budget", entityID: budgetToSave.id)
    }

    /// 예산 목록 조회.
    /// - Parameters:
    ///   - month: 대상 월 ("yyyy-MM"). nil이면 전체 예산 반환.
    ///   - exactMatch: true이면 지정된 month와 정확히 일치하는 예산만 반환. false(기본값)이면 해당 월에 적용되는 유효 예산(특정 월 예산 우선, 없으면 기본 month=nil 예산) 반환.
    public func budgets(month: String? = nil, exactMatch: Bool = false) throws -> [MoneyBudget] {
        guard let month else {
            return try listPayloads(MoneyBudget.self, sql: "SELECT payload FROM budgets ORDER BY category, month, id")
        }

        if exactMatch {
            let statement = try prepare("SELECT payload FROM budgets WHERE month = ? ORDER BY category, id")
            defer { sqlite3_finalize(statement) }
            bind(month, at: 1, to: statement)
            return try collect(MoneyBudget.self, statement: statement)
        }

        // 해당 월에 적용되는 유효 예산: 당월 예산(month = ?) 및 기본 예산(month IS NULL)
        let statement = try prepare("""
            SELECT payload FROM budgets
            WHERE month = ? OR month IS NULL
            ORDER BY category, (CASE WHEN month IS NOT NULL THEN 0 ELSE 1 END), id
            """)
        defer { sqlite3_finalize(statement) }
        bind(month, at: 1, to: statement)
        let candidateBudgets = try collect(MoneyBudget.self, statement: statement)

        // 카테고리별로 특정 월 예산 우선 적용 (중복 카테고리 시 최초 매칭된 특정 월 예산 유지)
        var categoryMap: [String: MoneyBudget] = [:]
        for b in candidateBudgets {
            if categoryMap[b.category] == nil {
                categoryMap[b.category] = b
            }
        }
        return categoryMap.values.sorted { $0.category < $1.category }
    }

    public func budget(idPrefix: String) throws -> MoneyBudget {
        try requireOne(MoneyBudget.self, table: "budgets", idPrefix: idPrefix)
    }

    public func budget(category: String, month: String? = nil, currency: String = "KRW") throws -> MoneyBudget? {
        let normCur = MoneyAmount.normalizedCurrency(currency)
        let all = try budgets(month: month)
        return all.first { $0.category.caseInsensitiveCompare(category) == .orderedSame && MoneyAmount.normalizedCurrency($0.currency) == normCur }
    }

    public func deleteBudget(id: String) throws {
        try executeMutation("DELETE FROM budgets WHERE id = ?") { bind(id, at: 1, to: $0) }
        try recordTombstone(entityType: "budget", entityID: id)
    }

    public func deleteBudget(category: String, month: String? = nil, currency: String = "KRW") throws {
        let normCur = MoneyAmount.normalizedCurrency(currency)
        let targets = try budgets().filter {
            $0.category == category && $0.month == month && $0.currency == normCur
        }
        for b in targets {
            try recordTombstone(entityType: "budget", entityID: b.id)
        }
        if let month {
            try executeMutation("DELETE FROM budgets WHERE category = ? AND month = ? AND currency = ?") { statement in
                bind(category, at: 1, to: statement)
                bind(month, at: 2, to: statement)
                bind(normCur, at: 3, to: statement)
            }
        } else {
            try executeMutation("DELETE FROM budgets WHERE category = ? AND month IS NULL AND currency = ?") { statement in
                bind(category, at: 1, to: statement)
                bind(normCur, at: 2, to: statement)
            }
        }
    }
}
