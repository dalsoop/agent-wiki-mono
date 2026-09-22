import Foundation

public enum FXGainLossKind: String, Codable, Equatable, Sendable {
    case realizedGain      // 외환차익 (결제/회수 시점 실현 이익)
    case realizedLoss      // 외환차손 (결제/회수 시점 실현 손실)
    case unrealizedGain    // 외화환산이익 (결산기말 미실현 평가 이익)
    case unrealizedLoss    // 외화환산손실 (결산기말 미실현 평가 손실)
    case neutral           // 변동 없음
}

public struct FXGainLossResult: Equatable, Codable, Sendable {
    public let foreignAmount: Decimal
    public let baseCurrency: CurrencyCode
    public let targetCurrency: CurrencyCode
    public let initialTargetValue: Decimal
    public let finalTargetValue: Decimal
    public let gainLossAmount: Decimal
    public let isAsset: Bool
    public let kind: FXGainLossKind

    public init(
        foreignAmount: Decimal,
        baseCurrency: CurrencyCode,
        targetCurrency: CurrencyCode,
        initialTargetValue: Decimal,
        finalTargetValue: Decimal,
        gainLossAmount: Decimal,
        isAsset: Bool,
        kind: FXGainLossKind
    ) {
        self.foreignAmount = foreignAmount
        self.baseCurrency = baseCurrency
        self.targetCurrency = targetCurrency
        self.initialTargetValue = initialTargetValue
        self.finalTargetValue = finalTargetValue
        self.gainLossAmount = gainLossAmount
        self.isAsset = isAsset
        self.kind = kind
    }

    public var isGain: Bool {
        gainLossAmount > 0
    }

    public var isLoss: Bool {
        gainLossAmount < 0
    }
}

public struct FXGainLossCalculator: Sendable {
    public init() {}
    
    /// Calculate foreign exchange gain or loss.
    /// - Parameters:
    ///   - foreignAmount: The amount in foreign currency (base currency of the rate).
    ///   - transactionRate: The exchange rate at the time of the transaction.
    ///   - settlementRate: The exchange rate at the time of settlement or evaluation.
    ///   - isAsset: True if the foreign amount represents an asset, false if a liability.
    /// - Returns: The gain or loss in target currency. Positive means gain, negative means loss.
    public func calculateGainLoss(
        foreignAmount: Decimal,
        transactionRate: ExchangeRate,
        settlementRate: ExchangeRate,
        isAsset: Bool = true
    ) throws -> Decimal {
        guard transactionRate.baseCurrency == settlementRate.baseCurrency,
              transactionRate.targetCurrency == settlementRate.targetCurrency else {
            throw FXError.invalidCurrencyPair
        }
        
        let transactionValue = foreignAmount * transactionRate.rate
        let settlementValue = foreignAmount * settlementRate.rate
        
        let difference = settlementValue - transactionValue
        return isAsset ? difference : -difference
    }

    /// Calculate realized foreign exchange gain/loss (외환차손익).
    public func calculateRealized(
        foreignAmount: Decimal,
        transactionRate: ExchangeRate,
        settlementRate: ExchangeRate,
        isAsset: Bool = true
    ) throws -> FXGainLossResult {
        let diff = try calculateGainLoss(
            foreignAmount: foreignAmount,
            transactionRate: transactionRate,
            settlementRate: settlementRate,
            isAsset: isAsset
        )
        let initialVal = foreignAmount * transactionRate.rate
        let finalVal = foreignAmount * settlementRate.rate
        
        let kind: FXGainLossKind
        if diff > 0 {
            kind = .realizedGain
        } else if diff < 0 {
            kind = .realizedLoss
        } else {
            kind = .neutral
        }

        return FXGainLossResult(
            foreignAmount: foreignAmount,
            baseCurrency: transactionRate.baseCurrency,
            targetCurrency: transactionRate.targetCurrency,
            initialTargetValue: initialVal,
            finalTargetValue: finalVal,
            gainLossAmount: diff,
            isAsset: isAsset,
            kind: kind
        )
    }

    /// Calculate unrealized foreign currency valuation gain/loss (외화환산손익).
    public func calculateUnrealized(
        foreignAmount: Decimal,
        bookRate: ExchangeRate,
        evaluationRate: ExchangeRate,
        isAsset: Bool = true
    ) throws -> FXGainLossResult {
        let diff = try calculateGainLoss(
            foreignAmount: foreignAmount,
            transactionRate: bookRate,
            settlementRate: evaluationRate,
            isAsset: isAsset
        )
        let initialVal = foreignAmount * bookRate.rate
        let finalVal = foreignAmount * evaluationRate.rate

        let kind: FXGainLossKind
        if diff > 0 {
            kind = .unrealizedGain
        } else if diff < 0 {
            kind = .unrealizedLoss
        } else {
            kind = .neutral
        }

        return FXGainLossResult(
            foreignAmount: foreignAmount,
            baseCurrency: bookRate.baseCurrency,
            targetCurrency: bookRate.targetCurrency,
            initialTargetValue: initialVal,
            finalTargetValue: finalVal,
            gainLossAmount: diff,
            isAsset: isAsset,
            kind: kind
        )
    }
}
