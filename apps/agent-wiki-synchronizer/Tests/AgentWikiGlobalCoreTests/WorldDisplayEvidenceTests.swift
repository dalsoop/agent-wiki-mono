import XCTest
import Foundation
import KnowledgeBaseWikiCore
@testable import AgentWikiGlobalCore

final class WorldDisplayEvidenceTests: XCTestCase {
    func testWorldDisplayRegistryMappings() {
        XCTAssertEqual(
            WorldDisplayRegistry.displayName(for: "gujo-wiki"),
            "조직 공유 원장 (Gujo Shared Ledger)"
        )
        XCTAssertEqual(
            WorldDisplayRegistry.displayName(for: "person-yun-jeonghan"),
            "윤정한 개인 주관 일지 (Jeonghan Personal Ledger)"
        )
        XCTAssertEqual(
            WorldDisplayRegistry.displayName(for: "gujo-wiki", explicitDisplay: "커스텀 이름"),
            "커스텀 이름"
        )
        XCTAssertEqual(
            WorldDisplayRegistry.displayName(for: "plain-slug"),
            "plain-slug"
        )
    }

    func testWorldListPresentationExposesDisplayNames() throws {
        let catalog = WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/gujo-wiki"),
            BoundWorld(name: "person-yun-jeonghan", rootPath: "/tmp/person-yun-jeonghan"),
            BoundWorld(name: "plain-slug", rootPath: "/tmp/plain"),
        ])
        let items = WorldListPresentation.items(catalog: catalog, selectedName: "gujo-wiki")

        let gujoItem = try XCTUnwrap(items.first { $0.name == "gujo-wiki" })
        XCTAssertEqual(gujoItem.displayName, "조직 공유 원장 (Gujo Shared Ledger)")
        XCTAssertEqual(gujoItem.display, "조직 공유 원장 (Gujo Shared Ledger)")

        let jeonghanItem = try XCTUnwrap(items.first { $0.name == "person-yun-jeonghan" })
        XCTAssertEqual(jeonghanItem.displayName, "윤정한 개인 주관 일지 (Jeonghan Personal Ledger)")
        XCTAssertEqual(jeonghanItem.display, "윤정한 개인 주관 일지 (Jeonghan Personal Ledger)")

        let plainItem = try XCTUnwrap(items.first { $0.name == "plain-slug" })
        XCTAssertEqual(plainItem.displayName, "plain-slug")
        XCTAssertEqual(plainItem.display, "plain-slug")

        let text = WorldListPresentation.plainText(items: items)
        XCTAssertTrue(text.contains("display=조직 공유 원장 (Gujo Shared Ledger)"))
        XCTAssertTrue(text.contains("display=윤정한 개인 주관 일지 (Jeonghan Personal Ledger)"))
        XCTAssertFalse(text.contains("display=plain-slug"))

        // JSON 직렬화/역직렬화 검증
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([WorldListJSONItem].self, from: data)
        XCTAssertEqual(decoded, items)
    }

    func testSceneEvidenceBacklinkExtractionAndResolution() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("wiki-scene-ev-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = LedgerStore(root: root)
        let decision = try store.publish(
            author: "agent",
            title: "결정: 룸 체제 도입",
            type: "decision",
            body: "결정 내용 본문"
        )
        XCTAssertFalse(decision.isSceneEvidence)

        let cite = try PublishCompleteness.sceneEvidenceLink(
            of: decision.id,
            objects: store.scan()
        ).get()

        let body = PublishCompleteness.sceneEvidenceBody(of: decision.id, body: "현장 로그 및 증적 데이터")
        let evidence = try store.publish(
            author: "agent",
            title: "scene: 룸 체제 현장 증거",
            type: PublishCompleteness.sceneEvidenceType,
            body: body,
            extras: LedgerPublishExtras(cites: [cite])
        )

        let scanned = store.scan()
        let evidenceObj = try XCTUnwrap(scanned.first { $0.id == evidence.id })
        XCTAssertTrue(evidenceObj.isSceneEvidence)

        // 단일 객체로부터 SceneEvidenceBacklink 추출
        let backlink = try XCTUnwrap(evidenceObj.sceneEvidenceBacklink)
        XCTAssertEqual(backlink.id, evidence.id)
        XCTAssertEqual(backlink.targetDecisionID, decision.id)
        XCTAssertEqual(backlink.rel, "of")
        XCTAssertEqual(backlink.author, "agent")
        XCTAssertEqual(backlink.title, "scene: 룸 체제 현장 증거")

        // store 에서 결정 ID 기준 scene evidence 역링크 객체 목록 조회
        let linksFromStore = store.sceneEvidences(forDecisionID: decision.id, in: scanned)
        XCTAssertEqual(linksFromStore.count, 1)
        XCTAssertEqual(linksFromStore.first?.id, evidence.id)

        // decision 객체에서 역링크 객체들 조회
        let linksFromDecision = decision.sceneEvidenceBacklinks(in: scanned)
        XCTAssertEqual(linksFromDecision.count, 1)
        XCTAssertEqual(linksFromDecision.first?.id, evidence.id)

        // Codable 왕복 검증
        let encoded = try JSONEncoder().encode(backlink)
        let decoded = try JSONDecoder().decode(SceneEvidenceBacklink.self, from: encoded)
        XCTAssertEqual(decoded, backlink)
    }
}
