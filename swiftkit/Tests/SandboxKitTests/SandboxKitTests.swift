import Foundation
@testable import SandboxKit
import StateRootKit
import XCTest

final class SandboxKitTests: XCTestCase {
    func temporaryTestHome() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-kit-tests-\(UUID().uuidString)", isDirectory: true)
    }

    func testSeatbeltProfileGeneration() {
        let profile = SeatbeltProfile(
            sandboxPath: "/Users/test/.sandboxes/room-101",
            tmpPath: "/Users/test/.sandboxes/room-101/tmp",
            allowedWritePaths: ["/Users/test/workspace/extra"]
        )
        let scheme = profile.generateScheme()

        XCTAssertTrue(scheme.contains("(version 1)"))
        XCTAssertTrue(scheme.contains("(allow default)"))
        XCTAssertTrue(scheme.contains("(deny file-write* (subpath"))
        XCTAssertTrue(scheme.contains("(allow file-write* (subpath \"/Users/test/.sandboxes/room-101\"))"))
        XCTAssertTrue(scheme.contains("(allow file-write* (subpath \"/Users/test/.sandboxes/room-101/tmp\"))"))
        XCTAssertTrue(scheme.contains("(allow file-write* (subpath \"/Users/test/workspace/extra\"))"))
    }

    func testSeatbeltProfileProxyPortRule() {
        let profile = SeatbeltProfile(
            sandboxPath: "/tmp/room",
            tmpPath: "/tmp/room/tmp",
            allowNetwork: false,
            proxyPort: 18080
        )
        let scheme = profile.generateScheme()
        XCTAssertTrue(scheme.contains("(allow network-outbound (remote ip \"localhost:18080\"))"), scheme)
        XCTAssertTrue(scheme.contains("(allow network-outbound (remote ip \"*:18080\"))"), scheme)
        XCTAssertFalse(scheme.contains("(deny network*)"), scheme)
    }

    func testSandboxContextAllocationAndEnvironment() throws {
        let home = temporaryTestHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let context = try SandboxContext.allocate(
            tenant: "tenant:acme",
            agentID: "agent:marketer@mac",
            roomID: "room-test-01",
            homeDirectory: home.path
        )

        XCTAssertEqual(context.roomID, "room-test-01")
        XCTAssertEqual(context.tenantSlug, "acme")
        XCTAssertEqual(context.agentID, "agent:marketer@mac")
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.sandboxDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: context.tmpDirectory.path))

        let env = context.makeEnvironment(base: ["BASE_KEY": "val"])
        XCTAssertEqual(env["BASE_KEY"], "val")
        XCTAssertEqual(env["TENANT_ID"], "acme")
        XCTAssertEqual(env["GUJO_TENANT_ID"], "acme")
        XCTAssertEqual(env["SWIFT_APP_STATE_ROOT"], context.sandboxDirectory.path)
        XCTAssertEqual(env["TMPDIR"], context.tmpDirectory.path)
        XCTAssertEqual(env["AGENT_ID"], "agent:marketer@mac")
        XCTAssertEqual(env["SANDBOX_ROOM_ID"], "room-test-01")

        try context.teardown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.sandboxDirectory.path))
    }

    func testPromotionEngineChecksumAndAtomicCopy() throws {
        let home = temporaryTestHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let context = try SandboxContext.allocate(
            tenant: "acme",
            roomID: "room-promo-test",
            homeDirectory: home.path
        )
        defer { try? context.teardown() }

        // 샌드박스 안에 임시 캠페인 파일 생성
        let campaignFile = context.sandboxDirectory.appendingPathComponent("campaigns/camp-01.json")
        try FileManager.default.createDirectory(at: campaignFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sampleData = "{\"id\":\"camp-01\",\"title\":\"Summer Promo\"}".data(using: .utf8)!
        try sampleData.write(to: campaignFile)

        // 1. 영수증 발행
        let receipt = try PromotionEngine.makeReceipt(
            context: context,
            relativePaths: ["campaigns/camp-01.json"]
        )
        XCTAssertEqual(receipt.artifacts.count, 1)
        XCTAssertEqual(receipt.artifacts[0].relativePath, "campaigns/camp-01.json")
        XCTAssertFalse(receipt.artifacts[0].sha256.isEmpty)

        // 2. 정본으로 원자적 승격
        try PromotionEngine.promote(context: context, receipt: receipt)

        let targetFile = context.readOnlyMasterRoot.appendingPathComponent("campaigns/camp-01.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))

        let targetData = try Data(contentsOf: targetFile)
        XCTAssertEqual(targetData, sampleData)

        // 3. 영수증 파일 검증
        let receiptRecord = context.readOnlyMasterRoot.appendingPathComponent(".receipts/\(receipt.receiptID).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptRecord.path))
    }

    func testPromotionFailsOnChecksumTampering() throws {
        let home = temporaryTestHome()
        defer { try? FileManager.default.removeItem(at: home) }

        let context = try SandboxContext.allocate(
            tenant: "acme",
            homeDirectory: home.path
        )
        defer { try? context.teardown() }

        let file = context.sandboxDirectory.appendingPathComponent("test.txt")
        try "original".write(to: file, atomically: true, encoding: .utf8)

        let receipt = try PromotionEngine.makeReceipt(context: context, relativePaths: ["test.txt"])

        // 파일 내용 위변조
        try "tampered".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try PromotionEngine.promote(context: context, receipt: receipt)) { error in
            guard case PromotionError.checksumMismatch = error else {
                XCTFail("Expected checksumMismatch error but got \(error)")
                return
            }
        }
    }

    func testOneShotSandboxAutoCleanup() async throws {
        let home = temporaryTestHome()
        defer { try? FileManager.default.removeItem(at: home) }

        var capturedPath: String?

        try SandboxRunner.withOneShotSandbox(
            tenant: "personal",
            homeDirectory: home.path
        ) { context in
            capturedPath = context.sandboxDirectory.path
            XCTAssertTrue(FileManager.default.fileExists(atPath: context.sandboxDirectory.path))
        }

        if let capturedPath {
            XCTAssertFalse(FileManager.default.fileExists(atPath: capturedPath))
        } else {
            XCTFail("Captured path should not be nil")
        }
    }
}
