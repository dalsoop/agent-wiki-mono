import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// 파생 인덱스 신선도 계약 — "발행했는데 검색에 안 잡힌다" 회귀.
///
/// 실사고(2026-08-04): `publish` 로 올린 객체가 `show` 로는 열리는데 `search` 는
/// **(결과 없음)** 이었다. 원인은 인덱스 미갱신인데, 분류(`--domain/--kind/
/// --knowledge`) 누락으로 오진돼 "분류해야 검색된다" 는 잘못된 규칙이 생겼다.
/// 실제로는 미분류 객체도 FTS 에 정상적으로 잡힌다 — 아래 첫 테스트가 그 계약.
///
/// 신선도 판정도 파일 **개수** 비교뿐이라, 개수가 같으면 stale 을 통과시켰다.
@Suite struct LedgerIndexFreshnessTests {
    private func makeWorld() -> (root: URL, store: LedgerStore, objectsDir: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-fresh-\(UUID())", isDirectory: true)
        return (root, LedgerStore(root: root), root.appendingPathComponent("objects"))
    }

    /// 분류는 검색 **도달**의 조건이 아니다 — 정밀도(필터·태그)용이다.
    @Test func unclassifiedObjectIsStillSearchable() throws {
        let world = makeWorld()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let object = try world.store.publish(
            author: "test", title: "근거: 미분류 도달 시험", type: "concept",
            body: "분류 스탬프 없이 발행한다.")

        let index = LedgerIndex(root: world.root)
        _ = index.sync(objectsDir: world.objectsDir)
        let hits = index.search("미분류 도달")
        #expect(hits.contains { $0.id == object.id })
        // 분류가 없다는 것도 함께 못박는다 — 그런데도 찾아진다는 게 요점.
        #expect(hits.first { $0.id == object.id }?.domain == nil)
    }

    /// 개수가 같아도 뒤처졌으면 stale 이어야 한다(제자리 개정).
    @Test func inPlaceEditIsDetectedThoughCountUnchanged() throws {
        let world = makeWorld()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let object = try world.store.publish(
            author: "test", title: "근거: 제자리 개정", type: "concept", body: "원래 본문")

        let index = LedgerIndex(root: world.root)
        _ = index.sync(objectsDir: world.objectsDir)
        #expect(index.isStale(objectsDir: world.objectsDir) == false)

        // 파일 수를 그대로 둔 채 본문만 늘린다.
        let path = try #require(index.pathFor(id: object.id))
        let url = URL(fileURLWithPath: path)
        let text = try String(contentsOf: url, encoding: .utf8)
        try (text + "\n추가된토큰 appended-token\n").write(to: url, atomically: true, encoding: .utf8)

        let census = index.diskCensus(objectsDir: world.objectsDir)
        #expect(census.count == index.objectCount())  // 개수는 같다
        #expect(index.isStale(objectsDir: world.objectsDir))  // 그래도 stale
    }

    /// 추가 1건 + 삭제 1건이 겹쳐도 개수가 같아 stale 을 놓치던 경우.
    @Test func addAndRemoveKeepingCountIsDetected() throws {
        let world = makeWorld()
        defer { try? FileManager.default.removeItem(at: world.root) }
        let first = try world.store.publish(
            author: "test", title: "근거: 사라질 객체", type: "concept", body: "본문 하나")

        let index = LedgerIndex(root: world.root)
        _ = index.sync(objectsDir: world.objectsDir)
        let firstPath = try #require(index.pathFor(id: first.id))

        let second = try world.store.publish(
            author: "test", title: "근거: 새로 온 객체", type: "concept", body: "본문 둘")
        try FileManager.default.removeItem(atPath: firstPath)

        #expect(index.diskCensus(objectsDir: world.objectsDir).count == index.objectCount())
        #expect(index.isStale(objectsDir: world.objectsDir))

        index.ensureFresh(objectsDir: world.objectsDir)
        #expect(index.search("새로 온 객체").contains { $0.id == second.id })
        #expect(index.search("사라질 객체").isEmpty)
    }
}
