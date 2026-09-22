import Foundation
import MoneyAccountingKit

public struct JournalEntryMapper: Sendable {
    public init() {}
    
    public func mapToJournalEntry(transaction: BankTransaction) throws -> JournalEntry {
        let bankAccount = StandardAccountCode.bankDeposit
        
        let debits: [JournalEntry.LineItem]
        let credits: [JournalEntry.LineItem]
        
        if transaction.depositAmount > 0 {
            debits = [JournalEntry.LineItem(accountCode: bankAccount, amount: transaction.depositAmount)]
            
            let salesAccount = StandardAccountCode.sales
            credits = [JournalEntry.LineItem(accountCode: salesAccount, amount: transaction.depositAmount)]
            
            return try JournalEntry(
                date: transaction.timestamp,
                description: transaction.description,
                debits: debits,
                credits: credits
            )
            
        } else if transaction.withdrawalAmount > 0 {
            credits = [JournalEntry.LineItem(accountCode: bankAccount, amount: transaction.withdrawalAmount)]
            
            let expenseAccount: StandardAccountCode
            if transaction.description.contains("급여") {
                expenseAccount = StandardAccountCode.salaries
            } else {
                expenseAccount = StandardAccountCode.costOfSales
            }
            
            debits = [JournalEntry.LineItem(accountCode: expenseAccount, amount: transaction.withdrawalAmount)]
            
            return try JournalEntry(
                date: transaction.timestamp,
                description: transaction.description,
                debits: debits,
                credits: credits
            )
        } else {
            return try JournalEntry(
                date: transaction.timestamp,
                description: transaction.description,
                debits: [],
                credits: []
            )
        }
    }
}
