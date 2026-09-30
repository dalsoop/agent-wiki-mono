import XCTest
@testable import StateRootKit

final class StateRootKitTests: XCTestCase {

    private let home = "/Users/tester"

    func testDefaultRootIsHomeDirectory() {
        XCTAssertEqual(StateRootKit.resolve(environment: [:], homeDirectory: home), home)
    }

    func testEnvOverrideReplacesTheWholeRoot() {
        let resolved = StateRootKit.resolve(
            environment: ["SWIFT_APP_STATE_ROOT": "/tmp/fixture-root"],
            homeDirectory: home
        )
        XCTAssertEqual(resolved, "/tmp/fixture-root")
    }

    func testEmptyOverrideFallsBackToHome() {
        let resolved = StateRootKit.resolve(
            environment: ["SWIFT_APP_STATE_ROOT": ""],
            homeDirectory: home
        )
        XCTAssertEqual(resolved, home)
    }

    func testTestRunnerMarkersAreAutoIsolated() {
        for key in ["XCTestConfigurationFilePath", "XCTestSessionIdentifier", "XCTestBundlePath", "SWIFT_TESTING_ENABLED"] {
            // 자동 격리는 홈 미지정 호출에만 적용한다 — 명시 홈은 아래 우선순위 테스트가 잠근다.
            let resolved = StateRootKit.resolve(environment: [key: "1"])
            XCTAssertFalse(
                resolved.hasPrefix(NSHomeDirectory()),
                "\(key) 아래에서 사용자 홈으로 가면 안 된다"
            )
            XCTAssertTrue(resolved.contains("swift-app-state-root-tests"))
        }
    }

    /// 명시 homeDirectory 는 테스트 러너 감지보다 우선한다(!7519 실측: CompilePathGuard 가
    /// 임시 홈을 넘겼는데 감지가 공유 테스트 루트로 덮어써 PATH 검증이 깨졌다).
    func testExplicitHomeDirectoryWinsOverTestRunnerDetection() {
        let explicitHome = "/tmp/state-root-explicit-\(UUID().uuidString)"
        let resolved = StateRootKit.resolve(
            environment: ["XCTestConfigurationFilePath": "/x"],
            homeDirectory: explicitHome
        )
        XCTAssertEqual(resolved, explicitHome)
    }

    /// 명시 오버라이드가 테스트 격리보다 우선한다 — 테스트가 자기 임시경로를 지정하면 그걸 쓴다.
    func testExplicitOverrideWinsOverTestIsolation() {
        let resolved = StateRootKit.resolve(
            environment: [
                "SWIFT_APP_STATE_ROOT": "/tmp/mine",
                "XCTestConfigurationFilePath": "/x",
            ],
            homeDirectory: home
        )
        XCTAssertEqual(resolved, "/tmp/mine")
    }

    func testThisVeryTestProcessIsIsolated() {
        XCTAssertFalse(
            StateRootKit.root.hasPrefix(home),
            "테스트가 자기 실행 중에 사용자 홈을 가리키면 이미 샌 것이다"
        )
        XCTAssertTrue(StateRootKit.isRunningUnderTest())
    }

    func testPathJoinsRelativeComponentUnderResolvedRoot() {
        let resolved = StateRootKit.path(
            ".memo-citation-ledger/config.json",
            environment: [:],
            homeDirectory: home
        )
        XCTAssertEqual(resolved, home + "/.memo-citation-ledger/config.json")
    }

    func testUrlMatchesPath() {
        let path = StateRootKit.path(".gujo-wiki", environment: [:], homeDirectory: home)
        let url = StateRootKit.url(".gujo-wiki", environment: [:], homeDirectory: home)
        XCTAssertEqual(url.path, path)
    }

    func testTenantContextRemapsResolveButNotHostPath() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-root-tenant-\(UUID().uuidString)")
        let ctxDir = tmp.appendingPathComponent(".agent-tenant-isolation-manager")
        try FileManager.default.createDirectory(at: ctxDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try Data(#"{"tenantID":"tenant:wife"}"#.utf8)
            .write(to: ctxDir.appendingPathComponent("current-context.json"))
        let tenantHome = tmp.path
        XCTAssertEqual(
            StateRootKit.resolve(environment: [:], homeDirectory: tenantHome),
            (tenantHome as NSString).appendingPathComponent(".tenants/wife")
        )
        XCTAssertEqual(
            StateRootKit.resolveHost(environment: [:], homeDirectory: tenantHome),
            tenantHome
        )
        // fixture 파일명은 registry 리터럴을 쓰지 않는다(registry-json-direct-read) —
        // 이 테스트는 hostPath 가 테넌트 컨텍스트를 무시하는 경로 조립만 잠근다(읽기 없음).
        XCTAssertEqual(
            StateRootKit.hostPath(".agent-apps/fleet-index.json", environment: [:], homeDirectory: tenantHome),
            (tenantHome as NSString).appendingPathComponent(".agent-apps/fleet-index.json")
        )
    }

    func testHealthPulseWritesSortedJSON() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("health-pulse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        HealthPulse.publish(
            app: "LLMRouteManager",
            status: "ok",
            environment: ["SWIFT_APP_STATE_ROOT": tmp.path],
            homeDirectory: tmp.path
        )
        let url = tmp.appendingPathComponent(".swift-app-state/pulse/LLMRouteManager.pulse")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        XCTAssertEqual(obj?["app"] as? String, "LLMRouteManager")
        XCTAssertEqual(obj?["status"] as? String, "ok")
        // 방금 쓴 펄스임을 나이로 확인한다(stale-evidence) — 편도 쓰기·읽기라 무조건 신선.
        let ageSeconds = Int(Date().timeIntervalSince1970) - (obj?["ts"] as? Int ?? 0)
        XCTAssertLessThan(ageSeconds, 60)
    }

    func testCustomerRoomStorageSSOT() {
        let tempHome = NSTemporaryDirectory() + "state-root-customer-test-\(UUID().uuidString)"
        let storageURL = StateRootKit.ensureCustomerRoomStorage(slug: "test-app", homeDirectory: tempHome)
        XCTAssertTrue(storageURL.path.contains("net.ranode.shared/test-app"))
        XCTAssertFalse(storageURL.path.contains("/rooms/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storageURL.path))
        try? FileManager.default.removeItem(atPath: tempHome)
    }

    func testNoRoomAliasesAndExplicitRoomPaths() {
        let tempHome = NSTemporaryDirectory() + "state-root-paths-\(UUID().uuidString)"
        let expected = tempHome + "/Library/Application Support/net.ranode.shared/test-app"

        XCTAssertEqual(StateRootKit.customerAppStorageURL(slug: "test-app", homeDirectory: tempHome).path, expected)
        for alias in ["room:default", "room-default", "default", "", "   \n"] {
            XCTAssertTrue(StateRootKit.isLegacyDefaultRoomID(alias))
            XCTAssertEqual(
                StateRootKit.customerAppStorageURL(slug: "test-app", roomID: alias, homeDirectory: tempHome).path,
                expected
            )
        }
        XCTAssertEqual(
            StateRootKit.customerAppStorageURL(
                slug: "test-app",
                roomID: "BD400651-BA69-4607-A9EA-7A91E3C5DC6E",
                homeDirectory: tempHome
            ).path,
            tempHome + "/Library/Application Support/net.ranode.shared/rooms/BD400651-BA69-4607-A9EA-7A91E3C5DC6E/test-app"
        )
    }

    func testPromotesEachLegacyNoRoomDirectory() throws {
        for legacyRoom in ["room-default", "room:default"] {
            let home = FileManager.default.temporaryDirectory
                .appendingPathComponent("state-root-promote-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: home) }
            let source = legacyStorageURL(home: home, room: legacyRoom)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try Data("legacy".utf8).write(to: source.appendingPathComponent("marker"))

            let result = StateRootKit.promoteLegacyNoRoomStorage(slug: "test-app", homeDirectory: home.path)
            let destination = StateRootKit.noRoomAppStorageURL(slug: "test-app", homeDirectory: home.path)
            XCTAssertEqual(result, .promoted(from: source, to: destination, leftBehind: nil))
            XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("marker").path))
            // 옛 경로는 새 저장소를 가리키는 호환 심링크다 — 옛 빌드가 옛 경로로 써도 새 저장소에 들어간다.
            let linkTarget = try FileManager.default.destinationOfSymbolicLink(atPath: source.path)
            XCTAssertEqual(URL(fileURLWithPath: linkTarget).standardizedFileURL.path, destination.path)
            try Data("from-old-build".utf8).write(to: source.appendingPathComponent("written-by-old-build"))
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: destination.appendingPathComponent("written-by-old-build").path))
            XCTAssertEqual(
                StateRootKit.promoteLegacyNoRoomStorage(slug: "test-app", homeDirectory: home.path),
                .noLegacyStorage
            )
        }
    }

    func testPromotionChoosesNewerStateAndLeavesOlderLegacy() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-root-newer-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let older = legacyStorageURL(home: home, room: "room-default")
        let newer = legacyStorageURL(home: home, room: "room:default")
        try FileManager.default.createDirectory(at: older, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newer, withIntermediateDirectories: true)
        let oldState = older.appendingPathComponent("state.json")
        let newState = newer.appendingPathComponent("state.json")
        try Data("old".utf8).write(to: oldState)
        try Data("new".utf8).write(to: newState)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: oldState.path)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)], ofItemAtPath: newState.path)

        let destination = StateRootKit.noRoomAppStorageURL(slug: "test-app", homeDirectory: home.path)
        XCTAssertEqual(
            StateRootKit.promoteLegacyNoRoomStorage(slug: "test-app", homeDirectory: home.path),
            .promoted(from: newer, to: destination, leftBehind: older)
        )
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("state.json")), Data("new".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.path))
        XCTAssertEqual(
            StateRootKit.promoteLegacyNoRoomStorage(slug: "test-app", homeDirectory: home.path),
            .destinationAlreadyExists(destination)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: older.path))
    }

    func testPromotionDoesNothingWhenNoRoomDestinationExists() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-root-existing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let source = legacyStorageURL(home: home, room: "room-default")
        let destination = StateRootKit.noRoomAppStorageURL(slug: "test-app", homeDirectory: home.path)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        XCTAssertEqual(
            StateRootKit.promoteLegacyNoRoomStorage(slug: "test-app", homeDirectory: home.path),
            .destinationAlreadyExists(destination)
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testPromotionRefusesInjectedRealHomeBoundaryDuringTests() throws {
        let simulatedRealHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("state-root-simulated-real-home-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: simulatedRealHome) }
        let source = legacyStorageURL(home: simulatedRealHome, room: "room-default")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let destination = StateRootKit.noRoomAppStorageURL(slug: "test-app", homeDirectory: simulatedRealHome.path)

        let result = StateRootKit.promoteLegacyNoRoomStorage(
            slug: "test-app",
            homeDirectory: simulatedRealHome.path,
            environment: ["SWIFT_TESTING_ENABLED": "1"],
            processName: "fixture",
            realHomeDirectory: simulatedRealHome.path
        )

        XCTAssertEqual(result, .refusedUnsafeTestHome(destination))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func legacyStorageURL(home: URL, room: String) -> URL {
        home.appendingPathComponent("Library/Application Support/net.ranode.shared/rooms", isDirectory: true)
            .appendingPathComponent(room, isDirectory: true)
            .appendingPathComponent("test-app", isDirectory: true)
    }

    func testStandardUrlAndPathLabeled() {
        let path = StateRootKit.path(for: ".ssot/WORK_STATUS.md", environment: [:], homeDirectory: home)
        let url = StateRootKit.url(for: ".ssot/WORK_STATUS.md", environment: [:], homeDirectory: home)
        XCTAssertEqual(path, home + "/.ssot/WORK_STATUS.md")
        XCTAssertEqual(url.path, path)
    }

    func testStateDirectoryForSlug() {
        // slug without dot -> auto dot prefix
        let dirWithoutDot = StateRootKit.stateDirectory(for: "agent-proxy-broker", environment: [:], homeDirectory: home)
        XCTAssertEqual(dirWithoutDot.path, home + "/.agent-proxy-broker")

        // slug with dot -> preserves dot
        let dirWithDot = StateRootKit.stateDirectory(for: ".agent-proxy-broker", environment: [:], homeDirectory: home)
        XCTAssertEqual(dirWithDot.path, home + "/.agent-proxy-broker")

        // well-known .ssot and .config
        let ssotDir = StateRootKit.stateDirectory(for: ".ssot", environment: [:], homeDirectory: home)
        XCTAssertEqual(ssotDir.path, home + "/.ssot")

        let configDir = StateRootKit.stateDirectory(for: ".config", environment: [:], homeDirectory: home)
        XCTAssertEqual(configDir.path, home + "/.config")

        let pathStr = StateRootKit.stateDirectoryPath(for: "sample-tool", environment: [:], homeDirectory: home)
        XCTAssertEqual(pathStr, home + "/.sample-tool")
    }

    func testEnsureStateDirectory() throws {
        let tempHome = NSTemporaryDirectory() + "state-root-ensure-\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: tempHome) }
        let dir = try StateRootKit.ensureStateDirectory(
            for: "sample-tool",
            environment: [:],
            homeDirectory: tempHome
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertEqual(dir.path, tempHome + "/.sample-tool")
    }

    func testTenantIsolationHelpers() {
        XCTAssertEqual(StateRootKit.tenantSlug(from: "tenant:wife"), "wife")
        XCTAssertEqual(StateRootKit.tenantSlug(from: "personal"), "personal")

        XCTAssertFalse(StateRootKit.isTenantIsolated(environment: [:], homeDirectory: home))
        XCTAssertTrue(StateRootKit.isTenantIsolated(environment: ["ROOM_TENANT": "tenant:wife"], homeDirectory: home))

        let tenantURL = StateRootKit.tenantURL(for: "settings.json", tenant: "tenant:wife", environment: [:], homeDirectory: home)
        XCTAssertEqual(tenantURL.path, home + "/.tenants/wife/settings.json")

        let tenantPath = StateRootKit.tenantPath(for: "settings.json", tenant: "tenant:wife", environment: [:], homeDirectory: home)
        XCTAssertEqual(tenantPath, home + "/.tenants/wife/settings.json")

        let tenantAppDir = StateRootKit.tenantStateDirectory(for: "my-app", tenant: "wife", environment: [:], homeDirectory: home)
        XCTAssertEqual(tenantAppDir.path, home + "/.tenants/wife/.my-app")
    }

    func testSsotAndConfigHelpers() {
        let ssotURL = StateRootKit.ssotURL(for: "ledger.json", environment: [:], homeDirectory: home)
        XCTAssertEqual(ssotURL.path, home + "/.ssot/ledger.json")

        let ssotPath = StateRootKit.ssotPath(for: "WORK_STATUS.md", environment: [:], homeDirectory: home)
        XCTAssertEqual(ssotPath, home + "/.ssot/WORK_STATUS.md")

        let configURL = StateRootKit.configURL(for: "tool.json", environment: [:], homeDirectory: home)
        XCTAssertEqual(configURL.path, home + "/.config/tool.json")

        let configPath = StateRootKit.configPath(for: "tool.json", environment: [:], homeDirectory: home)
        XCTAssertEqual(configPath, home + "/.config/tool.json")
    }
}
