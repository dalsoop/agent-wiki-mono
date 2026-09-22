import XCTest
import AgentSessionKit
@testable import AgentContextKit

/// 스킬 신호 분류 — `invoked` 와 `loaded` 를 구분하고, 뭉텅이 읽기는 bulk 로 표시한다.
/// 실측(2026-09-03): 이 구분이 없어서 7일·90일 어느 범위에서도 "안 쓰인 스킬" 이 0 이었다.
final class SkillSignalClassificationTests: XCTestCase {
    private func loaded(_ name: String, at: Int = 0) -> Activation {
        Activation(kind: .skill, name: name, at: at, thought: nil, mdPath: nil, source: .loaded)
    }

    private func invoked(_ name: String, at: Int = 0) -> Activation {
        Activation(kind: .skill, name: name, at: at, thought: nil, mdPath: nil, source: .invoked)
    }

    func testFewLoadsStayCountable() {
        let acts = (0..<5).map { loaded("skill-\($0)", at: $0) }
        let marked = Ledger.markBulkLoads(acts)
        XCTAssertTrue(marked.allSatisfy { !$0.bulk })
    }

    func testBulkLoadsAreMarkedButInvokedSurvive() {
        var acts = (0..<Ledger.bulkLoadThreshold).map { loaded("skill-\($0)", at: $0) }
        acts.append(invoked("agent-wiki", at: 999))
        acts.append(Activation(kind: .subagent, name: "Explore", at: 1000, thought: nil, mdPath: nil))
        let marked = Ledger.markBulkLoads(acts)
        let bulkLoads = marked.filter { $0.source == .loaded && $0.kind == .skill }
        XCTAssertTrue(bulkLoads.allSatisfy(\.bulk), "loaded 는 전부 bulk")
        XCTAssertFalse(marked.first { $0.name == "agent-wiki" }!.bulk, "invoked 는 건드리지 않는다")
        XCTAssertFalse(marked.first { $0.kind == .subagent }!.bulk, "서브에이전트는 대상이 아니다")
    }

    func testThresholdCountsDistinctNamesNotCalls() {
        // 같은 스킬을 30번 읽은 건 뭉텅이가 아니다 — 서로 다른 이름 수로 판정한다.
        let acts = (0..<30).map { loaded("agent-wiki", at: $0) }
        XCTAssertTrue(Ledger.markBulkLoads(acts).allSatisfy { !$0.bulk })
    }

    /// `source`·`bulk` 가 없던 캐시 JSON 도 읽힌다(기본 loaded·false).
    func testDecodesLegacyActivationWithoutNewFields() throws {
        let json = #"{"kind":"skill","name":"agent-wiki","at":3,"thought":null,"mdPath":null}"#
        let a = try JSONDecoder().decode(Activation.self, from: Data(json.utf8))
        XCTAssertEqual(a.source, .loaded)
        XCTAssertFalse(a.bulk)
    }

    func testRoundTripKeepsSourceAndBulk() throws {
        let a = invoked("agent-wiki", at: 7).markedBulk()
        let data = try JSONEncoder().encode(a)
        let back = try JSONDecoder().decode(Activation.self, from: data)
        XCTAssertEqual(back, a)
        XCTAssertEqual(back.source, .invoked)
        XCTAssertTrue(back.bulk)
    }

    /// 인덱스 규격이 오르면 옛 파일은 미스여야 한다 — 옛 분류로 만든 집계가 섞이지 않게.
    func testOldFormatVersionIsCacheMiss() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("activation-format-\(UUID().uuidString)").path
        defer { if FileManager.default.fileExists(atPath: root) { try? FileManager.default.removeItem(atPath: root) } }
        let cache = ActivationIndexCache(root: root)
        let stale = SessionActivationIndex(
            sessionId: "s", tool: "claude", cwd: "/p", lastActive: Date(),
            activations: [], sourceMTime: 1, sourceSize: 1,
            formatVersion: SessionActivationIndex.currentFormatVersion - 1)
        cache.save(stale)
        XCTAssertNil(cache.load(sessionId: "s", sourceMTime: 1, sourceSize: 1))
    }
}

/// agy 전사본에서 나온 문서 조각이 스킬 이름으로 올라오지 않는다.
final class SkillsLoadedNameHygieneTests: XCTestCase {
    func testRejectsMarkdownFragments() {
        let junk = [
            "cat /x/skills/AndroidAdbManager.app`)/SKILL.md",
            "read /x/skills/스킬 카드 카탈로그 — 파일 SSOT(agents.json,/SKILL.md",
            "cat /x/skills/| 고객 정본 표면 |/SKILL.md",
        ]
        for command in junk {
            XCTAssertTrue(SessionScan.skillsLoaded(in: command).isEmpty, command)
        }
    }

    func testAcceptsRealSkillDirectories() {
        XCTAssertEqual(SessionScan.skillsLoaded(in: "cat ~/.codex/skills/agent-wiki/SKILL.md").map(\.name),
                       ["agent-wiki"])
        XCTAssertEqual(SessionScan.skillsLoaded(in: "cat /w/.claude/skills/host_compile.gate/SKILL.md").map(\.name),
                       ["host_compile.gate"])
    }

    func testRequiresSkillsDirectoryInPath() {
        // 문서 디렉터리의 SKILL.md 는 스킬 로드가 아니다.
        XCTAssertTrue(SessionScan.skillsLoaded(in: "cat /repo/docs/guide/SKILL.md").isEmpty)
    }
}
