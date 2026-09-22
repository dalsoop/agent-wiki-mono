import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

private func makeStore() -> (LedgerStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("alias-test-\(UUID().uuidString)")
    return (LedgerStore(root: root), root)
}

@Suite struct AliasTagResolverTests {
    @Test func resolvesObjectByAliasTagBothIndexAndScan() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let onboarding = try store.publish(
            author: "human:yun-jeonghan",
            title: "본문: 온보딩 · START HERE",
            type: "note",
            body: "# 온보딩 안내\n첫 세션은 여기서 시작.",
            now: Date(timeIntervalSince1970: 1_000),
            extras: LedgerPublishExtras(tags: ["onboarding", "seed", "alias:온보딩", "alias:START"])
        )

        let objects = store.scan()
        #expect(objects.count == 1)

        // 1) 스캔 폴백 (index.db 없음)
        let scannedCandidates = store.resolveCandidates(objects, query: "온보딩")
        #expect(scannedCandidates.map(\.id) == [onboarding.id])

        // 대소문자 무시 (START, start)
        #expect(store.resolveCandidates(objects, query: "START").map(\.id) == [onboarding.id])
        #expect(store.resolveCandidates(objects, query: "start").map(\.id) == [onboarding.id])

        // alias: 접두어를 붙여서 검색해도 해석
        #expect(store.resolveCandidates(objects, query: "alias:온보딩").map(\.id) == [onboarding.id])

        // 2) SQLite 인덱스 기반 검색
        let index = LedgerIndex(root: root)
        index.ensureFresh(objectsDir: root.appendingPathComponent("objects"))

        #expect(index.resolveIDs("온보딩") == [onboarding.id])
        #expect(index.resolveIDs("START") == [onboarding.id])
        #expect(index.resolveIDs("start") == [onboarding.id])
        #expect(index.resolveIDs("alias:온보딩") == [onboarding.id])
    }

    @Test func searchPriorityOrder() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        // 우선순위 2: 제목 정확 일치 객체
        let objExactTitle = try store.publish(
            author: "agent",
            title: "가이드",
            type: "note",
            body: "정확한 제목 가이드",
            now: Date(timeIntervalSince1970: 1_000)
        )

        // 우선순위 3: alias 태그 일치 객체
        let objAlias = try store.publish(
            author: "agent",
            title: "본문: 종합 안내서",
            type: "note",
            body: "별칭 가이드",
            now: Date(timeIntervalSince1970: 2_000),
            extras: LedgerPublishExtras(tags: ["alias:가이드"])
        )

        // 우선순위 4: 제목 접두 일치 객체
        let objTitlePrefix = try store.publish(
            author: "agent",
            title: "가이드북 상세",
            type: "note",
            body: "제목 접두 일치",
            now: Date(timeIntervalSince1970: 3_000)
        )

        // 우선순위 5: 제목 부분 일치 객체
        let objTitleSubstring = try store.publish(
            author: "agent",
            title: "상세 가이드북",
            type: "note",
            body: "제목 부분 일치",
            now: Date(timeIntervalSince1970: 4_000)
        )

        let index = LedgerIndex(root: root)
        index.ensureFresh(objectsDir: root.appendingPathComponent("objects"))
        let objects = store.scan()

        // 1. "가이드" 검색 -> 제목 정확 일치가 alias 나 접두 일치보다 우선
        #expect(index.resolveIDs("가이드") == [objExactTitle.id])
        #expect(store.resolveCandidates(objects, query: "가이드").map(\.id) == [objExactTitle.id])

        // 2. objExactTitle 제외 시 -> alias 태그 일치가 제목 접두/부분 일치보다 우선
        let remainingObjectsWithoutExact = objects.filter { $0.id != objExactTitle.id }
        #expect(store.resolveCandidates(remainingObjectsWithoutExact, query: "가이드").map(\.id) == [objAlias.id])

        // 3. objAlias 도 제외 시 -> 제목 접두 일치가 부분 일치보다 우선
        let remainingWithoutAlias = remainingObjectsWithoutExact.filter { $0.id != objAlias.id }
        #expect(store.resolveCandidates(remainingWithoutAlias, query: "가이드").map(\.id) == [objTitlePrefix.id])

        // 4. ID 접두어는 제목이나 alias보다 최우선
        let idPrefix = String(objTitleSubstring.id.prefix(8))
        #expect(index.resolveIDs(idPrefix) == [objTitleSubstring.id])
        #expect(store.resolveCandidates(objects, query: idPrefix).map(\.id) == [objTitleSubstring.id])
    }
}
