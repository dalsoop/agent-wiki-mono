import Foundation
import KnowledgeBaseWikiCore
import Testing
import WikiLedgerKit
@testable import WikiCLIShared

/// 판결 등록(T11) 시험 — 등록 id·번호, 공유 원장 전용, 저장소 필터, 개정 뒤 현행판·처음 번호, 상태 값 집합.
/// 근거: docs/contracts.md "agent-law 명령 (ledger 3)" 판결 행, docs/business-rules.md "판결 등록"·"본문 머리 칸".
/// 임시 디렉터리 루트만 쓴다.
@Suite struct JudgmentRegistryTests {

    struct Fixture {
        let dir: URL
        let catalog: WorldBindingCatalog

        func target(_ name: String) -> LawLedgerTarget {
            LawLedgerTarget(
                worldName: name, root: URL(fileURLWithPath: catalog.world(named: name)!.rootPath),
                catalog: catalog, registeredDevices: ["mac"], currentDevice: "mac")
        }

        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    static func fixture() -> Fixture {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-law-judgment-\(UUID().uuidString)", isDirectory: true)
        func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
        let catalog = WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: path("gujo-wiki"), layer: "remoteShared"),
            BoundWorld(name: "agent-law", rootPath: path("law"), layer: "remoteShared", key: "law",
                       predecessor: "gujo-wiki"),
            BoundWorld(name: "agent-law-person-a", rootPath: path("person-a"), layer: "tenant",
                       parent: "agent-law", key: "person-a"),
            BoundWorld(name: "novel-world", rootPath: path("novel"), layer: "other"),
        ])
        return Fixture(dir: dir, catalog: catalog)
    }

    static let agent = LawActor(
        author: "agent:claude@mac", kind: .agent, device: "mac", runtime: "claude-code",
        model: "claude-opus-5-5", effort: "high")

    struct FakeTestimony: LawTestimonyVerifying {
        func speaker(for request: LawTestimonyRequest) throws -> LawSpeaker? { .user }
    }

    /// 공유 원장의 사용자 발화 증거(증언 확인은 가짜 확인자).
    static func userEvidence(_ fx: Fixture, text: String = "확정한다") throws -> LawStoredRecord {
        let store = fx.target("agent-law").store
        let sha = try store.putExhibit(Data(text.utf8))
        return try store.enact(
            LawDraft(actor: agent, speaker: "user", title: "증언", type: "evidence", exhibits: [sha],
                     body: "session: s-1\nutterance-at: 2026-10-04T00:00:00Z\n\n인용"),
            context: LawEnactContext(testimony: FakeTestimony()))
    }

    static func register(
        _ fx: Fixture, repo: String, title: String, status: String? = nil, path: String? = nil,
        testimony: String? = nil
    ) throws -> LawStoredRecord {
        try JudgmentRegistry.checkRegistrationTarget(worldName: "agent-law", catalog: fx.catalog)
        let draft = try JudgmentRegistry.draft(
            actor: agent, repo: repo, title: title, status: status, path: path, testimony: testimony)
        return try LawEnactService.enact(draft, target: fx.target("agent-law"), path: .judgment)
    }

    @Test func registerGivesIDAndNumberIsFirstEightCharacters() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let stored = try Self.register(fx, repo: "laravel-mono", title: "판결 2026-0027 머지 승인 범위",
                                       path: "docs/tracking/decisions/2026-0027.md")
        #expect(stored.id.count == 64)
        #expect(stored.record.type == LawRecordType.registration.rawValue)
        #expect(JudgmentRegistry.number(of: stored.id) == String(stored.id.prefix(8)))
        let head = try LawHeadFields.parse(body: stored.record.body, type: stored.record.type)
        #expect(head["repo"] == "laravel-mono")
        #expect(head["status"] == "provisional") // 기본값
        #expect(head["path"] == "docs/tracking/decisions/2026-0027.md")
        let entry = try JudgmentRegistry.find(String(stored.id.prefix(8)), records: fx.target("agent-law").store.scan())
        #expect(entry.number == String(stored.id.prefix(8)))
        #expect(entry.id == stored.id)
        #expect(!entry.amended)
    }

    @Test func registrationOnlyOnSharedLedger() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        for world in ["agent-law-person-a", "gujo-wiki", "novel-world", "missing"] {
            #expect(throws: JudgmentRegistryError.notSharedLedger(world)) {
                try JudgmentRegistry.checkRegistrationTarget(worldName: world, catalog: fx.catalog)
            }
        }
        try JudgmentRegistry.checkRegistrationTarget(worldName: "agent-law", catalog: fx.catalog)
        // 조회는 테넌트에서도 상위 공유 원장을 본다.
        #expect(try JudgmentRegistry.sharedLedger(for: "agent-law-person-a", catalog: fx.catalog).name == "agent-law")
        #expect(throws: JudgmentRegistryError.noSharedLedger("novel-world")) {
            try JudgmentRegistry.sharedLedger(for: "novel-world", catalog: fx.catalog)
        }
    }

    @Test func listFiltersByRepository() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let a = try Self.register(fx, repo: "laravel-mono", title: "A")
        let b = try Self.register(
            fx, repo: "agent-wiki-mono", title: "B", status: "confirmed", testimony: try Self.userEvidence(fx).id)
        let c = try Self.register(fx, repo: "laravel-mono", title: "C")
        let records = fx.target("agent-law").store.scan()
        #expect(Set(JudgmentRegistry.entries(records: records).map(\.id)) == [a.id, b.id, c.id])
        let laravel = JudgmentRegistry.entries(records: records, repo: "laravel-mono")
        #expect(Set(laravel.map(\.id)) == [a.id, c.id])
        let wiki = JudgmentRegistry.entries(records: records, repo: "agent-wiki-mono")
        #expect(wiki.map(\.status) == ["confirmed"])
        #expect(wiki.map(\.title) == ["B"])
        #expect(JudgmentRegistry.entries(records: records, repo: "none").isEmpty)
    }

    @Test func statusAmendKeepsFirstNumberAndShowsCurrentRevision() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let first = try Self.register(fx, repo: "laravel-mono", title: "판결 X")
        let evidence = try Self.userEvidence(fx)
        // 상태 변경은 개정(`judgment amend`) — 본문 머리 칸만 바꾼다. 일반 공포(amend)는 판결 등록 유형을 받지 않는다.
        // 잠정 → 확정은 사용자 발화 증언(`--testimony`)을 `testifies` 로 인용한다.
        let entry = try JudgmentRegistry.find(String(first.id.prefix(8)), records: law.store.scan())
        let draft = try JudgmentRegistry.amendDraft(
            actor: Self.agent, entry: entry, title: nil, status: "confirmed", path: nil, testimony: evidence.id)
        #expect(draft.title == "판결 X")
        #expect(draft.cites == [LawCite(id: evidence.id, rel: "testifies")])
        #expect(throws: LawEnactServiceError.self) { try LawEnactService.enact(draft, target: law) }
        let amended = try LawEnactService.enact(draft, target: law, path: .judgment)
        let records = law.store.scan()
        let number = String(first.id.prefix(8))
        for token in [number, String(amended.id.prefix(8))] {
            let entry = try JudgmentRegistry.find(token, records: records)
            #expect(entry.id == amended.id)
            #expect(entry.firstID == first.id)
            #expect(entry.number == number)
            #expect(entry.status == "confirmed")
            #expect(entry.amended)
            #expect(entry.revisions == 2)
        }
        let listed = JudgmentRegistry.entries(records: records)
        #expect(listed.map(\.id) == [amended.id])
        #expect(listed.map(\.number) == [number])
        #expect(throws: JudgmentRegistryError.notFound("ffffffff")) {
            try JudgmentRegistry.find("ffffffff", records: law.store.scan())
        }
    }

    /// 거부되면 그 공포 오류를, 통과하면 nil.
    static func refusal(_ body: () throws -> Void) -> LawEnactError? {
        do {
            try body()
            return nil
        } catch LawEnactServiceError.enact(let error) {
            return error
        } catch {
            Issue.record("예상하지 못한 오류: \(error)")
            return nil
        }
    }

    @Test func judgmentRepealRepealsProvisionalRegistrationOnJudgmentPathOnly() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let first = try Self.register(fx, repo: "r", title: "판결 Y")
        let number = String(first.id.prefix(8))
        let entry = try JudgmentRegistry.find(number, records: law.store.scan())
        let repeal = JudgmentRegistry.repealDraft(actor: Self.agent, entry: entry, reason: "잘못 등록")
        #expect(repeal.repeals == first.id)
        #expect(repeal.type == "registration")
        #expect(repeal.title == "폐지: 판결 Y")
        #expect(repeal.body == "잘못 등록")
        // 일반 repeal 은 판결 등록을 폐지하지 못한다.
        #expect(Self.refusal { try LawEnactService.enact(repeal, target: law) }
                == .targetRequiresDedicatedCommand(target: first.id, type: "registration", command: "judgment"))
        _ = try LawEnactService.enact(repeal, target: law, path: .judgment)
        #expect(throws: JudgmentRegistryError.noInForce(number)) {
            try JudgmentRegistry.find(number, records: law.store.scan())
        }
    }

    @Test func confirmingRequiresUserTestimony() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let first = try Self.register(fx, repo: "r", title: "판결 Z")
        let entry = try JudgmentRegistry.find(String(first.id.prefix(8)), records: law.store.scan())
        // 증언 없이 확정하지 못한다(개정·처음 등록 모두).
        let bare = try JudgmentRegistry.amendDraft(actor: Self.agent, entry: entry, title: nil, status: "confirmed", path: nil)
        #expect(Self.refusal { try LawEnactService.enact(bare, target: law, path: .judgment) } == .judgmentConfirmRequiresTestimony)
        #expect(Self.refusal {
            try LawEnactService.enact(
                try JudgmentRegistry.draft(actor: Self.agent, repo: "r", title: "t", status: "confirmed", path: nil),
                target: law, path: .judgment)
        } == .judgmentConfirmRequiresTestimony)
        // 사용자 화자가 아닌 증거는 증언이 아니다.
        let external = try LawEnactService.enact(
            LawDraft(actor: Self.agent, title: "외부", type: "evidence", body: "외부 문서"), target: law)
        let withExternal = try JudgmentRegistry.amendDraft(
            actor: Self.agent, entry: entry, title: nil, status: "confirmed", path: nil, testimony: external.id)
        #expect(Self.refusal { try LawEnactService.enact(withExternal, target: law, path: .judgment) }
                == .judgmentConfirmRequiresTestimony)
        // 잠정 판결의 경로·제목 수정은 증언 없이 바로 된다.
        let retitled = try LawEnactService.enact(
            try JudgmentRegistry.amendDraft(actor: Self.agent, entry: entry, title: "판결 Z'", status: nil, path: "docs/z.md"),
            target: law, path: .judgment)
        let current = try JudgmentRegistry.find(String(first.id.prefix(8)), records: law.store.scan())
        #expect(current.id == retitled.id)
        #expect(current.status == "provisional")
        #expect(current.path == "docs/z.md")
        // 증언이 있으면 처음부터 확정으로 등록할 수도 있다.
        let confirmed = try Self.register(
            fx, repo: "r", title: "확정 등록", status: "confirmed", testimony: try Self.userEvidence(fx, text: "확정 등록").id)
        #expect(try JudgmentRegistry.find(String(confirmed.id.prefix(8)), records: law.store.scan()).status == "confirmed")
    }

    @Test func confirmedRegistrationChangesOnlyBySupremeRuling() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let store = law.store
        let evidence = try Self.userEvidence(fx)
        let confirmed = try Self.register(fx, repo: "r", title: "확정 판결", status: "confirmed", testimony: evidence.id)
        let number = String(confirmed.id.prefix(8))
        let entry = try JudgmentRegistry.find(number, records: store.scan())
        // 판결 경로라도 대법원 결정 인용 없이는 개정(잠정으로 되돌림·경로 수정)·폐지 모두 거부.
        let back = try JudgmentRegistry.amendDraft(actor: Self.agent, entry: entry, title: nil, status: "provisional", path: nil)
        let moved = try JudgmentRegistry.amendDraft(
            actor: Self.agent, entry: entry, title: nil, status: nil, path: "docs/new.md", testimony: evidence.id)
        let repeal = JudgmentRegistry.repealDraft(actor: Self.agent, entry: entry, reason: "폐지")
        for draft in [back, moved, repeal] {
            for path in [LawEnactPath.judgment, .court] {
                #expect(Self.refusal { try LawEnactService.enact(draft, target: law, path: path) }
                        == .confirmedJudgmentRequiresSupreme(target: confirmed.id), "\(path)")
            }
        }
        // 항소심 결정 인용으로도 안 된다.
        let proposal = try store.enact(LawDraft(
            actor: Self.agent, title: "개정안", type: "proposal", cites: [LawCite(id: confirmed.id, rel: "proposes")],
            body: "scope: 상태\n\nrepo: r\nstatus: provisional\n"))
        let appellate = try store.enact(LawDraft(
            actor: Self.agent, title: "항소심 결정", type: "ruling", cites: [LawCite(id: proposal.id, rel: "hears")],
            body: "level: appellate\noutcome: refer\n\n회부\n"))
        var viaAppellate = back
        viaAppellate.cites = [LawCite(id: appellate.id, rel: "per-ruling")]
        #expect(Self.refusal { try LawEnactService.enact(viaAppellate, target: law, path: .judgment) }
                == .confirmedJudgmentRequiresSupreme(target: confirmed.id))
        #expect(try JudgmentRegistry.find(number, records: store.scan()).id == confirmed.id)
        // 대법원 결정을 per-ruling 으로 인용하면 된다(court·judgment 어느 경로든).
        let supreme = try store.enact(LawDraft(
            actor: Self.agent, speaker: "user", title: "대법원 결정", type: "ruling",
            cites: [LawCite(id: proposal.id, rel: "hears"), LawCite(id: evidence.id, rel: "testifies")],
            body: "level: supreme\noutcome: approve\n\n승인\n"))
        var viaSupreme = back
        viaSupreme.cites = [LawCite(id: supreme.id, rel: "per-ruling")]
        let reverted = try LawEnactService.enact(viaSupreme, target: law, path: .court)
        let current = try JudgmentRegistry.find(number, records: store.scan())
        #expect(current.id == reverted.id)
        #expect(current.status == "provisional")
        // 잠정이 된 판결은 다시 판결 경로로 바로 폐지된다.
        _ = try LawEnactService.enact(
            JudgmentRegistry.repealDraft(actor: Self.agent, entry: current, reason: "폐지"), target: law, path: .judgment)
        #expect(throws: JudgmentRegistryError.noInForce(number)) { try JudgmentRegistry.find(number, records: store.scan()) }
    }

    @Test func statusOutsideValueSetIsRefused() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        #expect(throws: JudgmentRegistryError.self) {
            try JudgmentRegistry.draft(actor: Self.agent, repo: "r", title: "t", status: "final", path: nil)
        }
        #expect(throws: JudgmentRegistryError.self) {
            try JudgmentRegistry.draft(actor: Self.agent, repo: "", title: "t", status: nil, path: nil)
        }
        #expect(throws: JudgmentRegistryError.invalidValue(key: "repo", value: "r\npath: x")) {
            try JudgmentRegistry.draft(actor: Self.agent, repo: "r\npath: x", title: "t", status: nil, path: nil)
        }
        // 개정으로 돌아가는 길(공포 경로)도 같은 값 집합으로 거부한다.
        let first = try Self.register(fx, repo: "r", title: "t")
        #expect(throws: LawEnactServiceError.self) {
            try LawEnactService.enact(
                LawDraft(actor: Self.agent, title: "t", type: LawRecordType.registration.rawValue,
                         amends: first.id, body: "repo: r\nstatus: final\n"),
                target: fx.target("agent-law"), path: .judgment)
        }
        #expect(fx.target("agent-law").store.scan().count == 1)
    }
}
