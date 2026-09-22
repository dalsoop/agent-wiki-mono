import XCTest
@testable import AgentPolicyKit

final class AgentPolicyStoreTests: XCTestCase {
    private func store() -> (AgentPolicyStore, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agent-policy-\(UUID().uuidString)")
        return (AgentPolicyStore(root: root), root)
    }

    /// 정책이 없으면 아무것도 막지 않는다 — 설치만으로 함대가 멈추면 안 된다.
    func testMissingPolicyAllowsEverything() {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertTrue(store.verdict(spentTodayUSD: 999).isAllowed)
    }

    /// 전체 정지는 무엇보다 먼저다 — 총액이 남아 있어도 막는다.
    func testPauseBeatsEverything() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.setPaused(true, reason: "폭주 조사 중")
        let verdict = store.verdict(spentTodayUSD: 0)
        XCTAssertFalse(verdict.isAllowed)
        XCTAssertEqual(verdict.reason, "함대 정지 중 — 폭주 조사 중")
    }

    /// 파일이라 프로세스를 넘어 유지되고, 풀면 즉시 통과한다.
    func testPauseIsDurableAndReversible() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.setPaused(true, reason: "x")
        XCTAssertTrue(AgentPolicyStore(root: root).isPaused)   // 새 인스턴스도 본다
        try store.setPaused(false)
        XCTAssertFalse(AgentPolicyStore(root: root).isPaused)
    }

    func testDailyCapBlocksWhenReached() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(AgentPolicy(dailyUSD: 10))
        XCTAssertTrue(store.verdict(spentTodayUSD: 9.99).isAllowed)
        XCTAssertNotNil(store.verdict(spentTodayUSD: 10).reason)
    }

    func testConcurrencyCap() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(AgentPolicy(maxConcurrent: 2))
        XCTAssertTrue(store.verdict(spentTodayUSD: 0, running: 1).isAllowed)
        XCTAssertNotNil(store.verdict(spentTodayUSD: 0, running: 2).reason)
    }

    func testRoundTrip() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(AgentPolicy(dailyUSD: 5, maxConcurrent: 3,
                                   forbiddenPaths: ["/etc"], note: "야간"))
        let loaded = store.load()
        XCTAssertEqual(loaded.dailyUSD, 5)
        XCTAssertEqual(loaded.forbiddenPaths, ["/etc"])
        XCTAssertEqual(loaded.note, "야간")
    }

    /// 깨진 파일에 죽지 않는다 — 정책이 깨졌다고 함대가 서면 안 된다.
    func testCorruptPolicyFallsBackToUnrestricted() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.policyURL)
        XCTAssertEqual(store.load(), .unrestricted)
        XCTAssertTrue(store.verdict(spentTodayUSD: 1).isAllowed)
    }

    func testMissingToolPolicyAllowsHomeFind() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(AgentPolicy(dailyUSD: 1))
        XCTAssertTrue(store.toolVerdict(AgentToolCall(command: "find $HOME -maxdepth 2")).isAllowed)
    }

    func testDefaultToolPolicyBlocksHomeFind() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(AgentPolicy(tool: .default))
        setenv("HOME", NSHomeDirectory(), 1)
        XCTAssertFalse(store.toolVerdict(AgentToolCall(command: "find $HOME -maxdepth 5")).isAllowed)
        let home = NSHomeDirectory()
        XCTAssertFalse(store.toolVerdict(AgentToolCall(command: "find \(home) -maxdepth 5")).isAllowed)
        XCTAssertTrue(store.toolVerdict(AgentToolCall(command: "find \(home)/Documents/WORK -name x")).isAllowed)
        XCTAssertTrue(store.toolVerdict(AgentToolCall(command: "agy --conversation abc")).isAllowed)
    }

    func testSessionHuntBlocksThreeRoots() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(AgentPolicy(tool: .default))
        let home = NSHomeDirectory()
        setenv("HOME", home, 1)
        let cmd = "rg uuid \(home)/.codex \(home)/.claude \(home)/.grok"
        XCTAssertFalse(store.toolVerdict(AgentToolCall(command: cmd)).isAllowed)
    }

    func testToolPolicyRoundTrip() throws {
        let (store, root) = self.store()
        defer { try? FileManager.default.removeItem(at: root) }
        try store.save(AgentPolicy(tool: .default))
        XCTAssertEqual(store.load().tool?.denyHomeRootSearch, true)
        XCTAssertEqual(store.load().tool?.sessionHuntMinRoots, 3)
    }
}
