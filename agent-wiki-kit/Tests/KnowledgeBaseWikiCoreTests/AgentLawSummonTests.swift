import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

// 소환과 증언 확인(T8) 시험. 가짜 R2(메모리)·주입 세션 원천·임시 원장 루트·임시 색인 폴더만 쓴다.
// 근거: docs/business-rules.md "화자"·"본문 머리 칸"·"관계", docs/security.md "agent-law" 격리 표,
// docs/contracts.md `summon`, docs/architecture.md "agent-law"(소환 색인은 로컬 파생).

/// 끊을 수 있는 R2 자리(색인 재생성·오프라인 시험).
final class SwitchableStore: @unchecked Sendable {
    private let lock = NSLock()
    private var online = true
    let store: FakeLawObjectStore

    init(_ store: FakeLawObjectStore) { self.store = store }

    func set(online value: Bool) { lock.withLock { online = value } }

    func open() throws -> (any LawObjectStore)? {
        try lock.withLock {
            guard online else { throw LawObjectStoreError.unreachable("가짜 끊김") }
            return store
        }
    }
}

@Suite struct AgentLawSummonTests {
    struct Fixture {
        let dir: URL
        let file: BoundLedgerFile
        let registry: LawSessionRegistry
        let store: FakeLawObjectStore
        let switchable: SwitchableStore
        let source = FakeSessionSource()
        /// 다른 기기(`mini`)의 세션.
        let miniSource = FakeSessionSource()
        let clock: ManualClock
        var indexDirectory: URL { dir.appendingPathComponent("summon-index") }

        var sources: LawSummonSources {
            let switchable = self.switchable
            return LawSummonSources(
                objectStore: { try switchable.open() }, local: source, registry: registry,
                tenantMap: file.tenantMap, currentDevice: "mac", indexDirectory: indexDirectory)
        }

        func target(_ name: String) -> LawLedgerTarget {
            var target = LawLedgerTarget(worldName: name, file: file)
            target.summonOverride = sources
            return target
        }

        func scope(_ name: String) -> LawSummonScope { LawSummonScope(world: name, catalog: target(name).catalog)! }

        func archive(device: String = "mac") throws -> LawArchiveOutcome {
            try LawArchiveRunner(
                device: device, file: file, source: device == "mac" ? source : miniSource, registry: registry,
                stateDirectory: dir.appendingPathComponent("archive-\(device)"), store: store, clock: clock.clock
            ).run(dryRun: false)
        }

        func search(_ query: LawSummonQuery, from world: String = "agent-law-person-a") throws -> LawSummonResult {
            try LawSummonService.search(query, target: target(world))
        }

        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    /// 2026-10-04 00:00:00 UTC.
    static let start = Date(timeIntervalSince1970: 1_791_072_000)
    static let agent = LawActor(
        author: "agent:claude@mac", kind: .agent, device: "mac", runtime: "claude-code",
        model: "claude-opus-5-5", effort: "high")
    static let human = LawActor(author: "user:tester", kind: .human, device: "mac")
    static let secretText = "결과는 tester@example.com 으로 보내 줘"

    static func say(_ role: String, _ text: String) -> LawSessionUtterance { LawSessionUtterance(role: role, text: text) }

    static func session(_ runtime: LawRuntime, _ id: String, _ lines: [LawSessionUtterance]) -> FakeSessionSource.Session {
        FakeSessionSource.Session(runtime: runtime, id: id, startedAt: start + 1, utterances: lines)
    }

    /// 개인(`person-a`)·공유(`law`, 테넌트 `shared`)·다른 테넌트(`tenant-b`)·테넌트 미상 세션을 두 기기에서 적재한다.
    static func fixture() throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-law-summon-\(UUID().uuidString)", isDirectory: true)
        func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
        let file = BoundLedgerFile(
            worlds: [
                BoundWorld(name: "agent-law", rootPath: path("law"), key: "law"),
                BoundWorld(name: "agent-law-person-a", rootPath: path("person-a"), layer: "tenant",
                           parent: "agent-law", key: "person-a"),
                BoundWorld(name: "agent-law-tenant-b", rootPath: path("tenant-b"), layer: "tenant",
                           parent: "agent-law", key: "tenant-b"),
            ],
            currentWorld: "agent-law",
            tenantMap: ["personal": "agent-law-person-a", "gujo": "agent-law-tenant-b", "shared": "agent-law"],
            devices: ["mac", "mini"], currentDevice: "mac")
        let store = FakeLawObjectStore()
        let fx = Fixture(
            dir: dir, file: file, registry: LawSessionRegistry(directory: dir.appendingPathComponent("sessions")),
            store: store, switchable: SwitchableStore(store), clock: ManualClock(start))
        // 켠 시각 기록(두 기기).
        _ = try fx.archive()
        _ = try fx.archive(device: "mini")
        fx.clock.advance(1)

        fx.registry.register(LawSessionRegistration(sessionID: "s-law", tenant: "shared"))
        fx.registry.register(LawSessionRegistration(sessionID: "s-gujo", tenant: "gujo"))
        fx.registry.register(LawSessionRegistration(sessionID: "s-acme", tenant: "acme"))
        fx.source.add(session(.claudeCode, "s-a", [say("user", "배포 순서를 정해줘"), say("assistant", "네, 정했습니다")]))
        fx.source.add(session(.codex, "s-b", [say("user", "로그 확인"), say("assistant", Self.secretText)]))
        fx.source.add(session(.claudeCode, "s-law", [say("user", "공유 원장 규칙")]))
        fx.source.add(session(.claudeCode, "s-gujo", [say("user", "구조 테넌트 비밀 대화")]))
        fx.source.add(session(.claudeCode, "s-acme", [say("user", "미상 테넌트 대화")]))
        fx.source.add(session(.claudeCode, "s-amb", [say("user", "좋아"), say("assistant", "좋아요")]))
        _ = try fx.archive()
        fx.clock.advance(3600)
        fx.miniSource.add(session(.grok, "s-c", [say("user", "배포 확인")]))
        _ = try fx.archive(device: "mini")
        return fx
    }

    // MARK: - 조건별 검색

    @Test func searchFiltersBySessionTimeDeviceRuntimeRoleAndWords() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let all = try fx.search(LawSummonQuery())
        #expect(all.ledgerKeys == ["person-a", "law"])
        #expect(Set(all.utterances.map(\.session)) == ["s-a", "s-b", "s-law", "s-amb", "s-c"])

        let words = try fx.search(LawSummonQuery(query: "배포"))
        #expect(words.utterances.map { "\($0.session)#\($0.index)" } == ["s-a#0", "s-c#0"])
        #expect(try fx.search(LawSummonQuery(query: "배포 순서")).utterances.map(\.session) == ["s-a"])

        let session = try fx.search(LawSummonQuery(session: "s-a"))
        #expect(session.utterances.map(\.index) == [0, 1])
        #expect(session.utterances[0].chunk?.hasPrefix("person-a/sessions/mac/claude-code/s-a/") == true)

        #expect(try fx.search(LawSummonQuery(runtime: "codex")).utterances.map(\.session) == ["s-b", "s-b"])
        #expect(try fx.search(LawSummonQuery(device: "mini")).utterances.map(\.session) == ["s-c"])
        #expect(try fx.search(LawSummonQuery(role: "assistant", query: "정했")).utterances.map(\.index) == [1])

        // 기간: s-c 는 한 시간 뒤 실행에 적재됐다.
        let later = try fx.search(LawSummonQuery(since: Self.start + 1800))
        #expect(later.utterances.map(\.session) == ["s-c"])
        let earlier = try fx.search(LawSummonQuery(until: Self.start + 1800))
        #expect(!earlier.utterances.contains { $0.session == "s-c" })
        #expect(earlier.utterances.allSatisfy { $0.at == LawArchiveKeys.kstTimestamp(Self.start + 1) })

        // 가림 규칙은 적재 때 적용돼 있다.
        let masked = try fx.search(LawSummonQuery(session: "s-b", role: "assistant"))
        #expect(masked.utterances.map(\.text) == [LawRedaction.redact(Self.secretText)])
        #expect(!masked.utterances[0].text.contains("tester@example.com"))
    }

    @Test func timeArgumentsParse() {
        #expect(LawSummonQuery.parseTime("2026-10-04T09:00:00+09:00") == Self.start)
        #expect(LawSummonQuery.parseTime("2026-10-04") == Self.start - 9 * 3600)  // 한국 시간 자정
        #expect(LawSummonQuery.parseTime("어제") == nil)
    }

    // MARK: - 범위

    @Test func otherTenantAndUnassignedSessionsAreRefusedSharedAllowed() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        #expect(throws: LawSummonError.outOfScope(session: "s-gujo", ledger: "tenant-b")) {
            try fx.search(LawSummonQuery(session: "s-gujo"))
        }
        #expect(throws: LawSummonError.outOfScope(session: "s-acme", ledger: "unassigned/acme")) {
            try fx.search(LawSummonQuery(session: "s-acme"))
        }
        // 조건 없는 검색에도 범위 밖 세션은 없다.
        let all = try fx.search(LawSummonQuery(query: "테넌트"))
        #expect(all.utterances.isEmpty)

        // 공유 원장(law) 세션은 테넌트 원장에서도 소환한다.
        #expect(try fx.search(LawSummonQuery(session: "s-law")).utterances.map(\.ledgerKey) == ["law"])

        // 다른 테넌트 원장에서는 그 테넌트 세션만, 개인 세션은 거부.
        #expect(try fx.search(LawSummonQuery(session: "s-gujo"), from: "agent-law-tenant-b").utterances.count == 1)
        #expect(throws: LawSummonError.outOfScope(session: "s-a", ledger: "person-a")) {
            try fx.search(LawSummonQuery(session: "s-a"), from: "agent-law-tenant-b")
        }
        // 공유 원장에서는 공유 세션만.
        #expect(try fx.search(LawSummonQuery(), from: "agent-law").utterances.map(\.session) == ["s-law"])
        #expect(throws: LawSummonError.outOfScope(session: "s-a", ledger: "person-a")) {
            try fx.search(LawSummonQuery(session: "s-a"), from: "agent-law")
        }
        // 적재 전인 다른 테넌트 로컬 세션도 거부.
        fx.registry.register(LawSessionRegistration(sessionID: "s-gujo-new", tenant: "gujo"))
        fx.source.add(Self.session(.codex, "s-gujo-new", [Self.say("user", "새 구조 대화")]))
        #expect(throws: LawSummonError.outOfScope(session: "s-gujo-new", ledger: "tenant-b")) {
            try fx.search(LawSummonQuery(session: "s-gujo-new"))
        }
    }

    @Test func localSessionNotYetArchivedIsSummonedBySessionID() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        fx.source.append("s-a", Self.say("user", "적재 전 발화 tester@example.com"))
        fx.source.add(Self.session(.codex, "s-new", [Self.say("user", "아직 안 올린 세션")]))
        let a = try fx.search(LawSummonQuery(session: "s-a"))
        #expect(a.utterances.map(\.index) == [0, 1, 2])
        #expect(a.utterances[2].chunk == nil)
        #expect(a.utterances[2].text == LawRedaction.redact("적재 전 발화 tester@example.com"))
        let fresh = try fx.search(LawSummonQuery(session: "s-new"))
        #expect(fresh.utterances.map(\.ledgerKey) == ["person-a"])
        #expect(fresh.utterances.map(\.device) == ["mac"])
    }

    // MARK: - 색인

    @Test func indexIsLocalCopyRebuiltFromR2() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let first = try fx.search(LawSummonQuery())
        #expect(first.offline == nil)
        let cached = fx.indexDirectory.appendingPathComponent("person-a/chunks")
        #expect(try FileManager.default.contentsOfDirectory(atPath: cached.path).count >= 1)

        // R2 가 끊겨도 사본으로 같은 결과.
        fx.switchable.set(online: false)
        let offline = try fx.search(LawSummonQuery())
        #expect(offline.offline != nil)
        #expect(offline.utterances == first.utterances)

        // 사본을 지우면 끊긴 동안은 비고, R2 가 돌아오면 다시 만든다.
        try FileManager.default.removeItem(at: fx.indexDirectory)
        #expect(try fx.search(LawSummonQuery()).utterances.isEmpty)
        fx.switchable.set(online: true)
        let rebuilt = try fx.search(LawSummonQuery())
        #expect(rebuilt.utterances == first.utterances)
        #expect(FileManager.default.fileExists(atPath: cached.path))
    }

    @Test func redactedChunksAreSkippedAndLocalCopiesDropped() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let before = try fx.search(LawSummonQuery(session: "s-b"))
        let chunk = try #require(before.utterances.first?.chunk)
        let cacheFile = fx.indexDirectory.appendingPathComponent("person-a/chunks/" + LawSummonIndex.fileName(chunk))
        #expect(FileManager.default.fileExists(atPath: cacheFile.path))

        _ = try LawRedactService.redact(
            chunk, reason: "개인정보", actor: Self.human, target: fx.target("agent-law-person-a"), objectStore: fx.store)
        let after = try fx.search(LawSummonQuery())
        #expect(!after.utterances.contains { $0.session == "s-b" })
        #expect(after.redactedChunks == 1)
        #expect(!FileManager.default.fileExists(atPath: cacheFile.path))

        // 가림 기록 없이 R2 에서 사라진 조각도 건너뛴다(사본이 없을 때).
        let law = try #require(try fx.search(LawSummonQuery(session: "s-law")).utterances.first?.chunk)
        try FileManager.default.removeItem(at: fx.indexDirectory)
        try fx.store.delete(key: law)
        let gone = try fx.search(LawSummonQuery(query: "공유"))
        #expect(gone.utterances.isEmpty)
        #expect(gone.redactedChunks >= 1)

        // 가린 발화로는 증언할 수 없다.
        let testimony = LawSessionTestimony(scope: fx.scope("agent-law-person-a"), sources: fx.sources)
        let quote = "로그 확인"
        let request = LawTestimonyRequest(
            session: "s-b", utteranceAt: nil, runtime: nil, device: nil,
            quotes: [LawExhibitQuote(sha256: LawHash.sha256Hex(quote), text: quote)])
        // 세션 원본은 이 기기에 남아 있어 로컬 발화로는 찾는다 — 로컬 원천을 빼면 없다.
        var archivedOnly = fx.sources
        archivedOnly.local = nil
        #expect(try LawSessionTestimony(scope: fx.scope("agent-law-person-a"), sources: archivedOnly)
            .speaker(for: request) == nil)
        #expect(try testimony.speaker(for: request) == .user)
    }

    // MARK: - --record

    @Test func recordStoresExhibitAndEnactsEvidenceWithUtteranceSpeaker() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let target = fx.target("agent-law-person-a")
        let user = try LawSummonService.record(
            index: 0, query: LawSummonQuery(session: "s-a"), target: target, actor: Self.agent, now: Self.start + 7200)
        #expect(user.record.record.type == "evidence")
        #expect(user.record.record.speaker == "user")
        #expect(user.record.record.exhibits == [user.exhibit])
        #expect(user.uploaded)
        #expect(fx.store.object(LawArchiveKeys.exhibit(ledgerKey: "person-a", sha256: user.exhibit)) != nil)
        let head = try LawHeadFields.parse(body: user.record.record.body, type: "evidence")
        #expect(head["session"] == "s-a")
        #expect(head["runtime"] == "claude-code")
        #expect(head["device"] == "mac")
        #expect(head["utterance-at"] == LawArchiveKeys.kstTimestamp(Self.start + 1))
        let exhibitData = try target.store.exhibit(sha256: user.exhibit)
        let exhibit = try #require(LawSummonExhibit.decode(String(decoding: exhibitData, as: UTF8.self)))
        #expect(exhibit.quote == "배포 순서를 정해줘")
        #expect(exhibit.speaker == "user")
        #expect(exhibit.session == "s-a")
        #expect(exhibit.chunk?.hasPrefix("person-a/sessions/mac/claude-code/s-a/") == true)
        #expect(LawHash.sha256Hex(exhibitData) == user.exhibit)

        let agent = try LawSummonService.record(
            index: 1, query: LawSummonQuery(session: "s-a"), target: target, actor: Self.agent, now: Self.start + 7201)
        #expect(agent.record.record.speaker == "agent")

        // 세션을 고르지 않으면 모호, 없는 번호는 거부, 범위 밖은 거부.
        #expect(throws: LawSummonError.self) {
            try LawSummonService.record(index: 0, query: LawSummonQuery(), target: target, actor: Self.agent)
        }
        #expect(throws: LawSummonError.utteranceNotFound(session: "s-a", index: 9)) {
            try LawSummonService.record(index: 9, query: LawSummonQuery(session: "s-a"), target: target, actor: Self.agent)
        }
        #expect(throws: LawSummonError.outOfScope(session: "s-gujo", ledger: "tenant-b")) {
            try LawSummonService.record(index: 0, query: LawSummonQuery(session: "s-gujo"), target: target, actor: Self.agent)
        }
    }

    @Test func speakerUserClaimPassesOnlyThroughTestimony() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let target = fx.target("agent-law-person-a")
        let evidence = try LawSummonService.record(
            index: 0, query: LawSummonQuery(session: "s-a"), target: target, actor: Self.agent)
        #expect(evidence.record.record.speaker == "user")

        // 증언 인용 없는 speaker: user 는 거부, testifies 로 인용하면 통과(기본 확인자 경로 그대로).
        let claim = LawDraft(actor: Self.agent, speaker: "user", title: "사용자 지시", body: "배포 순서를 정한다")
        #expect(throws: LawEnactServiceError.self) { try LawEnactService.enact(claim, target: target) }
        var cited = claim
        cited.cites = [LawCite(id: evidence.record.id, rel: LawRelation.testifies.rawValue)]
        #expect(try LawEnactService.enact(cited, target: target).record.speaker == "user")

        // assistant 발화를 user 라고 주장한 증거는 거부.
        let agentQuote = Data("네, 정했습니다".utf8)
        let sha = try target.store.putExhibit(agentQuote)
        let lie = LawDraft(
            actor: Self.agent, speaker: "user", title: "거짓 증언", type: "evidence", exhibits: [sha],
            body: "session: s-a\nruntime: claude-code\n\n네, 정했습니다")
        do {
            _ = try LawEnactService.enact(lie, target: target)
            Issue.record("거짓 증언이 공포됨")
        } catch LawEnactServiceError.enact(let error) {
            #expect(error == .testimonyMismatch)
        }
        // 손으로 넣은 인용 구절(전체 발화가 아닌 부분)도 같은 확인을 거친다 — 화자를 비우면 발화 역할.
        var honest = lie
        honest.speaker = nil
        #expect(try LawEnactService.enact(honest, target: target).record.speaker == "agent")
    }

    @Test func sharedLedgerCannotCiteTenantEvidence() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let evidence = try LawSummonService.record(
            index: 0, query: LawSummonQuery(session: "s-a"), target: fx.target("agent-law-person-a"), actor: Self.agent)
        let law = fx.target("agent-law")
        #expect(throws: LawEnactServiceError.self) {
            try LawEnactService.resolveReferences([evidence.record.id], index: LawEnactService.scope(of: law))
        }
        let draft = LawDraft(
            actor: Self.agent, speaker: "user", title: "공유 원장 기록",
            cites: [LawCite(id: evidence.record.id, rel: LawRelation.testifies.rawValue)], body: "본문")
        do {
            _ = try LawEnactService.enact(draft, target: law)
            Issue.record("공유 원장이 테넌트 증거를 인용함")
        } catch LawEnactServiceError.enact(let error) {
            #expect(error == .unresolvedReference(evidence.record.id))
        }
    }

    // MARK: - 증언 확인

    @Test func testimonyMatchesRedactedSubstringAndRefusesMismatchMissingAndAmbiguous() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let testimony = LawSessionTestimony(scope: fx.scope("agent-law-person-a"), sources: fx.sources)
        func ask(_ session: String?, _ quote: String, runtime: String? = nil, text: String? = nil) throws -> LawSpeaker? {
            try testimony.speaker(for: LawTestimonyRequest(
                session: session, utteranceAt: nil, runtime: runtime, device: nil,
                quotes: [LawExhibitQuote(sha256: LawHash.sha256Hex(quote), text: text ?? quote)]))
        }
        // 가린 발화의 연속 부분 문자열(가림 표시 포함).
        let redacted = LawRedaction.redact(Self.secretText)
        #expect(redacted.contains(LawRedaction.mask))
        let part = String(redacted.prefix(redacted.count - 3))
        #expect(try ask("s-b", part) == .agent)
        #expect(try ask("s-b", part, runtime: "codex") == .agent)
        #expect(try ask("s-b", part, runtime: "grok") == nil)
        // 가리지 않은 원문은 맞지 않는다.
        #expect(try ask("s-b", Self.secretText) == nil)
        // 불일치·세션 없음·세션 미지정.
        #expect(try ask("s-a", "하지 않은 말") == nil)
        #expect(try ask("s-none", "배포") == nil)
        #expect(try ask(nil, "배포") == nil)
        // 범위 밖 세션.
        #expect(try ask("s-gujo", "구조 테넌트") == nil)
        // 공유 원장 세션은 범위 안.
        #expect(try ask("s-law", "공유 원장") == .user)
        // 역할이 갈리는 인용은 모호 → 거부. 발화 번호를 지목한 증거물이면 그 발화로 정한다.
        #expect(try ask("s-amb", "좋아") == nil)
        let pinned = LawSummonExhibit(
            utterance: LawSummonUtterance(
                ledgerKey: "person-a", device: "mac", runtime: "claude-code", session: "s-amb", index: 1,
                role: "assistant", text: "좋아", at: nil, chunk: nil),
            speaker: .agent)
        let pinnedText = String(decoding: try pinned.encoded(), as: UTF8.self)
        #expect(try ask("s-amb", pinnedText) == .agent)
        // 증거물 내용이 이름(sha256)과 다르면 거부.
        #expect(try testimony.speaker(for: LawTestimonyRequest(
            session: "s-a", utteranceAt: nil, runtime: nil, device: nil,
            quotes: [LawExhibitQuote(sha256: LawHash.sha256Hex("다른 내용"), text: "배포 순서")])) == nil)
        // 로컬 증거물이 없으면 범위 안 R2 증거물에서 읽는다.
        let remote = Data("배포 순서".utf8)
        let sha = LawHash.sha256Hex(remote)
        fx.store.seed(LawArchiveKeys.exhibit(ledgerKey: "person-a", sha256: sha), remote)
        #expect(try testimony.speaker(for: LawTestimonyRequest(
            session: "s-a", utteranceAt: nil, runtime: nil, device: nil,
            quotes: [LawExhibitQuote(sha256: sha, text: nil)])) == .user)
    }

    @Test func enactPathUsesSessionTestimonyByDefault() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let target = fx.target("agent-law-person-a")
        let sha = try target.store.putExhibit(Data("배포 순서를".utf8))
        let draft = LawDraft(
            actor: Self.agent, title: "증언", type: "evidence", exhibits: [sha],
            body: "session: s-a\nutterance-at: 2026-10-04T09:00:01+09:00\n\n배포 순서를")
        // 확인자를 넘기지 않아도 공포 경로가 세션 대조로 화자를 정한다.
        #expect(try LawEnactService.enact(draft, target: target).record.speaker == "user")
        // 문맥 기본값에도 확인자가 들어 있다.
        #expect(LawEnactService.context(index: LawEnactService.scope(of: target)).testimony != nil)
    }
}

