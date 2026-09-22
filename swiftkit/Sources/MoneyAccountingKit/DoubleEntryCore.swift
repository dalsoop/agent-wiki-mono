import Foundation

public enum AccountType: String, Codable, Sendable, CaseIterable {
    case asset
    case liability
    case equity
    case revenue
    case expense
}

/// 표준 계정과목 체계 (100~500번대)
public struct StandardAccountCode: Codable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let type: AccountType
    
    public init(id: Int, name: String, type: AccountType) {
        self.id = id
        self.name = name
        self.type = type
    }
    
    public static let cash = StandardAccountCode(id: 101, name: "현금", type: .asset)
    public static let bankDeposit = StandardAccountCode(id: 103, name: "보통예금", type: .asset)
    public static let accountsReceivable = StandardAccountCode(id: 108, name: "외상매출금", type: .asset)
    
    public static let accountsPayable = StandardAccountCode(id: 251, name: "외상매입금", type: .liability)
    public static let shortTermBorrowings = StandardAccountCode(id: 260, name: "단기차입금", type: .liability)
    
    public static let capital = StandardAccountCode(id: 331, name: "자본금", type: .equity)
    
    public static let sales = StandardAccountCode(id: 401, name: "상품매출", type: .revenue)
    
    public static let costOfSales = StandardAccountCode(id: 501, name: "매출원가", type: .expense)
    public static let salaries = StandardAccountCode(id: 801, name: "급여", type: .expense)
}

public struct JournalEntry: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let date: Date
    public let description: String
    public let debits: [LineItem]
    public let credits: [LineItem]
    
    public struct LineItem: Codable, Sendable, Hashable {
        public let accountCode: StandardAccountCode
        public let amount: Int64
        
        public init(accountCode: StandardAccountCode, amount: Int64) {
            self.accountCode = accountCode
            self.amount = amount
        }
    }
    
    public init(id: UUID = UUID(), date: Date, description: String, debits: [LineItem], credits: [LineItem]) throws {
        self.id = id
        self.date = date
        self.description = description
        self.debits = debits
        self.credits = credits
        
        let totalDebit = debits.map(\.amount).reduce(0, +)
        let totalCredit = credits.map(\.amount).reduce(0, +)
        
        if totalDebit != totalCredit {
            throw AccountingError.unbalancedJournalEntry(debit: totalDebit, credit: totalCredit)
        }
    }
}

public enum AccountingError: Error, Equatable {
    case unbalancedJournalEntry(debit: Int64, credit: Int64)
}

public struct LedgerBook: Sendable {
    private var entries: [JournalEntry] = []
    
    public init() {}
    
    public mutating func post(_ entry: JournalEntry) {
        entries.append(entry)
    }
    
    public func balance(for account: StandardAccountCode) -> Int64 {
        var balance: Int64 = 0
        for entry in entries {
            for debit in entry.debits where debit.accountCode == account {
                balance += (account.type == .asset || account.type == .expense) ? debit.amount : -debit.amount
            }
            for credit in entry.credits where credit.accountCode == account {
                balance += (account.type == .asset || account.type == .expense) ? -credit.amount : credit.amount
            }
        }
        return balance
    }
    
    public func balances() -> [StandardAccountCode: Int64] {
        var result: [StandardAccountCode: Int64] = [:]
        for entry in entries {
            for debit in entry.debits {
                let current = result[debit.accountCode] ?? 0
                let amount = (debit.accountCode.type == .asset || debit.accountCode.type == .expense) ? debit.amount : -debit.amount
                result[debit.accountCode] = current + amount
            }
            for credit in entry.credits {
                let current = result[credit.accountCode] ?? 0
                let amount = (credit.accountCode.type == .asset || credit.accountCode.type == .expense) ? -credit.amount : credit.amount
                result[credit.accountCode] = current + amount
            }
        }
        return result
    }
    
    public var allEntries: [JournalEntry] {
        return entries
    }
}

public struct FinancialStatements: Sendable {
    public struct BalanceSheet {
        public var assets: [StandardAccountCode: Int64] = [:]
        public var liabilities: [StandardAccountCode: Int64] = [:]
        public var equity: [StandardAccountCode: Int64] = [:]
        
        public var totalAssets: Int64 { assets.values.reduce(0, +) }
        public var totalLiabilities: Int64 { liabilities.values.reduce(0, +) }
        public var totalEquity: Int64 { equity.values.reduce(0, +) }
    }
    
    public struct DoubleEntryIncomeStatement {
        public var revenues: [StandardAccountCode: Int64] = [:]
        public var expenses: [StandardAccountCode: Int64] = [:]
        
        public var totalRevenue: Int64 { revenues.values.reduce(0, +) }
        public var totalExpense: Int64 { expenses.values.reduce(0, +) }
        public var netIncome: Int64 { totalRevenue - totalExpense }
    }
    
    public static func generateBalanceSheet(from ledger: LedgerBook) -> BalanceSheet {
        var sheet = BalanceSheet()
        let balances = ledger.balances()
        for (account, balance) in balances {
            switch account.type {
            case .asset: sheet.assets[account] = balance
            case .liability: sheet.liabilities[account] = balance
            case .equity: sheet.equity[account] = balance
            default: break
            }
        }
        // Retained earnings calculation
        let ismt = generateIncomeStatement(from: ledger)
        if let retainedEarnings = sheet.equity[StandardAccountCode(id: 379, name: "이익잉여금", type: .equity)] {
            sheet.equity[StandardAccountCode(id: 379, name: "이익잉여금", type: .equity)] = retainedEarnings + ismt.netIncome
        } else if ismt.netIncome != 0 {
            sheet.equity[StandardAccountCode(id: 379, name: "이익잉여금", type: .equity)] = ismt.netIncome
        }
        
        return sheet
    }
    
    public static func generateIncomeStatement(from ledger: LedgerBook) -> DoubleEntryIncomeStatement {
        var sheet = DoubleEntryIncomeStatement()
        let balances = ledger.balances()
        for (account, balance) in balances {
            switch account.type {
            case .revenue: sheet.revenues[account] = balance
            case .expense: sheet.expenses[account] = balance
            default: break
            }
        }
        return sheet
    }
}
