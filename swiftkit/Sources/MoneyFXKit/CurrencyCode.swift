import Foundation

public enum CurrencyCode: String, Codable, Equatable, Hashable, CaseIterable, Sendable {
    case KRW
    case USD
    case JPY
    case EUR
    case CNY
    
    public var symbol: String {
        switch self {
        case .KRW: return "₩"
        case .USD: return "$"
        case .JPY: return "¥"
        case .EUR: return "€"
        case .CNY: return "¥"
        }
    }
}
