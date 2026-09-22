import XCTest
@testable import MoneyLedgerCLIKit
@testable import MoneyLedgerKit

final class LedgerCLITests: XCTestCase {
    private var tempDir: URL?
    private var context: LedgerContext?

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDir = dir
        context = LedgerContext(
            scope: .business,
            databaseURL: dir.appendingPathComponent("ledger.sqlite")
        )
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    private func requireTempDir() throws -> URL {
        try XCTUnwrap(tempDir)
    }

    @discardableResult
    private func run(_ arguments: [String]) async -> (code: Int32, output: CLIOutput) {
        let output = CLIOutput(passthrough: false)
        guard let ctx = context else {
            XCTFail("context is nil")
            return (code: 1, output: output)
        }
        let code = await LedgerCLI.run(
            context: ctx, arguments: arguments, output: output, environment: [:]
        )
        return (code, output)
    }

    private func resultObject(_ output: CLIOutput) throws -> [String: Any] {
        let joined = output.standardOut.joined(separator: "\n")
        let object = try JSONSerialization.jsonObject(with: Data(joined.utf8)) as? [String: Any]
        let unwrapped = try XCTUnwrap(object)
        XCTAssertEqual(unwrapped["ok"] as? Bool, true, "envelope not ok: \(joined)")
        return try XCTUnwrap(unwrapped["result"] as? [String: Any])
    }

    private func transactionObject(_ output: CLIOutput) throws -> [String: Any] {
        try XCTUnwrap(try resultObject(output)["transaction"] as? [String: Any])
    }

    private func seedAccountAndBusiness() async {
        _ = await run(["account", "add", "--name", "주거래", "--bank", "신한"])
        _ = await run(["biz", "add", "--name", "달숲"])
    }

    func testUnknownCommandExits64() async {
        let (code, _) = await run(["definitely-not-a-command"])
        XCTAssertEqual(code, 64)
    }

    func testUsageErrorJSONEnvelope() async throws {
        let (code, output) = await run(["account", "add", "--json"])  // --name/--bank 없음
        XCTAssertEqual(code, 64)
        let joined = output.standardOut.joined()
        let object = try JSONSerialization.jsonObject(with: Data(joined.utf8)) as? [String: Any]
        XCTAssertEqual(object?["ok"] as? Bool, false)
    }

    func testAccountAddListRoundTrip() async throws {
        let (addCode, addOutput) = await run([
            "account", "add", "--name", "주거래", "--bank", "신한", "--last4", "1234", "--json",
        ])
        XCTAssertEqual(addCode, 0)
        let added = try resultObject(addOutput)
        let account = try XCTUnwrap(added["account"] as? [String: Any])
        XCTAssertEqual(account["name"] as? String, "주거래")

        let (listCode, listOutput) = await run(["account", "list", "--json"])
        XCTAssertEqual(listCode, 0)
        let listed = try resultObject(listOutput)
        let accounts = try XCTUnwrap(listed["accounts"] as? [[String: Any]])
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0]["bank"] as? String, "신한")
    }

    func testTxAddDuplicateIdempotency() async throws {
        _ = await run(["account", "add", "--name", "주거래", "--bank", "신한"])
        let arguments = [
            "tx", "add", "--date", "2026-08-04", "--amount", "-15000",
            "--account", "주거래", "--desc", "커피", "--json",
        ]
        let (firstCode, firstOutput) = await run(arguments)
        XCTAssertEqual(firstCode, 0)
        let first = try resultObject(firstOutput)
        let firstTx = try XCTUnwrap(first["transaction"] as? [String: Any])
        XCTAssertEqual(firstTx["duplicate"] as? Bool, false)

        let (secondCode, secondOutput) = await run(arguments)
        XCTAssertEqual(secondCode, 0, "중복은 실패가 아니라 멱등 성공")
        let second = try resultObject(secondOutput)
        let secondTx = try XCTUnwrap(second["transaction"] as? [String: Any])
        XCTAssertEqual(secondTx["duplicate"] as? Bool, true)
        XCTAssertEqual(secondTx["id"] as? String, firstTx["id"] as? String)

        // --allow-duplicate 는 새 행을 만든다
        let (thirdCode, thirdOutput) = await run(arguments + ["--allow-duplicate"])
        XCTAssertEqual(thirdCode, 0)
        let third = try resultObject(thirdOutput)
        let thirdTx = try XCTUnwrap(third["transaction"] as? [String: Any])
        XCTAssertEqual(thirdTx["duplicate"] as? Bool, false)
    }

    func testSubAndReportFlow() async throws {
        _ = await run([
            "sub", "add", "--name", "Claude", "--amount", "20", "--currency", "USD",
            "--period", "monthly",
        ])
        _ = await run([
            "sub", "add", "--name", "도메인", "--amount", "24000", "--period", "yearly",
        ])
        let (code, output) = await run(["report", "subs", "--json"])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        let totals = try XCTUnwrap(result["monthlyTotals"] as? [[String: Any]])
        XCTAssertEqual(totals.count, 2)
        let krw = try XCTUnwrap(totals.first { $0["currency"] as? String == "KRW" })
        XCTAssertEqual(krw["monthlyEquivalent"] as? Double ?? 0, 2000.0, accuracy: 0.01)
    }

    func testReportMonthly() async throws {
        _ = await run(["account", "add", "--name", "주거래", "--bank", "신한"])
        _ = await run([
            "tx", "add", "--date", "2026-08-01", "--amount", "3000000",
            "--account", "주거래", "--desc", "매출",
        ])
        _ = await run([
            "tx", "add", "--date", "2026-08-02", "--amount", "-500000",
            "--account", "주거래", "--desc", "임대료", "--category", "고정비",
        ])
        let (code, output) = await run(["report", "monthly", "--month", "2026-08", "--json"])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        let flows = try XCTUnwrap(result["flows"] as? [[String: Any]])
        XCTAssertEqual(flows.count, 1)
        let inflow = try XCTUnwrap(flows[0]["inflow"] as? [String: Any])
        XCTAssertEqual(inflow["minorUnits"] as? Int64, 3_000_000)
    }

    func testImportCSVEndToEnd() async throws {
        _ = await run(["account", "add", "--name", "주거래", "--bank", "신한"])
        let csvURL = try requireTempDir().appendingPathComponent("bank.csv")
        try """
        거래일자,적요,출금액,입금액
        2026-08-01,스타벅스,5000,
        2026-08-02,급여,,3000000
        """.write(to: csvURL, atomically: true, encoding: .utf8)

        let (dryCode, dryOutput) = await run([
            "import", "csv", csvURL.path, "--account", "주거래",
            "--map", "date=거래일자,desc=적요,out=출금액,in=입금액", "--dry-run", "--json",
        ])
        XCTAssertEqual(dryCode, 0)
        let dry = try resultObject(dryOutput)
        XCTAssertEqual(dry["inserted"] as? Int, 2)

        let (code, output) = await run([
            "import", "csv", csvURL.path, "--account", "주거래",
            "--map", "date=거래일자,desc=적요,out=출금액,in=입금액", "--json",
        ])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        XCTAssertEqual(result["inserted"] as? Int, 2)
        let batchID = try XCTUnwrap(result["batchID"] as? String)

        let (undoCode, undoOutput) = await run(["import", "undo", batchID, "--json"])
        XCTAssertEqual(undoCode, 0)
        let undo = try resultObject(undoOutput)
        XCTAssertEqual(undo["removed"] as? Int, 2)
    }

    func testCapabilitiesListsAllTopCommands() async throws {
        let (code, output) = await run(["capabilities"])
        XCTAssertEqual(code, 0)
        let joined = output.standardOut.joined()
        let object = try JSONSerialization.jsonObject(with: Data(joined.utf8)) as? [String: Any]
        let result = try XCTUnwrap(object?["result"] as? [String: Any])
        XCTAssertEqual(result["name"] as? String, "business-ledger")
        let commands = try XCTUnwrap(result["commands"] as? [[String: Any]])
        let names = commands.compactMap { $0["name"] as? String }.joined(separator: " ")
        for top in ["account", "card", "sub", "tx", "import", "report", "vault", "capabilities"] {
            XCTAssertTrue(names.contains(top), "capabilities 에 \(top) 누락")
        }
    }

    func testDataRootOverride() async throws {
        let altRoot = try requireTempDir().appendingPathComponent("alt", isDirectory: true).path
        _ = await run([
            "account", "add", "--name", "다른원장", "--bank", "국민", "--data-root", altRoot,
        ])
        // 기본 원장에는 없다
        let (_, defaultOutput) = await run(["account", "list", "--json"])
        let defaults = try resultObject(defaultOutput)
        XCTAssertEqual((defaults["accounts"] as? [[String: Any]])?.count, 0)
        // alt 원장에는 있다
        let (_, altOutput) = await run(["account", "list", "--data-root", altRoot, "--json"])
        let alt = try resultObject(altOutput)
        XCTAssertEqual((alt["accounts"] as? [[String: Any]])?.count, 1)
    }

    func testTxAddWithBusinessAndListFilter() async throws {
        await seedAccountAndBusiness()
        let (addCode, addOutput) = await run([
            "tx", "add", "--date", "2026-08-04", "--amount", "-15000",
            "--account", "주거래", "--desc", "커피", "--business", "달숲", "--json",
        ])
        XCTAssertEqual(addCode, 0)
        let businessID = try XCTUnwrap(try transactionObject(addOutput)["businessID"] as? String)
        _ = await run([
            "tx", "add", "--date", "2026-08-05", "--amount", "-3000",
            "--account", "주거래", "--desc", "귀속 없음",
        ])

        // 필터는 id 로도 상호로도 된다 — sub add 와 같은 해석.
        let (byIDCode, byIDOutput) = await run(["tx", "list", "--business", businessID, "--json"])
        XCTAssertEqual(byIDCode, 0)
        XCTAssertEqual(try resultObject(byIDOutput)["count"] as? Int, 1)
        let (byNameCode, byNameOutput) = await run(["tx", "list", "--business", "달숲", "--json"])
        XCTAssertEqual(byNameCode, 0)
        XCTAssertEqual(try resultObject(byNameOutput)["count"] as? Int, 1)
        let (allCode, allOutput) = await run(["tx", "list", "--json"])
        XCTAssertEqual(allCode, 0)
        XCTAssertEqual(try resultObject(allOutput)["count"] as? Int, 2)
    }

    func testTxSetBusinessAndNone() async throws {
        await seedAccountAndBusiness()
        let (_, addOutput) = await run([
            "tx", "add", "--date", "2026-08-04", "--amount", "-15000",
            "--account", "주거래", "--desc", "커피", "--json",
        ])
        let txID = try XCTUnwrap(try transactionObject(addOutput)["id"] as? String)

        let (setCode, setOutput) = await run(["tx", "set-business", txID, "달숲", "--json"])
        XCTAssertEqual(setCode, 0)
        XCTAssertNotNil(try transactionObject(setOutput)["businessID"])
        let (showCode, showOutput) = await run(["tx", "show", txID, "--json"])
        XCTAssertEqual(showCode, 0)
        XCTAssertNotNil(try transactionObject(showOutput)["businessID"])

        let (noneCode, noneOutput) = await run(["tx", "set-business", txID, "none", "--json"])
        XCTAssertEqual(noneCode, 0)
        XCTAssertNil(try transactionObject(noneOutput)["businessID"])

        // 없는 사업체는 exit 1 — 조용히 무시하면 귀속이 새는 자리다.
        let (missingCode, _) = await run(["tx", "set-business", txID, "없는상호"])
        XCTAssertEqual(missingCode, 1)
    }

    func testImportCSVTagsWholeBatchWithBusiness() async throws {
        await seedAccountAndBusiness()
        let csvURL = try requireTempDir().appendingPathComponent("bank.csv")
        try """
        거래일자,적요,출금액,입금액
        2026-08-01,스타벅스,5000,
        2026-08-02,급여,,3000000
        """.write(to: csvURL, atomically: true, encoding: .utf8)
        let (code, output) = await run([
            "import", "csv", csvURL.path, "--account", "주거래", "--business", "달숲",
            "--map", "date=거래일자,desc=적요,out=출금액,in=입금액", "--json",
        ])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        XCTAssertEqual(result["inserted"] as? Int, 2)
        let businessID = try XCTUnwrap(result["businessID"] as? String)
        let (_, listOutput) = await run(["tx", "list", "--business", businessID, "--json"])
        XCTAssertEqual(try resultObject(listOutput)["count"] as? Int, 2)
    }

    func testReportMonthlyBusinessFilter() async throws {
        await seedAccountAndBusiness()
        _ = await run([
            "tx", "add", "--date", "2026-08-01", "--amount", "3000000",
            "--account", "주거래", "--desc", "달숲 매출", "--business", "달숲",
        ])
        _ = await run([
            "tx", "add", "--date", "2026-08-02", "--amount", "500000",
            "--account", "주거래", "--desc", "다른 입금",
        ])
        let (code, output) = await run([
            "report", "monthly", "--month", "2026-08", "--business", "달숲", "--json",
        ])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        XCTAssertNotNil(result["businessID"])
        let flows = try XCTUnwrap(result["flows"] as? [[String: Any]])
        XCTAssertEqual(flows.count, 1)
        let inflow = try XCTUnwrap(flows[0]["inflow"] as? [String: Any])
        XCTAssertEqual(inflow["minorUnits"] as? Int64, 3_000_000)
    }

    func testCapabilitiesListsSetBusiness() async throws {
        let (_, output) = await run(["capabilities"])
        XCTAssertTrue(output.standardOut.joined().contains("set-business"))
    }

    func testAccountAddWithTypeAndInitialBalance() async throws {
        // 1. cash 유형: 은행 없이도 자동 등록 & 초기잔액
        let (cashCode, cashOutput) = await run([
            "account", "add", "--name", "지갑", "--type", "cash", "--initial-balance", "50000", "--json"
        ])
        XCTAssertEqual(cashCode, 0)
        let cashAcc = try XCTUnwrap(try resultObject(cashOutput)["account"] as? [String: Any])
        XCTAssertEqual(cashAcc["name"] as? String, "지갑")
        XCTAssertEqual(cashAcc["bank"] as? String, "현금")
        XCTAssertEqual(cashAcc["type"] as? String, "cash")
        let cashInit = try XCTUnwrap(cashAcc["initialBalance"] as? [String: Any])
        XCTAssertEqual(cashInit["minorUnits"] as? Int64, 50000)

        // 2. realEstate 유형: 은행 없이 등록
        let (reCode, reOutput) = await run([
            "account", "add", "--name", "아파트", "--type", "realEstate", "--initial-balance", "500000000", "--json"
        ])
        XCTAssertEqual(reCode, 0)
        let reAcc = try XCTUnwrap(try resultObject(reOutput)["account"] as? [String: Any])
        XCTAssertEqual(reAcc["bank"] as? String, "부동산")
        XCTAssertEqual(reAcc["type"] as? String, "realEstate")

        // 3. loan 유형: 은행 필수
        let (loanNoBankCode, _) = await run([
            "account", "add", "--name", "대출", "--type", "loan", "--json"
        ])
        XCTAssertEqual(loanNoBankCode, 64)

        let (loanCode, loanOutput) = await run([
            "account", "add", "--name", "신용대출", "--type", "loan", "--bank", "우리은행", "--initial-balance", "20000000", "--json"
        ])
        XCTAssertEqual(loanCode, 0)
        let loanAcc = try XCTUnwrap(try resultObject(loanOutput)["account"] as? [String: Any])
        XCTAssertEqual(loanAcc["type"] as? String, "loan")
        XCTAssertEqual(loanAcc["bank"] as? String, "우리은행")

        // 4. account update 로 type 및 initial-balance 수정
        let (upCode, upOutput) = await run([
            "account", "update", "지갑", "--initial-balance", "70000", "--json"
        ])
        XCTAssertEqual(upCode, 0)
        let upAcc = try XCTUnwrap(try resultObject(upOutput)["account"] as? [String: Any])
        let upInit = try XCTUnwrap(upAcc["initialBalance"] as? [String: Any])
        XCTAssertEqual(upInit["minorUnits"] as? Int64, 70000)
    }

    func testTxAddWithKind() async throws {
        _ = await run(["account", "add", "--name", "통장", "--bank", "신한"])
        // --kind expense 지정 시 양수를 넘겨도 음수로 자동 보정
        let (code, output) = await run([
            "tx", "add", "--date", "2026-09-01", "--amount", "15000", "--account", "통장",
            "--desc", "점심", "--kind", "expense", "--json"
        ])
        XCTAssertEqual(code, 0)
        let tx = try transactionObject(output)
        let amtObj = try XCTUnwrap(tx["amount"] as? [String: Any])
        XCTAssertEqual(amtObj["minorUnits"] as? Int64, -15000)
        XCTAssertEqual(tx["kind"] as? String, "expense")
    }

    func testTxTransferBetweenAccounts() async throws {
        _ = await run(["account", "add", "--name", "보통예금", "--bank", "신한"])
        _ = await run(["account", "add", "--name", "적금", "--bank", "국민"])

        let (code, output) = await run([
            "tx", "transfer", "--from", "보통예금", "--to", "적금", "--amount", "100000",
            "--date", "2026-09-02", "--desc", "적금자동이체", "--json"
        ])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        let transferObj = try XCTUnwrap(result["transfer"] as? [String: Any])
        let withdrawal = try XCTUnwrap(transferObj["withdrawal"] as? [String: Any])
        let deposit = try XCTUnwrap(transferObj["deposit"] as? [String: Any])

        let wAmt = try XCTUnwrap(withdrawal["amount"] as? [String: Any])
        let dAmt = try XCTUnwrap(deposit["amount"] as? [String: Any])
        XCTAssertEqual(wAmt["minorUnits"] as? Int64, -100000)
        XCTAssertEqual(dAmt["minorUnits"] as? Int64, 100000)
        XCTAssertEqual(withdrawal["kind"] as? String, "transfer")
        XCTAssertEqual(deposit["kind"] as? String, "transfer")

        // 동일 계좌 이체는 에러
        let (sameCode, _) = await run([
            "tx", "transfer", "--from", "보통예금", "--to", "보통예금", "--amount", "10000"
        ])
        XCTAssertEqual(sameCode, 1)
    }

    func testTxSettleCard() async throws {
        _ = await run(["account", "add", "--name", "주거래", "--bank", "신한"])
        _ = await run(["card", "add", "--name", "현대카드", "--issuer", "현대"])

        let (code, output) = await run([
            "tx", "settle-card", "--from", "주거래", "--card", "현대카드", "--amount", "250000",
            "--date", "2026-09-03", "--desc", "9월 결제대금", "--json"
        ])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        let settlementObj = try XCTUnwrap(result["settlement"] as? [String: Any])
        let withdrawal = try XCTUnwrap(settlementObj["withdrawal"] as? [String: Any])
        let settlement = try XCTUnwrap(settlementObj["settlement"] as? [String: Any])

        let wAmt = try XCTUnwrap(withdrawal["amount"] as? [String: Any])
        let sAmt = try XCTUnwrap(settlement["amount"] as? [String: Any])
        XCTAssertEqual(wAmt["minorUnits"] as? Int64, -250000)
        XCTAssertEqual(sAmt["minorUnits"] as? Int64, 250000)
        XCTAssertEqual(withdrawal["kind"] as? String, "settlement")
        XCTAssertEqual(settlement["kind"] as? String, "settlement")
    }

    func testTxUpdate() async throws {
        _ = await run(["account", "add", "--name", "주거래", "--bank", "신한"])
        let (_, addOutput) = await run([
            "tx", "add", "--date", "2026-09-01", "--amount", "-10000",
            "--account", "주거래", "--desc", "기존적요", "--json"
        ])
        let txID = try XCTUnwrap(try transactionObject(addOutput)["id"] as? String)

        let (upCode, upOutput) = await run([
            "tx", "update", txID, "--amount", "-12000", "--desc", "수정된적요",
            "--category", "식비", "--memo", "맛있었음", "--json"
        ])
        XCTAssertEqual(upCode, 0)
        let updated = try transactionObject(upOutput)
        let amtObj = try XCTUnwrap(updated["amount"] as? [String: Any])
        XCTAssertEqual(amtObj["minorUnits"] as? Int64, -12000)
        XCTAssertEqual(updated["description"] as? String, "수정된적요")
        XCTAssertEqual(updated["category"] as? String, "식비")
        XCTAssertEqual(updated["memo"] as? String, "맛있었음")
    }

    func testNetWorthSummary() async throws {
        // 1. 자산 계좌 생성 (기초잔액)
        _ = await run(["account", "add", "--name", "예금", "--type", "savings", "--bank", "신한", "--initial-balance", "30000000"])
        _ = await run(["account", "add", "--name", "부동산", "--type", "realEstate", "--initial-balance", "700000000"])
        _ = await run(["account", "add", "--name", "주식", "--type", "investment", "--initial-balance", "100000000"])

        // 2. 부채 계좌 생성 (대출)
        _ = await run(["account", "add", "--name", "주담대", "--type", "loan", "--bank", "국민", "--initial-balance", "200000000"])

        // 3. 순자산 커맨드 실행
        let (code, output) = await run(["net-worth", "--json"])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        let reports = try XCTUnwrap(result["reports"] as? [[String: Any]])
        XCTAssertEqual(reports.count, 1)

        let krwReport = reports[0]
        let totalAssets = try XCTUnwrap(krwReport["totalAssets"] as? [String: Any])
        let totalLiabilities = try XCTUnwrap(krwReport["totalLiabilities"] as? [String: Any])
        let netWorth = try XCTUnwrap(krwReport["netWorth"] as? [String: Any])

        XCTAssertEqual(totalAssets["minorUnits"] as? Int64, 830000000)
        XCTAssertEqual(totalLiabilities["minorUnits"] as? Int64, 200000000)
        XCTAssertEqual(netWorth["minorUnits"] as? Int64, 630000000)

        // 텍스트 출력도 확인
        let (textCode, textOutput) = await run(["net-worth"])
        XCTAssertEqual(textCode, 0)
        let textJoined = textOutput.standardOut.joined(separator: "\n")
        XCTAssertTrue(textJoined.contains("총자산"))
        XCTAssertTrue(textJoined.contains("총부채"))
        XCTAssertTrue(textJoined.contains("순자산"))
        XCTAssertTrue(textJoined.contains("부동산"))
    }

    func testBudgetCommands() async throws {
        // 1. 예산 설정
        let (setCode, setOutput) = await run(["budget", "set", "--category", "식비", "--amount", "500000", "--json"])
        XCTAssertEqual(setCode, 0)
        let setResult = try resultObject(setOutput)
        XCTAssertEqual(setResult["category"] as? String, "식비")

        // 2. 예산 목록 조회
        let (listCode, listOutput) = await run(["budget", "list", "--json"])
        XCTAssertEqual(listCode, 0)
        let listResult = try resultObject(listOutput)
        let budgets = try XCTUnwrap(listResult["budgets"] as? [[String: Any]])
        XCTAssertEqual(budgets.count, 1)
        XCTAssertEqual(budgets[0]["category"] as? String, "식비")

        // 3. 텍스트 목록 조회
        let (textCode, textOutput) = await run(["budget", "list"])
        XCTAssertEqual(textCode, 0)
        XCTAssertTrue(textOutput.standardOut.joined().contains("식비"))
    }

    func testExportCommands() async throws {
        await seedAccountAndBusiness()
        _ = await run([
            "tx", "add", "--date", "2026-09-01", "--amount", "-15000",
            "--account", "주거래", "--desc", "스타벅스", "--category", "식비"
        ])

        let tempFile = try requireTempDir().appendingPathComponent("test-export.csv")
        let (code, output) = await run(["export", "--format", "csv", "--output", tempFile.path, "--json"])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        XCTAssertEqual(result["format"] as? String, "csv")
        XCTAssertEqual(result["count"] as? Int, 1)

        let fileData = try Data(contentsOf: tempFile)
        XCTAssertEqual(Array(fileData.prefix(3)), [0xEF, 0xBB, 0xBF], "Must contain UTF-8 BOM")
        let content = String(data: fileData.dropFirst(3), encoding: .utf8) ?? ""
        XCTAssertTrue(content.contains("일자,유형,계좌/카드,가맹점/적요,카테고리,금액,통화,메모,생성일시"))
        XCTAssertTrue(content.contains("스타벅스"))
        XCTAssertTrue(content.contains("식비"))
    }
}

