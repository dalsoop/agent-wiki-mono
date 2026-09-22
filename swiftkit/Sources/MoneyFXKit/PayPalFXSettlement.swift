import Foundation

/// Represents a PayPal cross-border transaction in foreign currency (typically USD).
public struct PayPalTransaction: Equatable, Codable, Sendable {
    public let id: String
    public let transactionDateKey: String
    public let grossUSD: Decimal
    public let feeUSD: Decimal

    public init(id: String, transactionDateKey: String, grossUSD: Decimal, feeUSD: Decimal) {
        self.id = id
        self.transactionDateKey = transactionDateKey
        self.grossUSD = grossUSD
        self.feeUSD = feeUSD
    }

    public var netUSD: Decimal {
        grossUSD - feeUSD
    }
}

/// Initial accounting recognition entry for a PayPal transaction converted at payment date benchmark rate.
public struct PayPalAccountingEntry: Equatable, Codable, Sendable {
    public let transactionId: String
    public let transactionDateKey: String
    public let benchmarkRate: Decimal
    public let grossKRW: Decimal         // 매출액 (수익)
    public let feeKRW: Decimal           // 지급수수료 (비용)
    public let netReceivableKRW: Decimal // 외화예금 또는 미수금 (자산)

    public init(
        transactionId: String,
        transactionDateKey: String,
        benchmarkRate: Decimal,
        grossKRW: Decimal,
        feeKRW: Decimal,
        netReceivableKRW: Decimal
    ) {
        self.transactionId = transactionId
        self.transactionDateKey = transactionDateKey
        self.benchmarkRate = benchmarkRate
        self.grossKRW = grossKRW
        self.feeKRW = feeKRW
        self.netReceivableKRW = netReceivableKRW
    }
}

/// Settlement / Withdrawal event of PayPal balance to Korean bank account.
public struct PayPalSettlementEvent: Equatable, Codable, Sendable {
    public let settlementId: String
    public let settlementDateKey: String
    public let settledUSD: Decimal
    /// Actual KRW received in bank account. If nil, calculated via benchmark rate on settlement date.
    public let actualKRWReceived: Decimal?

    public init(
        settlementId: String,
        settlementDateKey: String,
        settledUSD: Decimal,
        actualKRWReceived: Decimal? = nil
    ) {
        self.settlementId = settlementId
        self.settlementDateKey = settlementDateKey
        self.settledUSD = settledUSD
        self.actualKRWReceived = actualKRWReceived
    }
}

/// Result of evaluating a PayPal settlement against initial transaction book values.
public struct PayPalSettlementResult: Equatable, Codable, Sendable {
    public let transactionId: String
    public let settlementId: String
    public let settledUSD: Decimal
    public let initialBookValueKRW: Decimal
    public let settledValueKRW: Decimal
    public let realizedGainLossKRW: Decimal
    public let kind: FXGainLossKind

    public init(
        transactionId: String,
        settlementId: String,
        settledUSD: Decimal,
        initialBookValueKRW: Decimal,
        settledValueKRW: Decimal,
        realizedGainLossKRW: Decimal,
        kind: FXGainLossKind
    ) {
        self.transactionId = transactionId
        self.settlementId = settlementId
        self.settledUSD = settledUSD
        self.initialBookValueKRW = initialBookValueKRW
        self.settledValueKRW = settledValueKRW
        self.realizedGainLossKRW = realizedGainLossKRW
        self.kind = kind
    }

    public var isGain: Bool {
        realizedGainLossKRW > 0
    }

    public var isLoss: Bool {
        realizedGainLossKRW < 0
    }
}

public struct PayPalFXCalculator: Sendable {
    public init() {}

    /// Recognizes PayPal revenue and fee at the payment date benchmark rate.
    public func recognizeTransaction(
        transaction: PayPalTransaction,
        rateTable: ExchangeRateTable
    ) throws -> PayPalAccountingEntry {
        guard let rate = rateTable.rate(on: transaction.transactionDateKey, base: .USD, target: .KRW) else {
            throw FXError.rateNotFound(source: .USD, target: .KRW, date: transaction.transactionDateKey)
        }

        let grossKRW = transaction.grossUSD * rate.rate
        let feeKRW = transaction.feeUSD * rate.rate
        let netKRW = transaction.netUSD * rate.rate

        return PayPalAccountingEntry(
            transactionId: transaction.id,
            transactionDateKey: transaction.transactionDateKey,
            benchmarkRate: rate.rate,
            grossKRW: grossKRW,
            feeKRW: feeKRW,
            netReceivableKRW: netKRW
        )
    }

    /// Calculates settlement difference (외환차손익) when PayPal USD is withdrawn/settled to KRW.
    public func calculateSettlement(
        entry: PayPalAccountingEntry,
        originalNetUSD: Decimal,
        settlement: PayPalSettlementEvent,
        rateTable: ExchangeRateTable
    ) throws -> PayPalSettlementResult {
        guard originalNetUSD > 0 else {
            throw FXError.divisionByZero
        }

        let settledPortionRatio = settlement.settledUSD / originalNetUSD
        let initialBookValueKRW = entry.netReceivableKRW * settledPortionRatio

        let settledValueKRW: Decimal
        if let actual = settlement.actualKRWReceived {
            settledValueKRW = actual
        } else {
            guard let settleRate = rateTable.rate(on: settlement.settlementDateKey, base: .USD, target: .KRW) else {
                throw FXError.rateNotFound(source: .USD, target: .KRW, date: settlement.settlementDateKey)
            }
            settledValueKRW = settlement.settledUSD * settleRate.rate
        }

        let diff = settledValueKRW - initialBookValueKRW
        let kind: FXGainLossKind
        if diff > 0 {
            kind = .realizedGain
        } else if diff < 0 {
            kind = .realizedLoss
        } else {
            kind = .neutral
        }

        return PayPalSettlementResult(
            transactionId: entry.transactionId,
            settlementId: settlement.settlementId,
            settledUSD: settlement.settledUSD,
            initialBookValueKRW: initialBookValueKRW,
            settledValueKRW: settledValueKRW,
            realizedGainLossKRW: diff,
            kind: kind
        )
    }
}
