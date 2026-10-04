import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// 공포 경로(T4) 시험 — 쓰기 게이트·범위 해석기·작성자/모델 기록·화면 편집·설정 보존·색인·승격.
/// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", docs/business-rules.md "agent-law(ledger 3)", 결정 0007.
/// 임시 디렉터리 루트만 쓴다.
@Suite struct AgentLawEnactPathTests {

    /// 임시 루트 하나에 전신(ledger 2 `gujo-wiki`), 공유 원장 `agent-law`, 테넌트 둘(형제)을 둔다.
    struct Fixture {
        let dir: URL
        let file: BoundLedgerFile
        var catalog: WorldBindingCatalog { WorldBindingCatalog(worlds: file.effectiveWorlds) }
        let predecessorObject: LedgerObject

        func target(_ name: String, device: String? = "mac", devices: [String] = ["mac"]) -> LawLedgerTarget {
            LawLedgerTarget(
                worldName: name, root: URL(fileURLWithPath: catalog.world(named: name)!.rootPath),
                catalog: catalog, registeredDevices: devices, currentDevice: device)
        }

        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    static func fixture() throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-law-enact-\(UUID().uuidString)", isDirectory: true)
        func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
        let legacy = LedgerStore(root: URL(fileURLWithPath: path("gujo-wiki")))
        let old = try legacy.publish(author: "agent:old", title: "결정: 전신 지식", body: "전신 본문 키워드")
        let file = BoundLedgerFile(
            worlds: [
                BoundWorld(name: "gujo-wiki", rootPath: path("gujo-wiki"), layer: "remoteShared"),
                BoundWorld(name: "agent-law", rootPath: path("law"), key: "law", predecessor: "gujo-wiki"),
                BoundWorld(name: "agent-law-person-a", rootPath: path("person-a"), layer: "tenant",
                           parent: "agent-law", key: "person-a"),
                BoundWorld(name: "agent-law-tenant-b", rootPath: path("tenant-b"), layer: "tenant",
                           parent: "agent-law", key: "tenant-b"),
            ],
            currentWorld: "agent-law", devices: ["mac"], currentDevice: "mac")
        return Fixture(dir: dir, file: file, predecessorObject: old)
    }

    static let agent = LawActor(
        author: "agent:claude@mac", kind: .agent, device: "mac", runtime: "claude-code",
        model: "claude-opus-5-5", effort: "high")

    static func draft(_ title: String, body: String = "본문", cites: [LawCite] = [], amends: String? = nil,
                      repeals: String? = nil, batch: String? = nil) -> LawDraft {
        LawDraft(actor: agent, title: title, batch: batch, cites: cites, amends: amends, repeals: repeals, body: body)
    }

    // MARK: - 왕복

    @Test func enactAmendRepealRestoreAuditRoundTrip() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let first = try LawEnactService.enact(Self.draft("첫 기록", batch: "b1"), target: law)
        #expect(first.record.device == "mac")
        #expect(first.record.authorKind == "agent")
        let amended = try LawEnactService.enact(Self.draft("개정판", body: "새 본문", amends: first.id, batch: "b2"), target: law)
        let view = LawLedgerView(records: law.store.scan())
        #expect(!view.isInForce(first.id))
        #expect(view.isInForce(amended.id))
        let repealed = try LawEnactService.enact(Self.draft("폐지: 개정판", body: "", repeals: amended.id, batch: "b3"), target: law)
        #expect(!LawLedgerView(records: law.store.scan()).isInForce(amended.id))
        // 원상회복 b3 → 폐지 기록을 폐지해 개정판이 다시 현행.
        let restored = try LawEnactService.restore(batch: "b3", actor: Self.agent, target: law)
        #expect(restored.count == 1)
        #expect(restored[0].record.repeals == repealed.id)
        #expect(LawLedgerView(records: law.store.scan()).isInForce(amended.id))
        let report = law.store.audit(context: LawEnactService.context(index: LawEnactService.scope(of: law)))
        #expect(report.passed, "\(report.violations)")
    }

    // MARK: - 쓰기 게이트

    @Test func archivedPredecessorRefusesWritesInBothFormats() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let archived = fx.target("gujo-wiki")
        #expect(archived.writeDenial()?.reason == .archivedPredecessor)
        #expect(throws: LedgerHumanEditError.self) {
            try LedgerHumanEdit.perform(.create(title: "x", body: "y", cites: []), target: archived)
        }
        #expect(LedgerStore(root: archived.root).scan().count == 1)
    }

    @Test func unregisteredDeviceIsRefused() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        for target in [fx.target("agent-law", device: nil), fx.target("agent-law", device: "other")] {
            do {
                try LawEnactService.enact(Self.draft("x"), target: target)
                Issue.record("미등록 기기 공포가 통과함")
            } catch let LawEnactServiceError.writeDenied(denial) {
                #expect(denial.reason == .unregisteredDevice)
            }
        }
        #expect(fx.target("agent-law").store.scan().isEmpty)
    }

    // MARK: - 작성자와 모델 기록

    @Test func modelUnknownAgentIsRefused() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let actor = try LawActorResolution.actor(
            author: "agent:claude@mac", explicit: LawModelRecord(runtime: "claude-code"), environment: [:], device: "mac")
        do {
            try LawEnactService.enact(LawDraft(actor: actor, title: "x", body: "y"), target: fx.target("agent-law"))
            Issue.record("모델 미상 공포가 통과함")
        } catch LawEnactServiceError.enact(.modelUnknown) {}
    }

    @Test func modelRecordPrecedenceAndAuthorKind() throws {
        let environment = [
            LawModelRecordSource.runtimeKey: "codex", LawModelRecordSource.modelKey: "gpt-x",
            LawModelRecordSource.effortKey: "low",
        ]
        let fromEnvironment = try LawActorResolution.actor(author: "agent:c@mac", environment: environment, device: "mac")
        #expect(fromEnvironment.runtime == "codex")
        #expect(fromEnvironment.model == "gpt-x")
        let explicit = try LawActorResolution.actor(
            author: "agent:c@mac", explicit: LawModelRecord(model: "claude-opus-5-5"), environment: environment, device: "mac")
        #expect(explicit.model == "claude-opus-5-5")
        #expect(explicit.runtime == "codex")
        // 사람 작성자는 에이전트 표지(사람이 아닌 AGENT_WIKI_RUNTIME 등)가 있으면 거부하고, 없으면 사람 공포다.
        #expect(throws: LawActorError.humanInAgentSession(LawModelRecordSource.runtimeKey)) {
            try LawActorResolution.actor(author: "user:yun", environment: environment, device: "mac")
        }
        let human = try LawActorResolution.actor(author: "user:yun", environment: [:], device: "mac")
        #expect(human.kind == .human)
        #expect(human.model == nil)
        #expect(human.runtime == LawRuntime.human.rawValue)
        let app = try LawActorResolution.actor(author: "app:agent-wiki", environment: [:], device: "mac")
        #expect(app.kind == .app)
        #expect(app.app == "agent-wiki")
        #expect(LawActorResolution.kind(of: "yun@host") == nil)
        // 접두어 없는 기본 작성자는 에이전트 표지가 없으면 사람(`user:`)으로 읽는다(LawDefaultAuthorTests).
        let bare = try LawActorResolution.actor(author: "yun@host", environment: [:], device: "mac")
        #expect(bare.kind == .human)
        #expect(bare.author == "user:yun@host")
    }

    // MARK: - 인용 범위

    @Test func predecessorCiteAllowedSiblingRefused() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let lawIndex = LawEnactService.scope(of: law)
        let resolved = try LawReferenceLookup.resolve(String(fx.predecessorObject.id.prefix(10)), index: lawIndex)
        #expect(resolved == fx.predecessorObject.id)
        let citing = try LawEnactService.enact(
            Self.draft("전신 인용", cites: [LawCite(id: resolved)]), target: law, index: lawIndex)
        #expect(citing.record.cites.first?.id == fx.predecessorObject.id)
        let resolver = LawScopeReferenceResolver(index: lawIndex)
        #expect(resolver.resolve(resolved)?.scope == .predecessor)
        #expect(resolver.resolve(resolved)?.type == "decision")

        // 형제 테넌트의 기록은 범위 밖 — 인용 게이트의 거부 문구.
        let sibling = try LawEnactService.enact(Self.draft("형제 기록"), target: fx.target("agent-law-tenant-b"))
        let personIndex = LawEnactService.scope(of: fx.target("agent-law-person-a"))
        do {
            _ = try LawReferenceLookup.resolve(sibling.id, index: personIndex)
            Issue.record("형제 인용이 통과함")
        } catch LawReferenceError.outOfScope(let denial) {
            #expect(denial.message.contains("sibling"))
        }
        // 테넌트에서 상위(공유 원장)와 그 전신은 범위 안.
        #expect(personIndex.object(id: citing.id)?.world == "agent-law")
        #expect(personIndex.object(id: fx.predecessorObject.id)?.isPredecessor == true)
    }

    @Test func searchScopeMarksPredecessor() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        try LawEnactService.enact(Self.draft("새 기록 키워드"), target: law)
        let index = LawEnactService.scope(of: law)
        #expect(index.entries.map(\.name) == ["agent-law", "gujo-wiki"])
        #expect(index.entries.last?.predecessor == true)
        let hits = index.lookup("전신 지식")
        #expect(hits.count == 1)
        #expect(hits.first?.isPredecessor == true)
        #expect(hits.first?.entry.predecessorOf == "agent-law")
    }

    // MARK: - 화면 편집(모델 수준)

    @Test func humanEditPathUsesEnactWithHumanSpeaker() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let created = try LedgerHumanEdit.perform(
            .create(title: "내 기록", body: "사람 본문", cites: [.init(id: fx.predecessorObject.id, rel: "supports")]),
            target: law, author: "user:yun")
        let record = try #require(law.store.scan().first { $0.id == created }?.record)
        #expect(record.authorKind == "human")
        #expect(record.speaker == "user")
        #expect(record.device == "mac")
        #expect(record.model == nil)
        #expect(record.cites.first?.rel == "cites")  // ledger 3 관계 집합 밖은 cites 로
        let amended = try LedgerHumanEdit.perform(
            .amend(target: created, title: "내 기록", body: "고친 본문", cites: []), target: law, author: "user:yun")
        try LedgerHumanEdit.perform(.repeal(target: amended, reason: "deleted by user"), target: law, author: "user:yun")
        #expect(!LawLedgerView(records: law.store.scan()).isInForce(amended))
        try LedgerHumanEdit.perform(.restore(target: amended), target: law, author: "user:yun")
        #expect(LawLedgerView(records: law.store.scan()).isInForce(amended))
        #expect(law.store.audit(context: LawEnactService.context(index: LawEnactService.scope(of: law))).passed)
    }

    // MARK: - 설정 저장

    @Test func ledgerConfigSavePreservesLedgerThreeFields() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let url = fx.dir.appendingPathComponent("config.json")
        var file = fx.file
        file.tenantMap = ["personal": "agent-law-person-a"]
        file.dreamDevice = "mac"
        try WorldConfigStore.save(file, to: url)
        // 옛 모델로 읽고 고쳐 다시 쓴다(registerWorld·화면 world 전환 경로).
        var config = try JSONDecoder().decode(LedgerConfig.self, from: Data(contentsOf: url))
        config.currentWorld = "agent-law-person-a"
        config.worlds = (config.worlds ?? []) + [LedgerWorld(name: "novel-world", rootPath: "/tmp/novel")]
        try config.save(to: url)
        let reloaded = WorldConfigStore.load(from: url)
        #expect(reloaded.currentWorld == "agent-law-person-a")
        #expect(reloaded.tenantMap == ["personal": "agent-law-person-a"])
        #expect(reloaded.devices == ["mac"])
        #expect(reloaded.currentDevice == "mac")
        #expect(reloaded.dreamDevice == "mac")
        let catalog = WorldBindingCatalog(worlds: reloaded.effectiveWorlds)
        #expect(catalog.world(named: "agent-law")?.key == "law")
        #expect(catalog.world(named: "agent-law")?.predecessor == "gujo-wiki")
        #expect(catalog.world(named: "agent-law-person-a")?.parent == "agent-law")
        #expect(catalog.world(named: "agent-law-person-a")?.layer == "tenant")
        #expect(catalog.world(named: "gujo-wiki")?.layer == "remoteShared")
        #expect(catalog.world(named: "novel-world") != nil)
        #expect(catalog.isArchived("gujo-wiki"))
    }

    // MARK: - 파생 색인·승격

    @Test func derivedIndexCarriesLedgerThreeRecords() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        try LawEnactService.enact(Self.draft("색인 대상", body: "고유한단어"), target: law)
        let index = LedgerIndex(root: law.root)
        index.sync(objectsDir: law.root.appendingPathComponent("objects"))
        #expect(index.objectCount() == 1)
        #expect(!index.searchAllIDs("고유한단어").isEmpty)
        // 색인이 있으면 공포 후처리가 따라오게 한다.
        try LawEnactService.enact(Self.draft("두 번째"), target: law)
        #expect(LedgerIndex(root: law.root).objectCount() == 2)
    }

    @Test func promotionWritesReceiptsBothSides() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let person = fx.target("agent-law-person-a")
        let source = try LawEnactService.enact(Self.draft("올릴 기록"), target: person)
        let result = try LawPromotionService.promote(
            sourceID: source.id, source: person, targetWorld: "agent-law", actor: Self.agent)
        #expect(!result.deduplicated)
        let law = fx.target("agent-law")
        #expect(law.store.scan().contains { $0.id == result.promotedObjectId })
        let receipt = try #require(person.store.scan().first { $0.id == result.sourceReceiptObjectId })
        #expect(receipt.record.cites.map(\.rel) == ["receipts", "promoted-as"])
        let again = try LawPromotionService.promote(
            sourceID: source.id, source: person, targetWorld: "agent-law", actor: Self.agent)
        #expect(again.deduplicated)
        #expect(again.promotedObjectId == result.promotedObjectId)
        // 형제·하위로는 승격하지 않는다.
        #expect(throws: LawPromotionError.self) {
            try LawPromotionService.promote(
                sourceID: source.id, source: person, targetWorld: "agent-law-tenant-b", actor: Self.agent)
        }
        #expect(person.store.audit(context: LawEnactService.context(index: LawEnactService.scope(of: person))).passed)
    }
}
