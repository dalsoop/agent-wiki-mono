import XCTest
import MoneyAccountingKit
@testable import BankScraperKit

final class BankScraperKitTests: XCTestCase {
    
    func testTransactionNormalizerCSV() throws {
        let normalizer = TransactionNormalizer()
        
        let csvContent = """
        Timestamp,Deposit,Withdrawal,Balance,Description,Type
        2026-09-02T10:00:00Z,10000,0,10000,용돈,입금
        2026-09-02T11:00:00Z,0,5000,5000,식비,출금
        """
        
        let transactions = try normalizer.normalize(content: csvContent, format: "csv", accountNumber: "123-456-789")
        
        XCTAssertEqual(transactions.count, 2)
        XCTAssertEqual(transactions[0].depositAmount, 10000)
        XCTAssertEqual(transactions[0].description, "용돈")
        XCTAssertEqual(transactions[1].withdrawalAmount, 5000)
        XCTAssertEqual(transactions[1].description, "식비")
    }
    
    func testJournalEntryMapperDeposit() throws {
        let transaction = BankTransaction(
            timestamp: Date(),
            depositAmount: 10000,
            withdrawalAmount: 0,
            balanceAfterTransaction: 10000,
            description: "용돈",
            accountNumber: "123",
            transactionType: "입금"
        )
        
        let mapper = JournalEntryMapper()
        let entry = try mapper.mapToJournalEntry(transaction: transaction)
        
        XCTAssertEqual(entry.debits.count, 1)
        XCTAssertEqual(entry.debits[0].accountCode, StandardAccountCode.bankDeposit)
        XCTAssertEqual(entry.debits[0].amount, 10000)
        
        XCTAssertEqual(entry.credits.count, 1)
        XCTAssertEqual(entry.credits[0].accountCode, StandardAccountCode.sales)
        XCTAssertEqual(entry.credits[0].amount, 10000)
    }
    
    func testJournalEntryMapperWithdrawal() throws {
        let transaction = BankTransaction(
            timestamp: Date(),
            depositAmount: 0,
            withdrawalAmount: 5000,
            balanceAfterTransaction: 5000,
            description: "급여",
            accountNumber: "123",
            transactionType: "출금"
        )
        
        let mapper = JournalEntryMapper()
        let entry = try mapper.mapToJournalEntry(transaction: transaction)
        
        XCTAssertEqual(entry.credits.count, 1)
        XCTAssertEqual(entry.credits[0].accountCode, StandardAccountCode.bankDeposit)
        XCTAssertEqual(entry.credits[0].amount, 5000)
        
        XCTAssertEqual(entry.debits.count, 1)
        XCTAssertEqual(entry.debits[0].accountCode, StandardAccountCode.salaries)
        XCTAssertEqual(entry.debits[0].amount, 5000)
    }
}
