import XCTest
@testable import LoopLedgerKit

final class LoopLedgerTests: XCTestCase {
    func testDetailJSONPublishesStableTopLevelID() throws {
        let node = LoopNode(
            id: "game/prologue",
            path: "/tmp/loops/game/prologue",
            name: "prologue",
            isLoop: true,
            isRelease: false,
            children: []
        )
        let detail = LoopDetail(
            node: node,
            definition: nil,
            state: nil,
            rounds: [],
            feedback: [],
            release: nil,
            diagnostics: []
        )

        let data = try JSONEncoder().encode(detail)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["id"] as? String, "game/prologue")
    }

    private var root: String!

    override func setUpWithError() throws {
        root = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("loop-ledger-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func testScansNestedLoopsAndDecodesLegacyRoundAlias() throws {
        try put("game/prologue/loop.json", """
        {"id":"game/prologue","goal":"프롤로그 완주","gate":8,"maxRounds":3,
         "roster":[{"role":"maker","does":"구현"},{"role":"judge-A","does":"기술 검수"}]}
        """)
        try put("game/prologue/state.json", """
        {"status":"converged","round":1,"lastScore":9.0}
        """)
        try put("game/prologue/rounds.jsonl", """
        {"round":1,"phase":"r1-A","role":"judge-A","score":3,"blockers":[]}
        """)

        let snapshot = LoopLedger(root: root).snapshot()
        let detail = try XCTUnwrap(snapshot.detail(id: "game/prologue"))

        XCTAssertEqual(detail.definition?.goal, "프롤로그 완주")
        XCTAssertEqual(detail.state?.currentRound, 1)
        XCTAssertEqual(detail.state?.lastScore, 9.0)
        XCTAssertEqual(detail.rounds.first?.phase, "r1-A")
        XCTAssertEqual(detail.definition?.roster.count, 2)
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
    }

    func testCorruptLoopDoesNotHideHealthySibling() throws {
        try put("game/healthy/loop.json", "{\"id\":\"game/healthy\",\"goal\":\"정상\"}")
        try put("game/broken/loop.json", "{not-json")

        let snapshot = LoopLedger(root: root).snapshot()

        XCTAssertNotNil(snapshot.detail(id: "game/healthy"))
        XCTAssertNotNil(snapshot.detail(id: "game/broken"))
        XCTAssertEqual(snapshot.diagnostics.count, 1)
        XCTAssertTrue(snapshot.diagnostics[0].path.hasSuffix("game/broken/loop.json"))
    }

    func testLegacyDefinitionWithoutIDUsesLedgerPath() throws {
        try put("legacy/quality/loop.json", "{\"slug\":\"legacy\",\"kind\":\"quality\",\"roster\":[{\"role\":\"checker\"}]}")

        let snapshot = LoopLedger(root: root).snapshot()
        let detail = try XCTUnwrap(snapshot.detail(id: "legacy/quality"))

        XCTAssertEqual(detail.definition?.id, "legacy/quality")
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
    }

    func testProjectSummaryRollsUpRunningBlockedAndConverged() throws {
        try makeLoop("game/a", state: "{\"status\":\"running\",\"currentRound\":2}")
        try makeLoop("game/b", state: "{\"status\":\"budget_exhausted\"}")
        try makeLoop("game/c", state: "{\"status\":\"converged\"}")

        let project = try XCTUnwrap(LoopLedger(root: root).snapshot().projects.first)

        XCTAssertEqual(project.id, "game")
        XCTAssertEqual(project.loopCount, 3)
        XCTAssertEqual(project.runningCount, 1)
        XCTAssertEqual(project.blockedCount, 1)
        XCTAssertEqual(project.convergedCount, 1)
        XCTAssertEqual(project.rollupStatus, "budget_exhausted")
    }

    func testAppendFeedbackPersistsPortableJSONLine() throws {
        try makeLoop("game/a", state: "{\"status\":\"running\"}")
        let ledger = LoopLedger(root: root)

        try ledger.appendFeedback(
            loopID: "game/a",
            artifact: "evidence/r1.png",
            verdict: "negative",
            comment: "버튼이 잘림",
            at: Date(timeIntervalSince1970: 0)
        )

        let detail = try XCTUnwrap(ledger.detail(id: "game/a"))
        XCTAssertEqual(detail.feedback.count, 1)
        XCTAssertEqual(detail.feedback[0].artifact, "evidence/r1.png")
        XCTAssertEqual(detail.feedback[0].verdict, "negative")
        XCTAssertEqual(detail.feedback[0].by, "human")
    }

    func testOpenRequestRoundTripSelectsExactLoop() throws {
        let store = LoopOpenRequestStore(root: root)

        try store.write(loopID: "game/prologue", at: Date(timeIntervalSince1970: 0))

        XCTAssertEqual(try store.read()?.loopID, "game/prologue")
    }

    private func makeLoop(_ id: String, state: String) throws {
        try put("\(id)/loop.json", "{\"id\":\"\(id)\",\"goal\":\"goal\"}")
        try put("\(id)/state.json", state)
    }

    private func put(_ relative: String, _ contents: String) throws {
        let path = (root as NSString).appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true)
        try contents.data(using: .utf8)!.write(to: URL(fileURLWithPath: path))
    }
}
