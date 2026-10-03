import XCTest
@testable import SessionKit

/// 무인 실행 인자 — 실제 도구는 부르지 않고 인자 모양만 본다.
final class UnattendedRunPlanTests: XCTestCase {
    func testClaudePrintModeWithModelAndEffortOnStandardInput() throws {
        let plan = try XCTUnwrap(SupportedAIAgentCLI.claude.unattendedRunPlan(
            prompt: "질문", model: "claude-opus-5-5", effort: "high"))
        XCTAssertEqual(plan.standardInput, "질문")
        XCTAssertEqual(plan.arguments.first, "-p")
        XCTAssertTrue(plan.arguments.contains("--no-session-persistence"))
        XCTAssertEqual(Array(plan.arguments.suffix(4)), ["--model", "claude-opus-5-5", "--effort", "high"])
        XCTAssertFalse(plan.arguments.contains("질문"))
    }

    func testUnknownEffortIsNotPassed() throws {
        let plan = try XCTUnwrap(SupportedAIAgentCLI.claude.unattendedRunPlan(
            prompt: "q", model: "m", effort: "unknown"))
        XCTAssertFalse(plan.arguments.contains("--effort"))
    }

    func testCodexExecReadsPromptFromStandardInput() throws {
        let plan = try XCTUnwrap(SupportedAIAgentCLI.codex.unattendedRunPlan(
            prompt: "q", model: "gpt-5", effort: "medium"))
        XCTAssertEqual(plan.arguments.first, "exec")
        XCTAssertEqual(plan.arguments.last, "-")
        XCTAssertTrue(plan.arguments.contains("model_reasoning_effort=\"medium\""))
        XCTAssertEqual(plan.standardInput, "q")
    }

    func testGrokSingleTurnTakesPromptAsArgument() throws {
        let plan = try XCTUnwrap(SupportedAIAgentCLI.grok.unattendedRunPlan(prompt: "q", model: "grok-5", effort: nil))
        XCTAssertEqual(Array(plan.arguments.suffix(2)), ["--single", "q"])
        XCTAssertNil(plan.standardInput)
    }

    func testUnconfirmedToolsAreUnsupported() {
        for cli in [SupportedAIAgentCLI.agy, .opencode, .cursor] {
            XCTAssertNil(cli.unattendedRunPlan(prompt: "q", model: "m", effort: nil))
            XCTAssertFalse(cli.supportsUnattendedRun)
        }
        XCTAssertTrue(SupportedAIAgentCLI.claude.supportsUnattendedRun)
    }
}
