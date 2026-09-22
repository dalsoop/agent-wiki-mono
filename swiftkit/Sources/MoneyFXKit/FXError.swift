import Foundation

public enum FXError: Error, Equatable, Sendable {
    case invalidCurrencyPair
    case rateNotFound(source: CurrencyCode, target: CurrencyCode, date: String)
    case divisionByZero
    case missingSettlementInfo(String)
}
