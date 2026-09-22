import Foundation

/// Applicable rule for zero-rated export tax base conversion under Korean VAT law.
public enum ZeroRatedConversionRule: String, Codable, Equatable, Sendable {
    /// 공급시기(선적일) 전 원화 환전: 실제 환전된 원화 금액 적용
    case preSupplyExchangedToKRW
    /// 공급시기 이후 환전 또는 미환전 외화 보유: 공급시기의 기준환율 적용
    case supplyDateBenchmarkRate
}

/// Case data for export of goods or services.
public struct ZeroRatedExportCase: Equatable, Codable, Sendable {
    public let exportId: String
    public let foreignAmount: Decimal
    public let currency: CurrencyCode
    public let supplyDateKey: String        // 공급시기(선적일/용역제공완료일) YYYY-MM-DD
    public let exchangeDateKey: String?     // 원화 환전일 YYYY-MM-DD
    public let actualExchangedKRW: Decimal? // 실제 환전한 원화 금액

    public init(
        exportId: String,
        foreignAmount: Decimal,
        currency: CurrencyCode,
        supplyDateKey: String,
        exchangeDateKey: String? = nil,
        actualExchangedKRW: Decimal? = nil
    ) {
        self.exportId = exportId
        self.foreignAmount = foreignAmount
        self.currency = currency
        self.supplyDateKey = supplyDateKey
        self.exchangeDateKey = exchangeDateKey
        self.actualExchangedKRW = actualExchangedKRW
    }
}

/// Tax base calculation result for zero-rated export sales (영세율 매출 과세표준).
public struct ZeroRatedExportTaxBaseResult: Equatable, Codable, Sendable {
    public let exportId: String
    public let taxableSupplyValueKRW: Decimal // 영세율 과세표준 (원화)
    public let appliedRate: Decimal?          // 적용된 기준환율 (선적일 기준환율 적용 시)
    public let ruleApplied: ZeroRatedConversionRule
    public let note: String

    public init(
        exportId: String,
        taxableSupplyValueKRW: Decimal,
        appliedRate: Decimal?,
        ruleApplied: ZeroRatedConversionRule,
        note: String
    ) {
        self.exportId = exportId
        self.taxableSupplyValueKRW = taxableSupplyValueKRW
        self.appliedRate = appliedRate
        self.ruleApplied = ruleApplied
        self.note = note
    }
}

public struct ZeroRatedExportCalculator: Sendable {
    public init() {}

    /// Calculates Korean VAT zero-rated export taxable supply value (영세율 과세표준 공급가액).
    public func calculateTaxBase(
        exportCase: ZeroRatedExportCase,
        rateTable: ExchangeRateTable
    ) throws -> ZeroRatedExportTaxBaseResult {
        // Case 1: Exchanged to KRW before or on the supply date
        if let exchangeDate = exportCase.exchangeDateKey,
           let actualKRW = exportCase.actualExchangedKRW,
           exchangeDate <= exportCase.supplyDateKey {
            return ZeroRatedExportTaxBaseResult(
                exportId: exportCase.exportId,
                taxableSupplyValueKRW: actualKRW,
                appliedRate: nil,
                ruleApplied: .preSupplyExchangedToKRW,
                note: "공급시기(선적일 \(exportCase.supplyDateKey)) 이전 환전(\(exchangeDate)): 실제 환전액 적용"
            )
        }

        // Case 2: Exchanged after supply date or kept in foreign currency
        guard let benchmarkRate = rateTable.rate(
            on: exportCase.supplyDateKey,
            base: exportCase.currency,
            target: .KRW
        ) else {
            throw FXError.rateNotFound(
                source: exportCase.currency,
                target: .KRW,
                date: exportCase.supplyDateKey
            )
        }

        let supplyValueKRW = exportCase.foreignAmount * benchmarkRate.rate
        return ZeroRatedExportTaxBaseResult(
            exportId: exportCase.exportId,
            taxableSupplyValueKRW: supplyValueKRW,
            appliedRate: benchmarkRate.rate,
            ruleApplied: .supplyDateBenchmarkRate,
            note: "공급시기(선적일 \(exportCase.supplyDateKey)) 기준환율(\(benchmarkRate.rate)) 적용"
        )
    }
}
