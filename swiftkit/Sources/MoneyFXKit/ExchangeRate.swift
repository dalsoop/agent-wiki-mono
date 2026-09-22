import Foundation
import os

public struct ExchangeRate: Equatable, Codable, Sendable, Hashable {
    public let baseCurrency: CurrencyCode
    public let targetCurrency: CurrencyCode
    public let rate: Decimal
    public let date: Date
    public let dateKey: String
    
    public init(baseCurrency: CurrencyCode, targetCurrency: CurrencyCode, rate: Decimal, date: Date) {
        self.baseCurrency = baseCurrency
        self.targetCurrency = targetCurrency
        self.rate = rate
        self.date = date
        self.dateKey = Self.formatDateKey(date)
    }
    
    public init(baseCurrency: CurrencyCode, targetCurrency: CurrencyCode, rate: Decimal, dateKey: String) {
        self.baseCurrency = baseCurrency
        self.targetCurrency = targetCurrency
        self.rate = rate
        self.dateKey = dateKey
        self.date = Self.parseDateKey(dateKey) ?? Date(timeIntervalSince1970: 0)
    }
    
    public var invertedRate: Decimal {
        guard rate != 0 else { return 0 }
        return Decimal(1) / rate
    }
    
    public var inverted: ExchangeRate {
        ExchangeRate(
            baseCurrency: targetCurrency,
            targetCurrency: baseCurrency,
            rate: invertedRate,
            date: date
        )
    }

    private static let keyFormatterLock = OSAllocatedUnfairLock(initialState: {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 9 * 3600) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }())

    public static func formatDateKey(_ date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        keyFormatterLock.withLock { formatter in
            let oldCal = formatter.calendar
            formatter.calendar = calendar
            let res = formatter.string(from: date)
            formatter.calendar = oldCal
            return res
        }
    }

    public static func parseDateKey(_ string: String) -> Date? {
        keyFormatterLock.withLock { $0.date(from: string) }
    }
}
