import XCTest
import AgentSessionKit
@testable import AgentContextKit

/// 활성화 인덱스는 transcript 의 mtime·size 로 무효화된다. 둘 중 하나라도 다르면 미스다 —
/// 오래된 인덱스를 적중으로 돌려주면 "스킬 안 쓰임" 판정이 옛 세션 내용으로 나온다.
final class ActivationIndexCacheTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("activation-index-\(UUID().uuidString)").path
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root) { try FileManager.default.removeItem(atPath: root) }
    }

    private func sample(mtime: TimeInterval, size: Int) -> SessionActivationIndex {
        SessionActivationIndex(
            sessionId: "s-1", tool: "claude", cwd: "/proj", lastActive: Date(timeIntervalSince1970: 1_700_000_000),
            activations: [Activation(kind: .skill, name: "agent-wiki", at: 3, thought: "why", mdPath: "/skills/agent-wiki/SKILL.md")],
            sourceMTime: mtime, sourceSize: size)
    }

    func testRoundTripHitsOnSameSourceKey() {
        let cache = ActivationIndexCache(root: root)
        cache.save(sample(mtime: 10, size: 200))
        let hit = cache.load(sessionId: "s-1", sourceMTime: 10, sourceSize: 200)
        XCTAssertEqual(hit, sample(mtime: 10, size: 200))
        XCTAssertEqual(hit?.activations.first?.name, "agent-wiki")
    }

    func testMissesWhenTranscriptChanged() {
        let cache = ActivationIndexCache(root: root)
        cache.save(sample(mtime: 10, size: 200))
        XCTAssertNil(cache.load(sessionId: "s-1", sourceMTime: 11, sourceSize: 200), "mtime 가 다르면 미스")
        XCTAssertNil(cache.load(sessionId: "s-1", sourceMTime: 10, sourceSize: 201), "size 가 다르면 미스")
        XCTAssertNil(cache.load(sessionId: "other", sourceMTime: 10, sourceSize: 200), "없는 세션은 미스")
    }

    func testLedgerWiresCacheUnderHome() {
        let ledger = Ledger(home: root)
        XCTAssertEqual(ledger.activationIndexCache.root, root + "/.agent-session-context-ledger/activation-index")
    }
}
