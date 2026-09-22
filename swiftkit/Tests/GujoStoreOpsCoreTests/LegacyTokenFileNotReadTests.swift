import Foundation
import XCTest
@testable import GujoStoreOpsCore

final class LegacyTokenFileNotReadTests: XCTestCase {
    func testProbeSeesFileButAuthDoesNotReadIt() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gujo-store-ops-legacy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("token")
        let sentinel = "FILE-SECRET-MUST-NOT-BE-USED"
        try sentinel.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(LegacyPlaintextTokenProbe.exists(at: file.path, fileManager: FileManager.default))

        let provider = StaticStaffTokenProvider(token: nil)
        XCTAssertNil(try provider.staffToken())

        let leftover = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(leftover, sentinel)
    }

    func testKeychainProviderSourceDoesNotReadTokenFiles() throws {
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/GujoStoreOpsCore/KeychainStaffTokenProvider.swift")
        let text = try String(contentsOf: src, encoding: .utf8)
        XCTAssertFalse(text.contains("contentsOfFile"))
        XCTAssertFalse(text.contains(".gujo-store-ops"))
        XCTAssertFalse(text.contains(".gujo-skill-store"))
        XCTAssertFalse(text.contains("GUJO_STORE_OPS_TOKEN"))
        XCTAssertFalse(text.contains("UserDefaults"))
        XCTAssertTrue(text.contains("net.ranode.gujo"))
        XCTAssertTrue(text.contains("staff"))
    }

    func testOpsPreferencesSourceDoesNotReadEnvOrFiles() throws {
        let src = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/GujoStoreOpsCore/OpsPreferences.swift")
        let text = try String(contentsOf: src, encoding: .utf8)
        XCTAssertFalse(text.contains("contentsOfFile"))
        XCTAssertFalse(text.contains("GUJO_STORE_OPS_TOKEN"))
        XCTAssertFalse(text.contains("GUJO_STORE_OPS_BASE"))
    }

    func testLegacyProbeHasNoReadAPIOnType() {
        // Existence only — contents are never part of the probe surface.
        XCTAssertEqual(LegacyPlaintextTokenProbe.storeOpsRelativePath, ".gujo-store-ops/token")
        XCTAssertEqual(LegacyPlaintextTokenProbe.skillStoreRelativePath, ".gujo-skill-store/token")
        let names = Mirror(reflecting: LegacyPlaintextTokenProbe.self).children.map(\.label)
        XCTAssertFalse(names.contains { ($0 ?? "").localizedCaseInsensitiveContains("read") })
    }
}
