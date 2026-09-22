import Foundation

public struct AccountBalance: Equatable, Codable, Sendable {
    public var accountNumber: String
    public var balance: Int64
    public var asOf: Date

    public init(accountNumber: String, balance: Int64, asOf: Date) {
        self.accountNumber = accountNumber
        self.balance = balance
        self.asOf = asOf
    }
}
