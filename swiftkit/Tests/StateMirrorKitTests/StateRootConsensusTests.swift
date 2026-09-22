import Foundation
import XCTest
import StateRootKit
@testable import StateMirrorKit

/// StateMirror 게시 경로와 StateRootKit 해석 경로의 **합의** 계약.
///
/// router·소비자는 `StateRootKit.url(".swift-app-state")` 로 읽고 앱은
/// `StateMirror.publish` 로 쓴다. 이 둘이 다른 루트를 가리키면(2026-09-02 실측:
/// 테넌트 컨텍스트에서 게시는 홈, 해석은 테넌트 루트 — 함대 전체가 "미게시")
/// 채널이 조용히 갈라진다. directory() 가 홈을 직접 조립하지 않는지
/// 환경별로 잠근다.
final class StateRootConsensusTests: XCTestCase {
    private let tenantContext = """
        {"tenantID":"tenant:consensus-fixtures"}
        """

    private func writeTenantContext(home: String) throws -> String {
        let dir = URL(fileURLWithPath: home).appendingPathComponent(".agent-tenant-isolation-manager")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("current-context.json")
        try tenantContext.data(using: .utf8)!.write(to: file, options: .atomic)
        return file.path
    }

    func testMirrorDirFollowsStateRootResolution() throws {
        let home = NSTemporaryDirectory() + "ssot-home-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home + "/state-root", withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }

        // SWIFT_APP_STATE_ROOT 오버라이드 경로 — resolve() 가 그대로 따른다.
        let dir = StateMirror.directory(
            environment: ["SWIFT_APP_STATE_ROOT": home + "/state-root"],
            homeDirectory: home
        )
        let expected = StateRootKit.url(
            ".swift-app-state",
            environment: ["SWIFT_APP_STATE_ROOT": home + "/state-root"],
            homeDirectory: home
        ).path
        XCTAssertEqual(dir, expected)
    }

    func testMirrorDirFollowsTenantResolution() throws {
        let home = NSTemporaryDirectory() + "ssot-tenant-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        try writeTenantContext(home: home)

        let env: [String: String] = [:] // 오버라이드 없음 — 테넌트 컨텍스트 폴백 경로
        let dir = StateMirror.directory(environment: env, homeDirectory: home)
        let expected = StateRootKit.url(".swift-app-state", environment: env, homeDirectory: home).path

        XCTAssertEqual(dir, expected)
        // 홈에 직접 쓰지 않는지 — 테넌트 컨텍스트에선 테넌트 루트여야 한다.
        XCTAssertTrue(dir.hasSuffix(".tenants/consensus-fixtures/.swift-app-state"))
    }

    func testMirrorDirFallsBackToHomeWithoutContext() throws {
        let home = NSTemporaryDirectory() + "ssot-homeonly-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }

        let env: [String: String] = [:]
        let dir = StateMirror.directory(environment: env, homeDirectory: home)
        XCTAssertEqual(dir, (home as NSString).appendingPathComponent(".swift-app-state"))
    }
}
