import CommandKit
import MoneyLedgerStoreKit
import MoneyLedgerModels
import XCTest
@testable import MoneyLedgerVaultKit

final class VaultDocsGatewayTests: XCTestCase {
    /// vaultwarden-client 호출 목 — 명령 프리픽스 매칭 + 호출 기록.
    private final class MockRunner: CommandRunning, @unchecked Sendable {
        let responses: [String: String]
        var calls: [String] = []
        private let lock = NSLock()

        init(responses: [String: String]) { self.responses = responses }

        func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
            let key = arguments.joined(separator: " ")
            lock.withLock { calls.append(key) }
            if let stdout = responses.first(where: { key.hasPrefix($0.key) })?.value {
                return CommandResult(stdout: stdout, stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: #"{"ok":false,"error":{"message":"not found"}}"#, stderr: "", exitCode: 1)
        }
    }

    private func gateway(_ runner: MockRunner) -> VaultDocsGateway {
        VaultDocsGateway(runner: runner, cliPath: "/bin/echo")
    }

    func testStatusMapping() async {
        let cases: [(String, VaultDocsGateway.Status)] = [
            (#"{"ok":true,"result":{"status":"ready","ready":true}}"#, .ready),
            (#"{"ok":true,"result":{"status":"locked","ready":false}}"#, .locked),
            (#"{"ok":true,"result":{"status":"notLoggedIn","ready":false}}"#, .notLoggedIn),
        ]
        for (payload, expected) in cases {
            let status = await gateway(MockRunner(responses: ["status": payload])).status()
            XCTAssertEqual(status, expected)
        }
    }

    func testStatusUnavailableWhenCLIMissing() async {
        let status = await gateway(MockRunner(responses: [:])).status()
        XCTAssertEqual(status, .unavailable)
    }

    func testUploadPassesBoxAndPath() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("등록증-\(UUID()).pdf")
        try Data("pdf".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let runner = MockRunner(responses: ["docs upload": #"{"ok":true,"result":{"uploaded":"등록증.pdf"}}"#])
        try await gateway(runner).upload(fileURL: file, box: "서류: 달숲 [business-ledger]")
        let call = try XCTUnwrap(runner.calls.first)
        XCTAssertTrue(call.hasPrefix("docs upload 서류: 달숲 [business-ledger] \(file.path)"), call)
        XCTAssertTrue(call.hasSuffix("--json"))
    }

    func testUploadRejectsMissingFile() async {
        let gateway = gateway(MockRunner(responses: [:]))
        do {
            try await gateway.upload(fileURL: URL(fileURLWithPath: "/tmp/없음-\(UUID()).pdf"), box: "box")
            XCTFail("expected fileMissing")
        } catch let error as VaultDocsError {
            guard case .fileMissing = error else { return XCTFail("wrong error: \(error)") }
        } catch { XCTFail("wrong error type") }
    }

    func testListParsesAttachments() async throws {
        let payload = #"""
        {"ok":true,"result":{"box":"b","attachments":[{"id":"a1","fileName":"사업자등록증.pdf","sizeName":"1.2 MB"},{"id":"a2","fileName":"통신판매업신고증.pdf","sizeName":"800 KB"}]}}
        """#
        let files = try await gateway(MockRunner(responses: ["docs list": payload])).list(box: "b")
        XCTAssertEqual(files.map(\.fileName), ["사업자등록증.pdf", "통신판매업신고증.pdf"])
        XCTAssertEqual(files.first?.sizeName, "1.2 MB")
    }

    func testFailureSurfacesServerMessage() async {
        let runner = MockRunner(responses: [
            "docs list": #"{"ok":false,"error":{"message":"금고에 로그인돼 있지 않습니다"}}"#,
        ])
        do {
            _ = try await gateway(runner).list(box: "b")
            XCTFail("expected failure")
        } catch let error as VaultDocsError {
            XCTAssertTrue(error.description.contains("로그인"), error.description)
        } catch { XCTFail("wrong error type") }
    }

    func testNoteGetReturnsValue() async throws {
        let runner = MockRunner(responses: [
            "note get": #"{"ok":true,"result":{"name":"ledger/business/card/x","value":"1234-5678"}}"#,
        ])
        let value = try await gateway(runner).note(name: "ledger/business/card/x")
        XCTAssertEqual(value, "1234-5678")
    }

    func testDownloadPassesOutPath() async throws {
        let runner = MockRunner(responses: ["docs download": #"{"ok":true,"result":{"path":"/tmp/x.pdf"}}"#])
        let file = VaultDocsGateway.DocumentFile(id: "a1", fileName: "x.pdf", sizeName: "1 KB")
        try await gateway(runner).download(file: file, box: "b", to: URL(fileURLWithPath: "/tmp/x.pdf"))
        XCTAssertTrue(runner.calls.first?.contains("--out /tmp/x.pdf") ?? false)
    }
}
