import Foundation
import Testing
@testable import AgentRegistryKit

@Suite("에이전트 정의 이력")
struct AgentVersionHistoryTests {
    private func tempRegistry() -> AgentRegistry {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("agver-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        return AgentRegistry(url: dir.appendingPathComponent("agents.json"))
    }

    private func def(id: String, model: String) -> AgentDef {
        AgentDef(identity: .init(id: id, name: id), runtime: .init(agent: "grok", model: model))
    }

    @Test("정의를 고치면 이력이 쌓인다 — 덮어써도 어제 정의를 되찾을 수 있다")
    func historyAccumulates() throws {
        let r = tempRegistry()
        try r.upsert(def(id: "a", model: "m1"))
        try r.upsert(def(id: "a", model: "m2"))
        #expect(r.historyCount(id: "a") == 2)
        #expect(r.versionTag(id: "a") == "a@v2")
        // 명부 자체는 최신만 — 이력이 과거를 진다.
        #expect(r.load().first?.model == "m2")
    }

    @Test("버전은 id 별로 센다")
    func perIDVersioning() throws {
        let r = tempRegistry()
        try r.upsert(def(id: "a", model: "m"))
        try r.upsert(def(id: "b", model: "m"))
        try r.upsert(def(id: "a", model: "m2"))
        #expect(r.versionTag(id: "a") == "a@v2")
        #expect(r.versionTag(id: "b") == "b@v1")
    }

    @Test("삭제도 이력에 남는다 — 지운 캐릭터의 실적 귀속이 끊기지 않게")
    func removeIsRecorded() throws {
        let r = tempRegistry()
        try r.upsert(def(id: "a", model: "m"))
        try r.remove(id: "a")
        #expect(r.historyCount(id: "a") == 2)
        #expect(r.load().isEmpty)
    }

    @Test("이력 없는 id 는 v0 — 기록 전 정의라고 말한다")
    func unknownIsV0() {
        #expect(tempRegistry().versionTag(id: "ghost") == "ghost@v0")
    }
}
