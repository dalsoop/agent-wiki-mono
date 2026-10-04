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

    static func register(
        _ fx: Fixture, repo: String, title: String, status: String? = nil, path: String? = nil
    ) throws -> LawStoredRecord {
        try JudgmentRegistry.checkRegistrationTarget(worldName: "agent-law", catalog: fx.catalog)
        let draft = try JudgmentRegistry.draft(actor: agent, repo: repo, title: title, status: status, path: path)
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
        let b = try Self.register(fx, repo: "agent-wiki-mono", title: "B", status: "confirmed")
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
        // 상태 변경은 개정(`judgment amend`) — 본문 머리 칸만 바꾼다. 일반 공포(amend)는 판결 등록 유형을 받지 않는다.
        let entry = try JudgmentRegistry.find(String(first.id.prefix(8)), records: law.store.scan())
        let draft = try JudgmentRegistry.amendDraft(actor: Self.agent, entry: entry, title: nil, status: "confirmed", path: nil)
        #expect(draft.title == "판결 X")
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
        // 폐지되면 현행판이 없다.
        _ = try LawEnactService.enact(
            LawDraft(actor: Self.agent, title: "폐지: 판결 X", repeals: amended.id, body: ""), target: law)
        #expect(throws: JudgmentRegistryError.noInForce(number)) {
            try JudgmentRegistry.find(number, records: law.store.scan())
        }
        #expect(throws: JudgmentRegistryError.notFound("ffffffff")) {
            try JudgmentRegistry.find("ffffffff", records: law.store.scan())
        }
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
