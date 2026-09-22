import XCTest
@testable import MoneyFXKit

final class MoneyFXKitTests: XCTestCase {
    
    // MARK: - CurrencyCode Tests
    func testCurrencyCodeSymbol() {
        XCTAssertEqual(CurrencyCode.KRW.symbol, "₩")
        XCTAssertEqual(CurrencyCode.USD.symbol, "$")
        XCTAssertEqual(CurrencyCode.JPY.symbol, "¥")
        XCTAssertEqual(CurrencyCode.EUR.symbol, "€")
        XCTAssertEqual(CurrencyCode.CNY.symbol, "¥")
    }

    // MARK: - ExchangeRate Tests
    func testExchangeRateInversionAndDateKey() {
        let rate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1350.0, dateKey: "2026-09-01")
        XCTAssertEqual(rate.dateKey, "2026-09-01")
        XCTAssertEqual(rate.baseCurrency, .USD)
        XCTAssertEqual(rate.targetCurrency, .KRW)
        
        let inverted = rate.inverted
        XCTAssertEqual(inverted.baseCurrency, .KRW)
        XCTAssertEqual(inverted.targetCurrency, .USD)
        XCTAssertEqual(inverted.dateKey, "2026-09-01")
        XCTAssertEqual(inverted.rate, Decimal(1) / Decimal(1350.0))
    }
    
    // MARK: - FXConverter Tests
    func testFXConverterDirect() throws {
        let converter = FXConverter()
        let rate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, date: Date())
        
        let krwAmount = try converter.convert(amount: 100, from: .USD, to: .KRW, rate: rate)
        XCTAssertEqual(krwAmount, 130000.0)
    }
    
    func testFXConverterInverse() throws {
        let converter = FXConverter()
        let rate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, date: Date())
        
        let usdAmount = try converter.convert(amount: 130000, from: .KRW, to: .USD, rate: rate)
        XCTAssertEqual(usdAmount, 100.0)
    }

    func testFXConverterIdenticalCurrency() throws {
        let converter = FXConverter()
        let rate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, date: Date())
        
        let sameAmount = try converter.convert(amount: 500, from: .USD, to: .USD, rate: rate)
        XCTAssertEqual(sameAmount, 500.0)
    }
    
    func testFXConverterInvalidPair() {
        let converter = FXConverter()
        let rate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, date: Date())
        
        XCTAssertThrowsError(try converter.convert(amount: 100, from: .EUR, to: .KRW, rate: rate)) { error in
            XCTAssertEqual(error as? FXError, FXError.invalidCurrencyPair)
        }
    }

    func testFXConverterUSDAndKRWConvenience() throws {
        let converter = FXConverter()
        let krw = converter.convertUSDToKRW(usdAmount: 150, rate: 1320)
        XCTAssertEqual(krw, 198000)

        let usd = try converter.convertKRWToUSD(krwAmount: 198000, rate: 1320)
        XCTAssertEqual(usd, 150)
    }
    
    // MARK: - FXGainLossCalculator Tests
    func testFXGainLossAsset() throws {
        let calculator = FXGainLossCalculator()
        
        let txRate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1200.0, date: Date())
        let settleRate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, date: Date())
        
        // Asset (e.g. Accounts Receivable) of 100 USD. Rate goes up -> Gain
        let gainLoss = try calculator.calculateGainLoss(
            foreignAmount: 100,
            transactionRate: txRate,
            settlementRate: settleRate,
            isAsset: true
        )
        
        XCTAssertEqual(gainLoss, 10000.0) // (1300 - 1200) * 100
    }
    
    func testFXGainLossLiability() throws {
        let calculator = FXGainLossCalculator()
        
        let txRate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1200.0, date: Date())
        let settleRate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, date: Date())
        
        // Liability (e.g. Accounts Payable) of 100 USD. Rate goes up -> Loss
        let gainLoss = try calculator.calculateGainLoss(
            foreignAmount: 100,
            transactionRate: txRate,
            settlementRate: settleRate,
            isAsset: false
        )
        
        XCTAssertEqual(gainLoss, -10000.0) // -(1300 - 1200) * 100
    }
    
    func testFXGainLossInvalidPair() {
        let calculator = FXGainLossCalculator()
        
        let txRate = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1200.0, date: Date())
        let settleRate = ExchangeRate(baseCurrency: .EUR, targetCurrency: .KRW, rate: 1400.0, date: Date())
        
        XCTAssertThrowsError(try calculator.calculateGainLoss(foreignAmount: 100, transactionRate: txRate, settlementRate: settleRate)) { error in
            XCTAssertEqual(error as? FXError, FXError.invalidCurrencyPair)
        }
    }

    func testFXGainLossStructuredRealizedAndUnrealized() throws {
        let calculator = FXGainLossCalculator()
        let rate1 = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, dateKey: "2026-09-01")
        let rate2 = ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1350.0, dateKey: "2026-09-10")

        let realized = try calculator.calculateRealized(foreignAmount: 200, transactionRate: rate1, settlementRate: rate2, isAsset: true)
        XCTAssertEqual(realized.gainLossAmount, 10000)
        XCTAssertEqual(realized.kind, .realizedGain)
        XCTAssertTrue(realized.isGain)
        XCTAssertFalse(realized.isLoss)

        let unrealized = try calculator.calculateUnrealized(foreignAmount: 200, bookRate: rate2, evaluationRate: rate1, isAsset: true)
        XCTAssertEqual(unrealized.gainLossAmount, -10000)
        XCTAssertEqual(unrealized.kind, .unrealizedLoss)
        XCTAssertTrue(unrealized.isLoss)
    }

    // MARK: - ExchangeRateTable Tests
    func testExchangeRateTableLookupsAndFallbacks() throws {
        var table = ExchangeRateTable()
        table.addRate(ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, dateKey: "2026-09-01"))
        table.addRate(ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1320.0, dateKey: "2026-09-04")) // Friday
        // Weekend 2026-09-05, 2026-09-06 has no rate

        XCTAssertEqual(table.count, 2)

        // Exact match
        let rateSep1 = table.rate(on: "2026-09-01", base: .USD, target: .KRW)
        XCTAssertEqual(rateSep1?.rate, 1300.0)

        // Weekend fallback to Friday rate
        let rateSep5 = table.rate(on: "2026-09-05", base: .USD, target: .KRW, fallbackToPreceding: true)
        XCTAssertEqual(rateSep5?.rate, 1320.0)
        XCTAssertEqual(rateSep5?.dateKey, "2026-09-04")

        // Without fallback should return nil
        let rateSep5NoFallback = table.rate(on: "2026-09-05", base: .USD, target: .KRW, fallbackToPreceding: false)
        XCTAssertNil(rateSep5NoFallback)

        // Convert via table
        let krw = try table.convert(amount: 50, from: .USD, to: .KRW, on: "2026-09-05")
        XCTAssertEqual(krw, 66000.0) // 50 * 1320

        let usd = try table.convert(amount: 66000, from: .KRW, to: .USD, on: "2026-09-05")
        XCTAssertEqual(usd, 50.0)
    }

    // MARK: - PayPalFXSettlement Tests
    func testPayPalFXRecognitionAndSettlementGain() throws {
        var rateTable = ExchangeRateTable()
        rateTable.addRate(ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, dateKey: "2026-09-01"))
        rateTable.addRate(ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1350.0, dateKey: "2026-09-10"))

        let tx = PayPalTransaction(id: "PAYPAL-001", transactionDateKey: "2026-09-01", grossUSD: 100, feeUSD: 4)
        XCTAssertEqual(tx.netUSD, 96)

        let calculator = PayPalFXCalculator()
        let entry = try calculator.recognizeTransaction(transaction: tx, rateTable: rateTable)

        XCTAssertEqual(entry.grossKRW, 130000)
        XCTAssertEqual(entry.feeKRW, 5200)
        XCTAssertEqual(entry.netReceivableKRW, 124800) // 96 * 1300

        // Settlement on 2026-09-10 withdrawing full 96 USD at actual KRW deposit
        let settlement = PayPalSettlementEvent(
            settlementId: "SETTLE-001",
            settlementDateKey: "2026-09-10",
            settledUSD: 96,
            actualKRWReceived: 129600 // 96 * 1350
        )

        let result = try calculator.calculateSettlement(
            entry: entry,
            originalNetUSD: tx.netUSD,
            settlement: settlement,
            rateTable: rateTable
        )

        XCTAssertEqual(result.initialBookValueKRW, 124800)
        XCTAssertEqual(result.settledValueKRW, 129600)
        XCTAssertEqual(result.realizedGainLossKRW, 4800)
        XCTAssertEqual(result.kind, .realizedGain)
        XCTAssertTrue(result.isGain)
    }

    // MARK: - ZeroRatedExportFX Tests
    func testZeroRatedExportPreSupplyExchange() throws {
        var rateTable = ExchangeRateTable()
        rateTable.addRate(ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, dateKey: "2026-09-15"))

        // Exchanged before shipping date (2026-09-10 exchange < 2026-09-15 shipping)
        let exportCase = ZeroRatedExportCase(
            exportId: "EXP-2026-001",
            foreignAmount: 1000,
            currency: .USD,
            supplyDateKey: "2026-09-15",
            exchangeDateKey: "2026-09-10",
            actualExchangedKRW: 1285000
        )

        let calc = ZeroRatedExportCalculator()
        let result = try calc.calculateTaxBase(exportCase: exportCase, rateTable: rateTable)

        XCTAssertEqual(result.ruleApplied, .preSupplyExchangedToKRW)
        XCTAssertEqual(result.taxableSupplyValueKRW, 1285000)
        XCTAssertNil(result.appliedRate)
    }

    func testZeroRatedExportPostSupplyExchangeOrForeignCurrencyHeld() throws {
        var rateTable = ExchangeRateTable()
        rateTable.addRate(ExchangeRate(baseCurrency: .USD, targetCurrency: .KRW, rate: 1300.0, dateKey: "2026-09-15"))

        // Exchanged after shipping date (2026-09-20 exchange > 2026-09-15 shipping) -> Use shipping date benchmark rate
        let exportCase = ZeroRatedExportCase(
            exportId: "EXP-2026-002",
            foreignAmount: 1000,
            currency: .USD,
            supplyDateKey: "2026-09-15",
            exchangeDateKey: "2026-09-20",
            actualExchangedKRW: 1340000
        )

        let calc = ZeroRatedExportCalculator()
        let result = try calc.calculateTaxBase(exportCase: exportCase, rateTable: rateTable)

        XCTAssertEqual(result.ruleApplied, .supplyDateBenchmarkRate)
        XCTAssertEqual(result.taxableSupplyValueKRW, 1300000) // 1000 * 1300
        XCTAssertEqual(result.appliedRate, 1300.0)
    }
}
