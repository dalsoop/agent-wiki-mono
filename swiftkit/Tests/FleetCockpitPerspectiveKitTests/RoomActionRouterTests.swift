import Foundation
import Testing
import os
import CommandKit
@testable import FleetCockpitPerspectiveKit

private final class MockActionRunner: CommandRunning, Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [(command: String, args: [String])]())
    let stubbedResult: CommandResult = CommandResult(stdout: "ok", stderr: "", exitCode: 0)

    var executedCommands: [(command: String, args: [String])] {
        lock.withLock { $0 }
    }

    func run(_ command: String, _ args: [String], timeout: TimeInterval?) async -> CommandResult {
        lock.withLock { $0.append((command, args)) }
        return stubbedResult
    }
}

@Suite("RoomActionRouter Tests — 1-Click Native Jump SSOT")
struct RoomActionRouterTests {

    @Test("RoomActionRouter: bundle id is net.ranode.agentdeck")
    func testBundleIdentifierSSOT() {
        #expect(RoomActionRouter.agentDeckBundleID == "net.ranode.agentdeck")
    }

    @Test("RoomActionRouter: empty path fails closed without command execution")
    func testEmptyPathFailClosed() async {
        let runner = MockActionRunner()
        let result = await RoomActionRouter.openRoom(path: "   ", runner: runner)
        #expect(!result.ok)
        #expect(runner.executedCommands.isEmpty)
    }

    @Test("RoomActionRouter: fallback executes open with path")
    func testFallbackExecution() async {
        let runner = MockActionRunner()
        let result = await RoomActionRouter.openRoom(path: "/tmp/test-room", runner: runner)
        #expect(result.ok)
        #expect(!runner.executedCommands.isEmpty)
        let first = runner.executedCommands[0]
        #expect(first.command == "/usr/bin/open")
        #expect(first.args.contains("/tmp/test-room"))
    }

    @Test("RoomActionRouter: isolated environment injection via --env without mutating process setenv")
    func testIsolatedEnvironmentWithoutSetenv() async {
        let runner = MockActionRunner()
        let previousStateRoot = getenv("SWIFT_APP_STATE_ROOT").map { String(cString: $0) }
        let previousTenantID = getenv("TENANT_ID").map { String(cString: $0) }

        let result = await RoomActionRouter.openRoom(
            path: "/tmp/test-room",
            environment: [
                "SWIFT_APP_STATE_ROOT": "/custom/tenants/demo",
                "TENANT_ID": "tenant:demo"
            ],
            runner: runner
        )

        #expect(result.ok)
        #expect(!runner.executedCommands.isEmpty)
        let first = runner.executedCommands[0]
        #expect(first.command == "/usr/bin/open")
        #expect(first.args.contains("-n"))
        #expect(first.args.contains("--env"))
        #expect(first.args.contains("SWIFT_APP_STATE_ROOT=/custom/tenants/demo"))
        #expect(first.args.contains("TENANT_ID=tenant:demo"))

        // 프로세스 자체의 환경변수는 오염되지 않아야 함 (격리 보장)
        let currentStateRoot = getenv("SWIFT_APP_STATE_ROOT").map { String(cString: $0) }
        let currentTenantID = getenv("TENANT_ID").map { String(cString: $0) }
        #expect(currentStateRoot == previousStateRoot)
        #expect(currentTenantID == previousTenantID)
    }

    @Test("RoomSource: terminal environment stays bound to exact room and tenant")
    func testRoomBoundTerminalEnvironment() {
        let environment = RoomSource.terminalEnvironment(
            roomID: "room-1234-5678",
            tenantID: "tenant:customer-a"
        )

        #expect(environment["ROOM_ID"] == "1234-5678")
        #expect(environment["ROOM_TENANT"] == "tenant:customer-a")
        #expect(environment["AGENT_TENANT"] == "tenant:customer-a")
        #expect(environment["TENANT_ID"] == "tenant:customer-a")
        #expect(environment["SWIFT_APP_STATE_ROOT"] != nil)
    }
}
