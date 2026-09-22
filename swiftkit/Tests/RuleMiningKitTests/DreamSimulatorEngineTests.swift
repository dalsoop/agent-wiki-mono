import XCTest
@testable import RuleMiningKit

final class DreamSimulatorEngineTests: XCTestCase {

    func testNormalRulePassesSimulationAndSLA() {
        let normalRule = DeclarativeMinedRule(
            id: "rule-clean-anti-blocking",
            summary: "Detect synchronous blocking on main queue",
            pattern: "\\bDispatchQueue\\.main\\.sync\\b",
            message: "Avoid synchronous blocking on main queue",
            fix: "Task { @MainActor in ... }",
            grade: "observation",
            targetFileExtensions: ["swift"],
            excludePathPatterns: ["/Tests/", "/Fixtures/"]
        )

        let engine = DreamSimulatorEngine()
        let result = engine.simulateDream(candidate: normalRule)

        XCTAssertTrue(result.passed)
        XCTAssertEqual(result.falsePositiveCount, 0)
        XCTAssertTrue(result.survivedReDoS)
        XCTAssertTrue(result.conformsPathSanity)
        XCTAssertLessThanOrEqual(result.stressDurationMs, 5.0)
        XCTAssertTrue(result.reason.contains("certified invariant"))
    }

    func testFalsePositiveRuleFailsImmediately() {
        let overlyBroadRule = DeclarativeMinedRule(
            id: "rule-overly-broad-functions",
            summary: "Rule that triggers on standard function declarations",
            pattern: "\\bfunc\\s+[a-zA-Z0-9_]+\\b",
            message: "All functions flagged",
            fix: "//",
            grade: "warning",
            targetFileExtensions: ["swift"],
            excludePathPatterns: ["/Tests/", "/Fixtures/"]
        )

        let engine = DreamSimulatorEngine()
        let result = engine.simulateDream(candidate: overlyBroadRule)

        XCTAssertFalse(result.passed)
        XCTAssertGreaterThan(result.falsePositiveCount, 0)
        XCTAssertTrue(result.reason.contains("false positive"))
    }

    func testReDoSVulnerabilityRejectedByStressSLA() {
        let redosRule = DeclarativeMinedRule(
            id: "rule-catastrophic-backtracking",
            summary: "Vulnerable regex with nested quantifiers",
            pattern: "(a+)+$",
            message: "Catastrophic backtracking vulnerability",
            fix: "//",
            grade: "error",
            targetFileExtensions: ["swift"],
            excludePathPatterns: ["/Tests/", "/Fixtures/"]
        )

        let engine = DreamSimulatorEngine()
        let result = engine.simulateDream(candidate: redosRule)

        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.survivedReDoS)
        XCTAssertTrue(result.reason.contains("ReDoS vulnerability detected"))
    }

    func testPathSanityRejectsMissingExclusionPaths() {
        let ruleMissingExclusions = DeclarativeMinedRule(
            id: "rule-missing-exclusions",
            summary: "Rule without test and fixture exclusion patterns",
            pattern: "\\bDispatchQueue\\.sync\\b",
            message: "Missing boundary checks",
            fix: "//",
            grade: "observation",
            targetFileExtensions: ["swift"],
            excludePathPatterns: []
        )

        let engine = DreamSimulatorEngine()
        let result = engine.simulateDream(candidate: ruleMissingExclusions)

        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.conformsPathSanity)
        XCTAssertTrue(result.reason.contains("Pre-validation path sanity violation"))
    }

    func testPathSanityRejectsEmptyTargetFileExtensions() {
        let ruleMissingExtensions = DeclarativeMinedRule(
            id: "rule-missing-extensions",
            summary: "Rule without target file extensions",
            pattern: "\\bDispatchQueue\\.sync\\b",
            message: "Missing target extensions",
            fix: "//",
            grade: "observation",
            targetFileExtensions: [],
            excludePathPatterns: ["/Tests/", "/Fixtures/"]
        )

        let engine = DreamSimulatorEngine()
        let result = engine.simulateDream(candidate: ruleMissingExtensions)

        XCTAssertFalse(result.passed)
        XCTAssertFalse(result.conformsPathSanity)
        XCTAssertTrue(result.reason.contains("Target file extensions must not be empty"))
    }

    func testSleepCycleOrchestratorConsolidationAndQuarantine() {
        let orchestrator = SleepCycleOrchestrator()

        let validRule = DeclarativeMinedRule(
            id: "rule-valid-candidate",
            summary: "Valid rule targeting DispatchQueue.sync",
            pattern: "\\bDispatchQueue\\.sync\\b",
            message: "Avoid sync dispatch",
            fix: "Task { ... }",
            grade: "observation",
            targetFileExtensions: ["swift"],
            excludePathPatterns: ["/Tests/", "/Fixtures/"]
        )

        let badFpRule = DeclarativeMinedRule(
            id: "rule-bad-fp-candidate",
            summary: "False positive rule targeting struct keyword",
            pattern: "\\bstruct\\s+",
            message: "Flagging struct definitions",
            fix: "//",
            grade: "warning",
            targetFileExtensions: ["swift"],
            excludePathPatterns: ["/Tests/", "/Fixtures/"]
        )

        let validEval = orchestrator.evaluateRuleForConsolidation(candidate: validRule)
        XCTAssertTrue(validEval.promoted)
        XCTAssertTrue(validEval.result.passed)
        XCTAssertEqual(validEval.result.falsePositiveCount, 0)
        XCTAssertTrue(validEval.result.survivedReDoS)

        let badEval = orchestrator.evaluateRuleForConsolidation(candidate: badFpRule)
        XCTAssertFalse(badEval.promoted)
        XCTAssertFalse(badEval.result.passed)
        XCTAssertGreaterThan(badEval.result.falsePositiveCount, 0)
    }

    func testCounterfactualBranchSimulationWinnerSelection() {
        let engine = DreamSimulatorEngine()

        let episode = WakeEpisodeRecord(
            agentId: "agent-worker-2",
            conversationId: "conv-dream-test-01",
            targetFile: "Sources/Core/Worker.swift",
            durationMs: 42.0,
            intentSentence: "Resolve synchronous blocking in background worker",
            hypothesis: "DispatchQueue.sync blocks threads",
            observedAnomaly: "Main thread latency spike",
            ambiguity: CognitiveAmbiguityProfile(
                confidenceScore: 0.65,
                competingHypotheses: [
                    "DispatchQueue.sync causes thread pool starvation",
                    "Task.sleep delay causes timeout"
                ],
                intuitiveSmell: "Possible deadlocks on background queues",
                hesitationCount: 2,
                unresolvedQuestions: ["Should we switch to structured concurrency?"]
            )
        )

        let res = engine.simulateCounterfactualBranches(episode: episode)
        XCTAssertNotNil(res.winningRule)
        XCTAssertNil(res.failureRecord)
        XCTAssertFalse(res.branches.isEmpty)
        XCTAssertTrue(res.branches.contains { $0.isWinner })
    }
}
