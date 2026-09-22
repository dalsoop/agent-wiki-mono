import XCTest
@testable import MoneyLedgerCLIKit
@testable import MoneyLedgerKit

final class BusinessCLITests: XCTestCase {
    private var tempDir: URL!
    private var context: LedgerContext!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ledger-biz-cli-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        context = LedgerContext(
            scope: .business,
            databaseURL: tempDir.appendingPathComponent("ledger.sqlite")
        )
    }

    override func tearDownWithError() throws {
        if let tempDir { try? FileManager.default.removeItem(at: tempDir) }
    }

    @discardableResult
    private func run(_ arguments: [String]) async -> (code: Int32, output: CLIOutput) {
        let output = CLIOutput(passthrough: false)
        let code = await LedgerCLI.run(
            context: context, arguments: arguments, output: output, environment: [:]
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

    func testBizAddValidatesRegistrationNumber() async throws {
        // 체크섬 틀린 번호는 거부
        let (badCode, _) = await run(["biz", "add", "--name", "달숲", "--reg-no", "123-45-67890"])
        XCTAssertEqual(badCode, 64)
        // --force 로 통과 가능
        let (forcedCode, _) = await run([
            "biz", "add", "--name", "강제등록", "--reg-no", "123-45-67890", "--force",
        ])
        XCTAssertEqual(forcedCode, 0)
        // 올바른 번호는 그대로 통과
        let (goodCode, goodOutput) = await run([
            "biz", "add", "--name", "달숲", "--reg-no", "123-45-67891", "--rep", "윤정한", "--json",
        ])
        XCTAssertEqual(goodCode, 0)
        let result = try resultObject(goodOutput)
        let business = try XCTUnwrap(result["business"] as? [String: Any])
        XCTAssertEqual(business["registrationNumber"] as? String, "1234567891")
        XCTAssertEqual(business["registrationNumberFormatted"] as? String, "123-45-67891")
    }

    func testBizAttachAndFiles() async throws {
        _ = await run(["biz", "add", "--name", "달숲", "--reg-no", "123-45-67891"])
        let source = tempDir.appendingPathComponent("등록증.png")
        try Data([0x89, 0x50]).write(to: source)

        let (attachCode, attachOutput) = await run(["biz", "attach", "달숲", source.path, "--json"])
        XCTAssertEqual(attachCode, 0)
        let attached = try resultObject(attachOutput)
        let attachment = try XCTUnwrap(attached["attachment"] as? [String: Any])
        let storedPath = try XCTUnwrap(attachment["path"] as? String)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedPath))

        let (filesCode, filesOutput) = await run(["biz", "files", "달숲", "--json"])
        XCTAssertEqual(filesCode, 0)
        let files = try resultObject(filesOutput)
        XCTAssertEqual((files["attachments"] as? [[String: Any]])?.count, 1)

        // detach 후 파일도 사라진다
        let attachmentID = try XCTUnwrap(attachment["id"] as? String)
        let (detachCode, _) = await run(["biz", "detach", String(attachmentID.prefix(8))])
        XCTAssertEqual(detachCode, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storedPath))
    }

    func testBizRemovePurgesAttachments() async throws {
        _ = await run(["biz", "add", "--name", "달숲"])
        let source = tempDir.appendingPathComponent("doc.pdf")
        try Data("pdf".utf8).write(to: source)
        _ = await run(["biz", "attach", "달숲", source.path])

        let (code, output) = await run(["biz", "remove", "달숲", "--purge", "--json"])
        XCTAssertEqual(code, 0)
        let result = try resultObject(output)
        XCTAssertEqual(result["attachmentsRemoved"] as? Int, 1)
    }

    func testCapabilitiesIncludesBiz() async throws {
        let (_, output) = await run(["capabilities"])
        XCTAssertTrue(output.standardOut.joined().contains("biz add"))
    }
}
