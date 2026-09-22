import XCTest
@testable import MarketingVersionKit

final class VersionSSOTTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        root = (FileManager.default.temporaryDirectory
            .appendingPathComponent("vssot-\(UUID().uuidString)")).path
        try FileManager.default.createDirectory(
            atPath: VersionSSOT.directory(root: root), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        do {
            try FileManager.default.removeItem(atPath: root)
        } catch let error {
            print("SSOT 테스트 정리 실패: \(error)")  // allow:debug — 테스트 정리 로그
        }
        root = nil
    }

    func testWriteAndRoundTrip() throws {
        try VersionSSOT.write(root: root, app: "agent-deck-swift", version: "1.2.3")
        XCTAssertEqual(VersionSSOT.version(root: root, app: "agent-deck-swift"), "1.2.3")
        XCTAssertTrue(VersionSSOT.apps(root: root).contains("agent-deck-swift"))
    }

    func testMissingAppReturnsNil() {
        XCTAssertNil(VersionSSOT.version(root: root, app: "ghost-swift"))
    }

    func testDriftJudgement() throws {
        try VersionSSOT.write(root: root, app: "a-swift", version: "2.0.1")
        XCTAssertEqual(VersionSSOT.drift(root: root, app: "a-swift", plistVersion: "1.0.0"), true)
        XCTAssertEqual(VersionSSOT.drift(root: root, app: "a-swift", plistVersion: "2.0.1"), false)
        XCTAssertNil(VersionSSOT.drift(root: root, app: "legacy-app", plistVersion: "9.9.9"))
    }
}
