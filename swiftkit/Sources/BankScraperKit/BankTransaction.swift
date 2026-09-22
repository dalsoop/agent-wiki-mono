import Foundation

public struct BankTransaction: Equatable, Codable, Sendable {
    public var timestamp: Date
    public var depositAmount: Int64
    public var withdrawalAmount: Int64
    public var balanceAfterTransaction: Int64
    public var description: String
    public var accountNumber: String
    public var transactionType: String

    public init(
        timestamp: Date,
        depositAmount: Int64,
        withdrawalAmount: Int64,
        balanceAfterTransaction: Int64,
        description: String,
        accountNumber: String,
        transactionType: String
    ) {
        self.timestamp = timestamp
        self.depositAmount = depositAmount
        self.withdrawalAmount = withdrawalAmount
        self.balanceAfterTransaction = balanceAfterTransaction
        self.description = description
        self.accountNumber = accountNumber
        self.transactionType = transactionType
    }
}
