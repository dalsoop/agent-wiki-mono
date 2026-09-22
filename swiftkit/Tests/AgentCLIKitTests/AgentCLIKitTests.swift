import XCTest
@testable import AgentCLIKit

final class AgentCLIKitTests: XCTestCase {
    private let app = AgentCLIApp(slug: "test", workspaceRoot: nil)

    func testReservedAgentIsNotHandledButSkillIs() async {
        let app = AgentCLIApp(slug: "test", reservedCommands: ["agent"])
        let cmd = AgentCLICommand(app: app)
        let agent = await cmd.handle(["agent", "list"])
        if case .notHandled = agent { /* ok */ } else { XCTFail("reserved agent must not be swallowed") }
        let skill = await cmd.handle(["skill", "list"])
        guard case let .handled(code) = skill else { return XCTFail("skill stays on the rail") }
        XCTAssertEqual(code, 0)
    }

    func testNotHandledForUnknown() async {
        let r = await AgentCLICommand(app: app).handle(["unknown"])
        if case .notHandled = r { /* ok */ } else { XCTFail("expected notHandled") }
    }

    func testNotHandledForEmpty() async {
        let r = await AgentCLICommand(app: app).handle([])
        if case .notHandled = r { /* ok */ } else { XCTFail("expected notHandled") }
    }

    func testAgentListHandledZero() async throws {
        let r = await AgentCLICommand(app: app).handle(["agent", "list"])
        guard case let .handled(code) = r else { return XCTFail("expected handled") }
        XCTAssertEqual(code, 0)
    }

    func testAgentScanHandledZero() async throws {
        let r = await AgentCLICommand(app: app).handle(["agent", "scan"])
        guard case let .handled(code) = r else { return XCTFail("expected handled") }
        XCTAssertEqual(code, 0)
    }

    func testAgentHelpHandledZero() async throws {
        let r = await AgentCLICommand(app: app).handle(["agent", "--help"])
        guard case let .handled(code) = r else { return XCTFail("expected handled") }
        XCTAssertEqual(code, 0)
    }

    func testSkillListHandledZero() async throws {
        let r = await AgentCLICommand(app: app).handle(["skill", "list"])
        guard case let .handled(code) = r else { return XCTFail("expected handled") }
        XCTAssertEqual(code, 0)
    }

    func testChatEmptyPromptHandled64() async throws {
        let r = await AgentCLICommand(app: app).handle(["chat"])
        guard case let .handled(code) = r else { return XCTFail("expected handled") }
        XCTAssertEqual(code, 64)
    }

    func testChatBackendMissingValueHandled64() async throws {
        let r = await AgentCLICommand(app: app).handle(["chat", "--backend"])
        guard case let .handled(code) = r else { return XCTFail("expected handled") }
        XCTAssertEqual(code, 64)
    }

    func testChatHelpHandledZero() async throws {
        let r = await AgentCLICommand(app: app).handle(["chat", "--help"])
        guard case let .handled(code) = r else { return XCTFail("expected handled") }
        XCTAssertEqual(code, 0)
    }

    func testAgentShowMissingIdHandled64() async throws {
        let r = await AgentCLICommand(app: app).handle(["agent", "show"])
        guard case let .handled(code) = r else { return XCTFail("expected handled") }
        XCTAssertEqual(code, 64)
    }

    func testDoctorIsNotOnTheRail() async {
        let r = await AgentCLICommand(app: app).handle(["doctor"])
        guard case .notHandled = r else { return XCTFail("doctor is not a rail verb") }
    }

    func testStatusIsHandledOnTheRail() async {
        let r = await AgentCLICommand(app: app).handle(["status"])
        guard case let .handled(code) = r else { return XCTFail("status is a rail verb") }
        XCTAssertEqual(code, 0)
    }

    func testRunSyncUnknownReturnsNil() {
        XCTAssertNil(AgentCLICommand(app: app).runSync(["open"]))
    }

    /// 동기 진입점은 비동기 진입점의 결과를 그대로 옮겨야 한다 —
    /// "코드가 나왔다" 만 보면 0 과 64 가 뒤바뀌어도 초록이다.
    func testRunSyncStatusCarriesTheSameCodeAsHandle() async {
        let sync = AgentCLICommand(app: app).runSync(["status"])
        guard case let .handled(code) = await AgentCLICommand(app: app).handle(["status"]) else {
            return XCTFail("status 는 레일이 처리한다")
        }
        XCTAssertEqual(sync, code)
    }

    func testRailVerbsAreTheHandleSurface() {
        XCTAssertEqual(
            AgentCLICommand.railVerbs,
            ["agent", "skill", "chat", "status"]
        )
    }
}
