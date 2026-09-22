import XCTest
@testable import PluginKit

/// 등록 문에서 액션 이름을 검사하는 계약.
///
/// `no-dotted-action-in-plugin` 은 소스 텍스트를 본다. CLI 가 `capabilities --json`
/// 으로 런타임에 보고한 이름은 소스에 리터럴이 없어 그 린트가 **원리적으로 못 본다.**
/// 이 파일은 그 사각을 메우는 문이 열려 있지 않은지 지킨다.
final class PluginRegistryActionVettingTests: XCTestCase {
    private struct StubPlugin: AppPlugin {
        let id: String
        let name = "Stub"
        let version = "1.0.0"
        let actions: [String]
        var dependencies: [String] { [] }
        func execute(action: String, argv: [String]) async throws -> [String: Sendable] { [:] }
    }

    func testDottedActionNameIsRecordedAtRegistration() {
        let registry = PluginRegistry()
        registry.register(StubPlugin(id: "demo", actions: ["get", "secret.get"]))
        let refused = registry.rejectedActions(id: "demo")
        XCTAssertEqual(refused.count, 1)
        XCTAssertTrue(refused[0].hasPrefix("secret.get — "), refused[0])
    }

    /// 사유가 없으면 CLI 쪽 결함이 "그냥 안 됨"으로 뭉개진다.
    func testRejectionNamesTheRealSubcommand() {
        let registry = PluginRegistry()
        registry.register(StubPlugin(id: "demo", actions: ["vault.secret.get"]))
        XCTAssertTrue(registry.rejectedActions(id: "demo")[0].contains("'get'"),
                      registry.rejectedActions(id: "demo")[0])
    }

    func testCleanPluginRecordsNothing() {
        let registry = PluginRegistry()
        registry.register(StubPlugin(id: "demo", actions: ["status", "run", "ship-queue"]))
        XCTAssertTrue(registry.rejectedActions(id: "demo").isEmpty)
        XCTAssertTrue(registry.allRejectedActions().isEmpty)
    }

    /// 같은 id 로 깨끗한 플러그인을 다시 등록하면 옛 기록이 남으면 안 된다.
    func testReregisteringACleanPluginClearsTheOldRecord() {
        let registry = PluginRegistry()
        registry.register(StubPlugin(id: "demo", actions: ["secret.get"]))
        XCTAssertFalse(registry.rejectedActions(id: "demo").isEmpty)
        registry.register(StubPlugin(id: "demo", actions: ["get"]))
        XCTAssertTrue(registry.rejectedActions(id: "demo").isEmpty)
    }

    func testUnregisterDropsTheRecord() {
        let registry = PluginRegistry()
        registry.register(StubPlugin(id: "demo", actions: ["secret.get"]))
        registry.unregister(id: "demo")
        XCTAssertTrue(registry.allRejectedActions().isEmpty)
    }

    /// 등록 자체는 여전히 성공한다 — 지금은 기록만 하고 디스패치를 막지 않는다.
    func testRegistrationStillSucceedsDespiteRejections() {
        let registry = PluginRegistry()
        registry.register(StubPlugin(id: "demo", actions: ["secret.get"]))
        XCTAssertEqual(registry.get(id: "demo")?.id, "demo")
        // 기록은 남되 액션은 그대로 실려 있어야 한다(지금은 디스패치를 막지 않는다).
        XCTAssertEqual(registry.get(id: "demo")?.actions, ["secret.get"])
        XCTAssertFalse(registry.rejectedActions(id: "demo").isEmpty)
    }
}
