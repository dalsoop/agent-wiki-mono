import Foundation

public struct FXConverter: Sendable {
    public init() {}
    
    public func convert(
        amount: Decimal,
        from sourceCurrency: CurrencyCode,
        to targetCurrency: CurrencyCode,
        rate: ExchangeRate
    ) throws -> Decimal {
        if sourceCurrency == targetCurrency {
            return amount
        }
        if sourceCurrency == rate.baseCurrency && targetCurrency == rate.targetCurrency {
            return amount * rate.rate
        }
        guard sourceCurrency == rate.targetCurrency && targetCurrency == rate.baseCurrency else {
            throw FXError.invalidCurrencyPair
        }
        guard rate.rate != 0 else {
            return 0
        }
        return amount / rate.rate
    }

    /// Convert USD to KRW using rate (rate is KRW per 1 USD)
    public func convertUSDToKRW(usdAmount: Decimal, rate: Decimal) -> Decimal {
        usdAmount * rate
    }

    /// Convert KRW to USD using rate (rate is KRW per 1 USD)
    public func convertKRWToUSD(krwAmount: Decimal, rate: Decimal) throws -> Decimal {
        guard rate != 0 else { throw FXError.divisionByZero }
        return krwAmount / rate
    }
}
