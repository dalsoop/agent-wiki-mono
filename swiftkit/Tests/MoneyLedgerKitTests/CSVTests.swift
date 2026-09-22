import XCTest
import MoneyLedgerStoreKit
import MoneyLedgerModels
@testable import MoneyLedgerImportKit

final class CSVTableTests: XCTestCase {
    func testBasicParse() {
        let rows = CSVTable.parse("a,b,c\n1,2,3\n")
        XCTAssertEqual(rows, [["a", "b", "c"], ["1", "2", "3"]])
    }

    func testQuotedFields() {
        let rows = CSVTable.parse("desc,amount\n\"스타벅스, 강남점\",\"1,500\"\n\"say \"\"hi\"\"\",2\n")
        XCTAssertEqual(rows[1], ["스타벅스, 강남점", "1,500"])
        XCTAssertEqual(rows[2], ["say \"hi\"", "2"])
    }

    func testQuotedNewline() {
        let rows = CSVTable.parse("a,b\n\"줄1\n줄2\",x\n")
        XCTAssertEqual(rows[1], ["줄1\n줄2", "x"])
    }

    func testCRLFAndEmptyLines() {
        let rows = CSVTable.parse("a,b\r\n1,2\r\n\r\n3,4\r\n")
        XCTAssertEqual(rows.count, 3)
    }

    func testUTF8BOM() throws {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("날짜,금액\n2026-08-04,1500\n".utf8))
        let table = try CSVTable.read(data: data)
        XCTAssertEqual(table.encodingName, "utf8")
        XCTAssertEqual(table.rows[0], ["날짜", "금액"])
    }

    func testCP949AutoDetect() throws {
        let text = "날짜,적요,출금액\n2026-08-04,스타벅스,15000\n"
        let cfEncoding = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.EUC_KR.rawValue)
        )
        let data = text.data(using: String.Encoding(rawValue: cfEncoding))!
        let table = try CSVTable.read(data: data, encoding: .auto)
        XCTAssertEqual(table.encodingName, "cp949")
        XCTAssertEqual(table.rows[1][1], "스타벅스")
    }
}

final class CSVImportServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func makeStore() throws -> LedgerStore {
        try LedgerStore(url: tempDir.appendingPathComponent("ledger.sqlite"))
    }

    private func table(_ text: String) -> CSVTable {
        CSVTable(rows: CSVTable.parse(text), encodingName: "utf8")
    }

    func testSplitInOutImport() async throws {
        let store = try makeStore()
        let csv = table("""
        거래일자,거래시간,적요,출금액,입금액,거래후잔액
        2026-08-01,09:10:11,스타벅스,5000,,995000
        2026-08-02,12:00:00,급여,,3000000,3995000
        """)
        let mapping = try ColumnMapping.parse("date=거래일자,time=거래시간,desc=적요,out=출금액,in=입금액,balance=거래후잔액")
        let result = try await CSVImportService().run(
            store: store, table: csv, sourceFile: "test.csv",
            request: CSVImportRequest(mapping: mapping, accountID: "acct-1")
        )
        XCTAssertEqual(result.inserted, 2)
        XCTAssertEqual(result.duplicates, 0)
        XCTAssertTrue(result.errors.isEmpty)

        let listed = try await store.transactions()
        XCTAssertEqual(listed.count, 2)
        let outflow = listed.first { $0.description == "스타벅스" }
        XCTAssertEqual(outflow?.amountMinor, -5000)
        XCTAssertEqual(outflow?.balanceAfterMinor, 995_000)
        let inflow = listed.first { $0.description == "급여" }
        XCTAssertEqual(inflow?.amountMinor, 3_000_000)
    }

    func testReimportIsFullyDeduplicated() async throws {
        let store = try makeStore()
        let csv = table("""
        날짜,적요,금액
        2026-08-01,커피,-5000
        2026-08-01,커피,-5000
        2026-08-02,점심,-12000
        """)
        let mapping = try ColumnMapping.parse("date=날짜,desc=적요,amount=금액")
        let service = CSVImportService()

        let first = try await service.run(
            store: store, table: csv, sourceFile: "a.csv",
            request: CSVImportRequest(mapping: mapping, accountID: "acct-1")
        )
        // 같은 파일 안 동일 2건은 occurrence 로 둘 다 산다.
        XCTAssertEqual(first.inserted, 3)

        let second = try await service.run(
            store: store, table: csv, sourceFile: "a.csv",
            request: CSVImportRequest(mapping: mapping, accountID: "acct-1")
        )
        XCTAssertEqual(second.inserted, 0)
        XCTAssertEqual(second.duplicates, 3)
        let count = try await store.transactionCount()
        XCTAssertEqual(count, 3)
    }

    func testDryRunInsertsNothing() async throws {
        let store = try makeStore()
        let csv = table("날짜,적요,금액\n2026-08-01,커피,-5000\n")
        let mapping = try ColumnMapping.parse("date=날짜,desc=적요,amount=금액")
        let result = try await CSVImportService().run(
            store: store, table: csv, sourceFile: "a.csv",
            request: CSVImportRequest(mapping: mapping, accountID: "acct-1", dryRun: true)
        )
        XCTAssertNil(result.batchID)
        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.preview.count, 1)
        let count = try await store.transactionCount()
        XCTAssertEqual(count, 0)
        let batches = try await store.importBatches()
        XCTAssertTrue(batches.isEmpty)
    }

    func testRowErrorsReportedWithLineNumbers() async throws {
        let store = try makeStore()
        let csv = table("""
        날짜,적요,금액
        2026-08-01,커피,-5000
        не дата,이상한 행,xyz
        """)
        let mapping = try ColumnMapping.parse("date=날짜,desc=적요,amount=금액")
        let result = try await CSVImportService().run(
            store: store, table: csv, sourceFile: "a.csv",
            request: CSVImportRequest(mapping: mapping, accountID: "acct-1")
        )
        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertEqual(result.errors.first?.line, 3)
    }

    func testColumnIndexMapping() async throws {
        let store = try makeStore()
        let csv = table("컬럼1,컬럼2,컬럼3\n2026-08-01,점심,-12000\n")
        let mapping = try ColumnMapping.parse("date=1,desc=2,amount=3")
        let result = try await CSVImportService().run(
            store: store, table: csv, sourceFile: "b.csv",
            request: CSVImportRequest(mapping: mapping, accountID: "acct-1")
        )
        XCTAssertEqual(result.inserted, 1)
    }

    func testSkipRows() async throws {
        let store = try makeStore()
        let csv = table("""
        신한은행 거래내역
        조회기간: 2026-08-01 ~ 2026-08-31
        날짜,적요,금액
        2026-08-01,커피,-5000
        """)
        let mapping = try ColumnMapping.parse("date=날짜,desc=적요,amount=금액")
        let result = try await CSVImportService().run(
            store: store, table: csv, sourceFile: "c.csv",
            request: CSVImportRequest(mapping: mapping, accountID: "acct-1", skipRows: 2)
        )
        XCTAssertEqual(result.inserted, 1)
    }

    func testUndoBatch() async throws {
        let store = try makeStore()
        let csv = table("날짜,적요,금액\n2026-08-01,커피,-5000\n")
        let mapping = try ColumnMapping.parse("date=날짜,desc=적요,amount=금액")
        let result = try await CSVImportService().run(
            store: store, table: csv, sourceFile: "a.csv",
            request: CSVImportRequest(mapping: mapping, accountID: "acct-1")
        )
        let removed = try await store.undoImportBatch(id: result.batchID!)
        XCTAssertEqual(removed, 1)
        let count = try await store.transactionCount()
        XCTAssertEqual(count, 0)
    }

    func testMappingValidation() {
        XCTAssertThrowsError(try ColumnMapping.parse("desc=적요"))          // date 없음
        XCTAssertThrowsError(try ColumnMapping.parse("date=날짜"))          // 금액 없음
        XCTAssertThrowsError(try ColumnMapping.parse("date=날짜,amount=1,in=2"))  // 충돌
        XCTAssertThrowsError(try ColumnMapping.parse("weird=1,date=날짜,amount=1"))
    }

    func testInstrumentExclusivity() async throws {
        let store = try makeStore()
        let csv = table("날짜,금액\n2026-08-01,-5000\n")
        let mapping = try ColumnMapping.parse("date=날짜,amount=금액")
        do {
            _ = try await CSVImportService().run(
                store: store, table: csv, sourceFile: "a.csv",
                request: CSVImportRequest(mapping: mapping, accountID: "acct-1", cardID: "card-1")
            )
            XCTFail("expected instrumentRequired")
        } catch let error as CSVImportError {
            XCTAssertEqual(error, .instrumentRequired)
        }
    }
}
