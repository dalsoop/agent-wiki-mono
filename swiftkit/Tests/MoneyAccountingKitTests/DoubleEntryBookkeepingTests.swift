import XCTest
@testable import MoneyAccountingKit

final class DoubleEntryBookkeepingTests: XCTestCase {
    func testJournalEntryBalanceValidation() {
        XCTAssertThrowsError(try JournalEntry(
            date: Date(),
            description: "Unbalanced",
            debits: [.init(accountCode: .cash, amount: 1000)],
            credits: [.init(accountCode: .sales, amount: 900)]
        )) { error in
            XCTAssertEqual(error as? AccountingError, .unbalancedJournalEntry(debit: 1000, credit: 900))
        }
        
        XCTAssertNoThrow(try JournalEntry(
            date: Date(),
            description: "Balanced",
            debits: [.init(accountCode: .cash, amount: 1000)],
            credits: [.init(accountCode: .sales, amount: 1000)]
        ))
    }
    
    func testLedgerPostingAndBalance() throws {
        var ledger = LedgerBook()
        let entry1 = try JournalEntry(
            date: Date(),
            description: "Initial capital",
            debits: [.init(accountCode: .cash, amount: 10000)],
            credits: [.init(accountCode: .capital, amount: 10000)]
        )
        ledger.post(entry1)
        
        let entry2 = try JournalEntry(
            date: Date(),
            description: "Sales",
            debits: [.init(accountCode: .cash, amount: 5000)],
            credits: [.init(accountCode: .sales, amount: 5000)]
        )
        ledger.post(entry2)
        
        XCTAssertEqual(ledger.balance(for: .cash), 15000)
        XCTAssertEqual(ledger.balance(for: .capital), 10000)
        XCTAssertEqual(ledger.balance(for: .sales), 5000)
    }
    
    func testFinancialStatementsGeneration() throws {
        var ledger = LedgerBook()
        try ledger.post(JournalEntry(
            date: Date(),
            description: "Capital",
            debits: [.init(accountCode: .cash, amount: 10000)],
            credits: [.init(accountCode: .capital, amount: 10000)]
        ))
        try ledger.post(JournalEntry(
            date: Date(),
            description: "Sales",
            debits: [.init(accountCode: .accountsReceivable, amount: 5000)],
            credits: [.init(accountCode: .sales, amount: 5000)]
        ))
        try ledger.post(JournalEntry(
            date: Date(),
            description: "Salaries",
            debits: [.init(accountCode: .salaries, amount: 2000)],
            credits: [.init(accountCode: .cash, amount: 2000)]
        ))
        
        let incomeStatement = FinancialStatements.generateIncomeStatement(from: ledger)
        XCTAssertEqual(incomeStatement.totalRevenue, 5000)
        XCTAssertEqual(incomeStatement.totalExpense, 2000)
        XCTAssertEqual(incomeStatement.netIncome, 3000)
        
        let balanceSheet = FinancialStatements.generateBalanceSheet(from: ledger)
        XCTAssertEqual(balanceSheet.totalAssets, 13000) // 8000 cash + 5000 AR
        XCTAssertEqual(balanceSheet.totalLiabilities, 0)
        // Capital 10000 + Retained earnings 3000 = 13000
        XCTAssertEqual(balanceSheet.totalEquity, 13000)
        
        XCTAssertEqual(balanceSheet.totalAssets, balanceSheet.totalLiabilities + balanceSheet.totalEquity)
    }
}
