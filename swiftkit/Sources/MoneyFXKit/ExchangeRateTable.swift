import Foundation

/// In-memory exchange rate table for benchmark rates (기준환율 / 매매기준율).
/// Pure value type without external network or file I/O.
public struct ExchangeRateTable: Codable, Equatable, Sendable {
    private var ratesByKey: [String: ExchangeRate]
    private var sortedDatesByPair: [String: [String]]

    public init(rates: [ExchangeRate] = []) {
        self.ratesByKey = [:]
        self.sortedDatesByPair = [:]
        addRates(rates)
    }

    public var count: Int {
        ratesByKey.count
    }

    public mutating func addRate(_ rate: ExchangeRate) {
        let pairKey = "\(rate.baseCurrency.rawValue):\(rate.targetCurrency.rawValue)"
        let fullKey = "\(pairKey):\(rate.dateKey)"
        ratesByKey[fullKey] = rate

        var dates = sortedDatesByPair[pairKey] ?? []
        if !dates.contains(rate.dateKey) {
            dates.append(rate.dateKey)
            dates.sort()
            sortedDatesByPair[pairKey] = dates
        }
    }

    public mutating func addRates(_ rates: [ExchangeRate]) {
        for rate in rates {
            addRate(rate)
        }
    }

    public func rate(
        on dateKey: String,
        base: CurrencyCode,
        target: CurrencyCode,
        fallbackToPreceding: Bool = true
    ) -> ExchangeRate? {
        let pairKey = "\(base.rawValue):\(target.rawValue)"
        let directKey = "\(pairKey):\(dateKey)"
        if let direct = ratesByKey[directKey] {
            return direct
        }
        guard fallbackToPreceding, let availableDates = sortedDatesByPair[pairKey] else {
            return nil
        }
        let precedingDates = availableDates.filter { $0 <= dateKey }
        guard let latestPreceding = precedingDates.last else {
            return nil
        }
        return ratesByKey["\(pairKey):\(latestPreceding)"]
    }

    public func rate(
        on date: Date,
        base: CurrencyCode,
        target: CurrencyCode,
        fallbackToPreceding: Bool = true,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> ExchangeRate? {
        let dateKey = ExchangeRate.formatDateKey(date, calendar: calendar)
        return rate(on: dateKey, base: base, target: target, fallbackToPreceding: fallbackToPreceding)
    }

    public func convert(
        amount: Decimal,
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on dateKey: String,
        fallbackToPreceding: Bool = true
    ) throws -> Decimal {
        if sourceCurrency == targetCurrency {
            return amount
        }
        if let direct = rate(on: dateKey, base: sourceCurrency, target: targetCurrency, fallbackToPreceding: fallbackToPreceding) {
            return amount * direct.rate
        }
        guard let inverse = rate(on: dateKey, base: targetCurrency, target: sourceCurrency, fallbackToPreceding: fallbackToPreceding) else {
            throw FXError.rateNotFound(source: sourceCurrency, target: targetCurrency, date: dateKey)
        }
        guard inverse.rate != 0 else { throw FXError.divisionByZero }
        return amount / inverse.rate
    }

    public func convert(
        amount: Decimal,
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        on date: Date,
        fallbackToPreceding: Bool = true
    ) throws -> Decimal {
        let dateKey = ExchangeRate.formatDateKey(date)
        return try convert(
            amount: amount,
            from: sourceCurrency,
            to: targetCurrency,
            on: dateKey,
            fallbackToPreceding: fallbackToPreceding
        )
    }
}
