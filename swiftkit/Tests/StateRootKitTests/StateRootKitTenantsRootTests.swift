import XCTest
@testable import StateRootKit

final class StateRootKitTenantsRootTests: XCTestCase {
    func testInsideTenantRootReusesTenantsDirectory() {
        let root = StateRootKit.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/personal"],
            homeDirectory: "/Users/x"
        )
        XCTAssertEqual(root, "/Users/x/.tenants")
    }

    func testInsideRoomFolderClimbsToTenantsDirectory() {
        let root = StateRootKit.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/gujo/rooms/L1/seller/state"],
            homeDirectory: "/Users/x"
        )
        XCTAssertEqual(root, "/Users/x/.tenants")
    }

    func testOutsideRootNestsTenantsDirectory() {
        let root = StateRootKit.tenantsRoot(
            environment: ["SWIFT_APP_STATE_ROOT": "/tmp/isolated"],
            homeDirectory: "/Users/x"
        )
        XCTAssertEqual(root, "/tmp/isolated/.tenants")
        XCTAssertEqual(
            StateRootKit.tenantStateRoot(
                tenant: "tenant:gujo",
                environment: ["SWIFT_APP_STATE_ROOT": "/Users/x/.tenants/personal"],
                homeDirectory: "/Users/x"
            ),
            "/Users/x/.tenants/gujo"
        )
    }

    // MARK: - `.tenants` 층은 상태 루트 안에 겹치지 않는다 (F1EBD86C)

    /// 가짜 홈 — 실제 디스크를 읽지 않는 자리(`current-context.json` 이 없다).
    private let tenantEnv = ["ROOM_TENANT": "tenant:personal"]

    /// 실측 2026-09-25: 테넌트 컨텍스트가 켜진 프로세스가 `.tenants/<slug>/…` 를 이으면
    /// `~/.tenants/personal/.tenants/gujo` 가 생겼다. 호스트 홈 한 층으로 가야 한다.
    func testPathWithTenantsPrefixDoesNotNestInsideTenantRoot() {
        XCTAssertEqual(
            StateRootKit.resolve(environment: tenantEnv, homeDirectory: "/srv/x"),
            "/srv/x/.tenants/personal",
            "전제: 상태 루트는 테넌트 축이다"
        )
        XCTAssertEqual(
            StateRootKit.path(".tenants/gujo/audit.jsonl", environment: tenantEnv, homeDirectory: "/srv/x"),
            "/srv/x/.tenants/gujo/audit.jsonl"
        )
        XCTAssertEqual(
            StateRootKit.url(".tenants", environment: tenantEnv, homeDirectory: "/srv/x").path,
            "/srv/x/.tenants"
        )
        XCTAssertEqual(
            StateRootKit.stateDirectory(for: "tenants", environment: tenantEnv, homeDirectory: "/srv/x").path,
            "/srv/x/.tenants"
        )
        XCTAssertEqual(
            StateRootKit.path("./.tenants/wife", environment: tenantEnv, homeDirectory: "/srv/x"),
            "/srv/x/.tenants/wife"
        )
    }

    /// `.tenants` 층이 아닌 경로는 지금까지처럼 상태 루트(테넌트 축) 밑이다.
    func testOtherRelativePathsStayOnTheTenantAxis() {
        XCTAssertEqual(
            StateRootKit.path(".agent-chat", environment: tenantEnv, homeDirectory: "/srv/x"),
            "/srv/x/.tenants/personal/.agent-chat"
        )
        XCTAssertEqual(
            StateRootKit.path(".tenants-backup/x", environment: tenantEnv, homeDirectory: "/srv/x"),
            "/srv/x/.tenants/personal/.tenants-backup/x",
            "`.tenants-backup` 은 다른 이름이다"
        )
    }

    /// 컨텍스트가 없으면 결과는 예전과 같다 — `<홈>/.tenants/<slug>`.
    func testWithoutTenantContextNothingChanges() {
        XCTAssertEqual(
            StateRootKit.path(".tenants/wife", environment: [:], homeDirectory: "/srv/x"),
            "/srv/x/.tenants/wife"
        )
        XCTAssertEqual(
            StateRootKit.hostPath(".tenants/wife/.swift-app-state", environment: [:], homeDirectory: "/srv/x"),
            "/srv/x/.tenants/wife/.swift-app-state"
        )
        XCTAssertEqual(
            StateRootKit.path(".tenants/wife", environment: ["SWIFT_APP_STATE_ROOT": "/tmp/isolated"],
                              homeDirectory: "/srv/x"),
            "/tmp/isolated/.tenants/wife"
        )
    }

    /// 오버라이드가 테넌트 루트(`use <tenant>` 셸)여도 `path`·`hostPath` 둘 다 겹치지 않는다.
    func testOverrideInsideTenantRootDoesNotNest() {
        let env = ["SWIFT_APP_STATE_ROOT": "/srv/x/.tenants/personal"]
        XCTAssertEqual(
            StateRootKit.path(".tenants/wife", environment: env, homeDirectory: "/srv/x"),
            "/srv/x/.tenants/wife"
        )
        XCTAssertEqual(
            StateRootKit.hostPath(".tenants/wife", environment: env, homeDirectory: "/srv/x"),
            "/srv/x/.tenants/wife"
        )
        XCTAssertEqual(
            StateRootKit.path(".swift-app-state", environment: env, homeDirectory: "/srv/x"),
            "/srv/x/.tenants/personal/.swift-app-state"
        )
    }

    /// 테넌트 루트 기준 조립도 `.tenants` 층은 겹치지 않는다.
    func testTenantPathWithTenantsPrefixDoesNotNest() {
        XCTAssertEqual(
            StateRootKit.tenantPath(for: ".tenants/gujo", tenant: "tenant:wife",
                                    environment: [:], homeDirectory: "/srv/x"),
            "/srv/x/.tenants/gujo"
        )
        XCTAssertEqual(
            StateRootKit.tenantURL(for: "settings.json", tenant: "tenant:wife",
                                   environment: [:], homeDirectory: "/srv/x").path,
            "/srv/x/.tenants/wife/settings.json"
        )
    }

    /// 넘겨받은 홈이 이미 테넌트 루트여도 컨텍스트 테넌트 루트를 그 안에 만들지 않는다.
    func testResolveFromTenantRootHomeDoesNotNest() {
        XCTAssertEqual(
            StateRootKit.resolve(environment: ["ROOM_TENANT": "tenant:wife"],
                                 homeDirectory: "/srv/x/.tenants/personal"),
            "/srv/x/.tenants/wife"
        )
    }
}
