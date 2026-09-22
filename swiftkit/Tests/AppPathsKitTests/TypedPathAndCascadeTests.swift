import XCTest
@testable import AppPathsKit

final class TypedPathAndCascadeTests: XCTestCase {

    // MARK: - TypedPath Tests

    func testTypedPathOperations() {
        let statePath: StatePath = "/tmp/test-app"
        XCTAssertEqual(statePath.path, "/tmp/test-app")
        XCTAssertEqual(statePath.lastPathComponent, "test-app")

        let child = statePath.appending("database.sqlite")
        XCTAssertEqual(child.path, "/tmp/test-app/database.sqlite")
        XCTAssertEqual(child.lastPathComponent, "database.sqlite")
        XCTAssertEqual(child.pathExtension, "sqlite")
        XCTAssertEqual(child.deletingPathExtension.path, "/tmp/test-app/database")

        let parent = child.deletingLastPathComponent
        XCTAssertEqual(parent.path, "/tmp/test-app")

        let casted: LockPath = child.unsafeCast()
        XCTAssertEqual(casted.path, "/tmp/test-app/database.sqlite")
    }

    func testTypedPathCategoryHelpers() {
        let statePath: StatePath = "/tmp/my-app"
        XCTAssertEqual(statePath.stateFile.lastPathComponent, "state.json")
        XCTAssertEqual(statePath.settingsFile.lastPathComponent, "settings.json")
        XCTAssertEqual(statePath.sqliteFile.lastPathComponent, "app.sqlite")
        XCTAssertEqual(statePath.file("custom.txt").lastPathComponent, "custom.txt")
        XCTAssertEqual(statePath.directory("nested").lastPathComponent, "nested")

        let lock = statePath.lockFile(name: "sync")
        XCTAssertEqual(lock.path, "/tmp/my-app/locks/sync.lock")

        let cache = statePath.cacheDirectory()
        XCTAssertEqual(cache.path, "/tmp/my-app/cache")
    }

    func testTypedPathCodable() throws {
        let original: StatePath = "/var/data/state"
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StatePath.self, from: encoded)
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.path, "/var/data/state")
    }

    // MARK: - Cascade Resolution Tests

    func testCascadePriority1AppSpecificEnv() {
        let env = [
            "AGENT_WIKI_STATE_ROOT": "/custom/agent-wiki/state",
            "SWIFT_APP_STATE_ROOT": "/fleet/root",
            "SANDBOX_ROOM_ID": "room-xyz",
            "XDG_STATE_HOME": "/xdg/state"
        ]

        let (path, source) = AppPaths.resolveStateRootWithSource(slug: "agent-wiki", environment: env)
        XCTAssertEqual(path.path, "/custom/agent-wiki/state")
        XCTAssertEqual(source, .appSpecificEnv(key: "AGENT_WIKI_STATE_ROOT", value: "/custom/agent-wiki/state"))
    }

    func testCascadePriority2FleetStateRoot() {
        let env = [
            "SWIFT_APP_STATE_ROOT": "/fleet/root",
            "SANDBOX_ROOM_ID": "room-xyz",
            "XDG_STATE_HOME": "/xdg/state"
        ]

        let (path, source) = AppPaths.resolveStateRootWithSource(slug: "agent-wiki", environment: env)
        XCTAssertEqual(path.path, "/fleet/root/Library/Application Support/net.ranode.agent-wiki")
        XCTAssertEqual(source, .swiftAppStateRoot(value: "/fleet/root"))
    }

    func testCascadePriority3SandboxRoom() {
        let mockHome = URL(fileURLWithPath: "/Users/testuser")
        let env = [
            "SANDBOX_ROOM_ID": "b514ab27",
            "XDG_STATE_HOME": "/xdg/state"
        ]

        let (path, source) = AppPaths.resolveStateRootWithSource(slug: "agent-wiki", environment: env, homeDirectory: mockHome)
        XCTAssertEqual(path.path, "/Users/testuser/.sandboxes/room-b514ab27/agent-wiki")
        XCTAssertEqual(source, .sandboxRoom(roomID: "b514ab27"))
    }

    func testCascadePriority4XDG() {
        let env = [
            "XDG_STATE_HOME": "/custom/xdg/state"
        ]

        let (path, source) = AppPaths.resolveStateRootWithSource(slug: "agent-wiki", environment: env)
        XCTAssertEqual(path.path, "/custom/xdg/state/agent-wiki")
        XCTAssertEqual(source, .xdg(variable: "XDG_STATE_HOME", value: "/custom/xdg/state"))
    }

    func testCascadePriority5MacOSStandard() {
        let mockHome = URL(fileURLWithPath: "/Users/testuser")
        let env: [String: String] = [:]

        let (path, source) = AppPaths.resolveStateRootWithSource(slug: "agent-wiki", environment: env, homeDirectory: mockHome)
        XCTAssertEqual(path.path, "/Users/testuser/Library/Application Support/net.ranode.agent-wiki")
        XCTAssertEqual(source, .macosStandard)
    }

    // MARK: - Factory Methods Tests

    func testStandardFactoryMethods() {
        let mockHome = URL(fileURLWithPath: "/Users/testuser")
        let env: [String: String] = [:]

        let lock = AppPaths.lockFile(slug: "my-app", name: "sync", environment: env, homeDirectory: mockHome)
        XCTAssertEqual(lock.path, "/Users/testuser/Library/Application Support/net.ranode.my-app/locks/sync.lock")

        let sqliteURL = AppPaths.sqliteURL(slug: "my-app", environment: env, homeDirectory: mockHome)
        XCTAssertEqual(sqliteURL.path, "/Users/testuser/Library/Application Support/net.ranode.my-app/app.sqlite")

        let cache = AppPaths.cacheDirectory(slug: "my-app", environment: env, homeDirectory: mockHome)
        XCTAssertEqual(cache.path, "/Users/testuser/Library/Caches/net.ranode.my-app")
    }

    func testSqliteURLCascadeIsolation() {
        let mockHome = URL(fileURLWithPath: "/Users/testuser")

        // 1. App-specific env
        let appEnv = ["MY_APP_STATE_ROOT": "/custom/app-root"]
        let appSqlite = AppPaths.sqliteURL(slug: "my-app", environment: appEnv, homeDirectory: mockHome)
        XCTAssertEqual(appSqlite.path, "/custom/app-root/app.sqlite")

        // 2. SWIFT_APP_STATE_ROOT
        let fleetEnv = ["SWIFT_APP_STATE_ROOT": "/fleet/root"]
        let fleetSqlite = AppPaths.sqliteURL(slug: "my-app", environment: fleetEnv, homeDirectory: mockHome)
        XCTAssertEqual(fleetSqlite.path, "/fleet/root/Library/Application Support/net.ranode.my-app/app.sqlite")

        // 3. SANDBOX_ROOM_ID
        let roomEnv = ["SANDBOX_ROOM_ID": "room-xyz"]
        let roomSqlite = AppPaths.sqliteURL(slug: "my-app", environment: roomEnv, homeDirectory: mockHome)
        XCTAssertEqual(roomSqlite.path, "/Users/testuser/.sandboxes/room-room-xyz/my-app/app.sqlite")

        // 4. XDG_STATE_HOME
        let xdgEnv = ["XDG_STATE_HOME": "/custom/xdg"]
        let xdgSqlite = AppPaths.sqliteURL(slug: "my-app", environment: xdgEnv, homeDirectory: mockHome)
        XCTAssertEqual(xdgSqlite.path, "/custom/xdg/my-app/app.sqlite")
    }

    func testCacheDirectoryCascadeIsolation() {
        let mockHome = URL(fileURLWithPath: "/Users/testuser")

        // 1. App-specific env
        let appEnv = ["MY_APP_STATE_ROOT": "/custom/app-root"]
        let appCache = AppPaths.cacheDirectory(slug: "my-app", environment: appEnv, homeDirectory: mockHome)
        XCTAssertEqual(appCache.path, "/custom/app-root/cache")

        // 2. SWIFT_APP_STATE_ROOT
        let fleetEnv = ["SWIFT_APP_STATE_ROOT": "/fleet/root"]
        let fleetCache = AppPaths.cacheDirectory(slug: "my-app", environment: fleetEnv, homeDirectory: mockHome)
        XCTAssertEqual(fleetCache.path, "/fleet/root/Library/Caches/net.ranode.my-app")

        // 3. SANDBOX_ROOM_ID
        let roomEnv = ["SANDBOX_ROOM_ID": "room-xyz"]
        let roomCache = AppPaths.cacheDirectory(slug: "my-app", environment: roomEnv, homeDirectory: mockHome)
        XCTAssertEqual(roomCache.path, "/Users/testuser/.sandboxes/room-room-xyz/my-app/cache")

        // 4. XDG_STATE_HOME
        let xdgEnv = ["XDG_STATE_HOME": "/custom/xdg"]
        let xdgCache = AppPaths.cacheDirectory(slug: "my-app", environment: xdgEnv, homeDirectory: mockHome)
        XCTAssertEqual(xdgCache.path, "/custom/xdg/my-app/cache")
    }

    func testTestRunnerAutoIsolation() {
        let env = ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"]
        let sqlite = AppPaths.sqliteURL(slug: "my-app", environment: env)
        XCTAssertTrue(sqlite.path.contains("swift-app-state-root-tests"))
        XCTAssertFalse(sqlite.path.contains("/Users/"))

        let cache = AppPaths.cacheDirectory(slug: "my-app", environment: env)
        XCTAssertTrue(cache.path.contains("swift-app-state-root-tests"))
        XCTAssertFalse(cache.path.contains("/Users/"))
    }

    // MARK: - POSIX Permission (0o700) Tests

    func testEnsureDirectoryWith0o700() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-0o700-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try AppPaths.ensureDirectory(at: tmpDir, permissions: 0o700)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpDir.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: tmpDir.path)
        if let posixPermissions = attrs[.posixPermissions] as? NSNumber {
            XCTAssertEqual(posixPermissions.intValue & 0o777, 0o700)
        }
    }

    func testLockPathWithFileLock() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-lock-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("test.lock")
        defer { try? FileManager.default.removeItem(at: tmpFile.deletingLastPathComponent()) }

        let lockPath = LockPath(url: tmpFile)
        var executed = false
        try lockPath.withFileLock {
            executed = true
            XCTAssertTrue(FileManager.default.fileExists(atPath: tmpFile.path))
        }
        XCTAssertTrue(executed)
    }
}
