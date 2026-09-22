import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

/// world 사람용 Display 이름 — 등록에 display 가 없으면 slug 그대로, 있으면 뒤에 덧붙여 표기.
@Suite struct WorldDisplayNameTests {
    @Test func ledgerWorldDisplayDefaultsToNilAndRoundTrips() throws {
        let bare = try JSONDecoder().decode(
            LedgerWorld.self,
            from: Data(#"{"name":"gujo-wiki","rootPath":"/tmp/w"}"#.utf8))
        #expect(bare.display == nil)

        let named = LedgerWorld(name: "gujo-wiki", rootPath: "/tmp/w", display: "구조 공유 위키")
        let decoded = try JSONDecoder().decode(LedgerWorld.self, from: JSONEncoder().encode(named))
        #expect(decoded.display == "구조 공유 위키")
    }

    @Test func wikiListItemsCarryDisplayDefaultingToSlug() {
        let items = WikiWorldPresentation.listItems(
            worlds: [
                LedgerWorld(name: "gujo-wiki", rootPath: "/tmp/gujo-wiki", display: "구조 공유 위키"),
                LedgerWorld(name: "plain", rootPath: "/tmp/plain-wiki"),
            ],
            selectedName: "gujo-wiki")
        #expect(items.first { $0.name == "gujo-wiki" }?.display == "구조 공유 위키")
        #expect(items.first { $0.name == "plain" }?.display == "plain")
    }

    @Test func wikiPlainTextAppendsDisplayWithoutBreakingBaseFormat() {
        let items = WikiWorldPresentation.listItems(
            worlds: [
                LedgerWorld(name: "gujo-wiki", rootPath: "/tmp/gujo-wiki", display: "구조 공유 위키"),
                LedgerWorld(name: "plain", rootPath: "/tmp/plain-wiki"),
            ],
            selectedName: nil)
        let text = WikiWorldPresentation.plainText(items: items)
        #expect(text.contains("[gujo-wiki]  /tmp/gujo-wiki  display=구조 공유 위키"))
        // display 미등록은 기존 포맷 그대로 — 줄 끝이 rootPath 로 끝난다.
        #expect(text.contains("[plain]  /tmp/plain-wiki\n") || text.hasSuffix("[plain]  /tmp/plain-wiki"))
        #expect(!text.contains("display=plain"))
    }

    @Test func boundWorldListShowsDisplayAndDefaultsToSlug() {
        let catalog = WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/gujo-wiki", display: "구조 공유 위키"),
            BoundWorld(name: "plain", rootPath: "/tmp/plain-wiki"),
        ])
        let items = WorldListPresentation.items(catalog: catalog, selectedName: "gujo-wiki")
        #expect(items.first { $0.name == "gujo-wiki" }?.display == "구조 공유 위키")
        #expect(items.first { $0.name == "plain" }?.display == "plain")

        let text = WorldListPresentation.plainText(items: items)
        #expect(text.contains("display=구조 공유 위키"))
        #expect(!text.contains("display=plain"))
    }

    @Test func worldMutationAddingKeepsDisplay() throws {
        let file = BoundLedgerFile(worlds: [])
        let next = try WorldMutation.adding(
            to: file, name: "w", path: "/tmp/w", layer: nil, parent: nil, display: "표시명").get()
        #expect(next.effectiveWorlds.first?.display == "표시명")
    }

    @Test func replacingWorldsPreservesDisplay() {
        let file = BoundLedgerFile(worlds: [
            BoundWorld(name: "w", rootPath: "/tmp/w", display: "표시명")
        ])
        let next = WorldConfigStore.replacingWorlds(
            file, with: [BoundWorld(name: "w", rootPath: "/tmp/w2")])
        #expect(next.effectiveWorlds.first?.display == "표시명")
    }

    @Test func catalogMergingOverlaysConfigDisplay() {
        let config = LedgerConfig(worlds: [
            LedgerWorld(name: "w", rootPath: "/tmp/w", display: "설정 표시명")
        ])
        let file = BoundLedgerFile(worlds: [BoundWorld(name: "w", rootPath: "/tmp/w")])
        let catalog = WorldCatalogLoader.merging(file: file, config: config)
        #expect(catalog.world(named: "w")?.display == "설정 표시명")
    }
}

/// scene evidence — 결정(decision) 객체에 역링크된 독립 객체.
/// 역링크는 evidence 쪽 cite(rel `of`)와 본문 `of:` 필드로만 — 결정 객체는 건드리지 않는다.
@Suite struct SceneEvidenceTests {
    private func makeWorld() -> LedgerStore {
        LedgerStore(root: FileManager.default.temporaryDirectory
            .appendingPathComponent("kbw-scene-\(UUID())", isDirectory: true))
    }

    @Test func publishesSceneEvidenceWithBacklinkCite() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let decision = try store.publish(
            author: "test", title: "결정: 룸 체제", type: "decision", body: "결정 본문")

        let cite = try PublishCompleteness.sceneEvidenceLink(
            of: decision.id, objects: store.scan()).get()
        #expect(cite == LedgerObject.Cite(id: decision.id, rel: "of"))

        let body = PublishCompleteness.sceneEvidenceBody(of: decision.id, body: "현장 로그")
        #expect(PublishCompleteness.parseSceneEvidenceOf(body) == decision.id)

        let evidence = try store.publish(
            author: "test", title: "scene: 룸 체제 근거",
            type: PublishCompleteness.sceneEvidenceType, body: body,
            extras: LedgerPublishExtras(cites: [cite]))

        // 발행된 객체를 다시 읽어 역링크 cite 와 of: 필드가 남았는지 본다.
        let stored = store.scan().first { $0.id == evidence.id }
        #expect(stored?.cites.contains(LedgerObject.Cite(id: decision.id, rel: "of")) == true)
        #expect(PublishCompleteness.parseSceneEvidenceOf(stored?.body ?? "") == decision.id)
        // 결정 객체는 그대로다(역링크는 evidence 쪽에만).
        let decisionAfter = store.scan().first { $0.id == decision.id }
        #expect(decisionAfter?.cites.isEmpty == true)
    }

    @Test func rejectsOfWithoutExistingDecision() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let result = PublishCompleteness.sceneEvidenceLink(of: "없는-id", objects: store.scan())
        #expect(throws: PublishCompleteness.Failure.self) { try result.get() }
    }

    @Test func rejectsOfTargetThatIsNotADecision() throws {
        let store = makeWorld()
        defer { try? FileManager.default.removeItem(at: store.root) }
        let note = try store.publish(
            author: "test", title: "근거: 그냥 근거", type: "evidence", body: "본문")
        let result = PublishCompleteness.sceneEvidenceLink(of: note.id, objects: store.scan())
        #expect(throws: PublishCompleteness.Failure.self) { try result.get() }
    }

    /// 완결성 — cite 1 이상만 요구하고, 결정용 생략표 요구는 적용하지 않는다.
    @Test func completenessRequiresOneCiteOnly() {
        #expect(PublishCompleteness.validateSceneEvidence(cites: []) != nil)
        #expect(PublishCompleteness.validateSceneEvidence(
            cites: [LedgerObject.Cite(id: "x", rel: "of")]) == nil)
    }

    /// scene-evidence 는 처리 기록이라 분류 기준선 게이트 대상이 아니다.
    @Test func sceneEvidenceIsExemptFromClassificationBaseline() {
        let probe = LedgerObject(
            id: "0", published: Date(), author: "test",
            type: PublishCompleteness.sceneEvidenceType, body: "of: x")
        #expect(probe.isProcess)
    }

    @Test func sceneEvidenceBodyIsIdempotent() {
        let once = PublishCompleteness.sceneEvidenceBody(of: "abc", body: "본문")
        let twice = PublishCompleteness.sceneEvidenceBody(of: "abc", body: once)
        #expect(once == twice)
    }
}
