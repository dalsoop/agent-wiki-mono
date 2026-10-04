import CommandKit
import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// 드리밍·목차·보고(T10) 시험. 실제 AI 실행 도구·R2·세션·키체인을 쓰지 않는다(주입 실행기·메모리 R2·임시 루트).
/// 근거: docs/business-rules.md "드리밍"·"출처 표시"·"심급제"·"작성자와 모델 기록", docs/security.md agent-law 격리 표,
/// docs/contracts.md `dream run|status|resume`·`contents`·`report models`, docs/architecture.md "agent-law"(드리밍 R2).
@Suite struct AgentLawDreamTests {
    typealias FakeAI = AgentLawCourtTests.FakeAI

    struct Fixture {
        let dir: URL
        var file: BoundLedgerFile
        let store = FakeLawObjectStore()
        let clock: ManualClock
        let decision: LedgerObject
        let knowledge: LedgerObject
        let other: LedgerObject

        var catalog: WorldBindingCatalog { WorldBindingCatalog(worlds: file.effectiveWorlds) }
        var stateDirectory: URL { dir.appendingPathComponent("dream-state") }

        func target(_ name: String) -> LawLedgerTarget { LawLedgerTarget(worldName: name, file: file) }
        var law: LawLedgerTarget { target("agent-law") }
        var person: LawLedgerTarget { target("agent-law-person-a") }

        func service(_ ai: FakeAI, settings: LawDreamSettings? = nil) -> LawDreamService {
            LawDreamService(
                file: file, settings: settings, runner: ai.runner, objectStore: store,
                stateStore: LawDreamStateStore(directory: stateDirectory), finish: { ["synced"] },
                appVersion: "9.9.9", clock: clock.clock)
        }

        var now: Date { clock.clock.now() }
        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    /// 2026-10-04 00:00:00 UTC.
    static let start = Date(timeIntervalSince1970: 1_791_072_000)
    static let agent = LawActor(
        author: "agent:claude@mac", kind: .agent, device: "mac", runtime: "claude-code",
        model: "claude-opus-5-5", effort: "high")
    static let codexAgent = LawActor(
        author: "agent:codex@mac", kind: .agent, device: "mac", runtime: "codex", model: "gpt-6", effort: "medium")
    static let human = LawActor(author: "user:tester", kind: .human, device: "mac")

    static func fixture(dreamDevice: String? = "mac") throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-law-dream-\(UUID().uuidString)", isDirectory: true)
        func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
        for name in ["law", "person-a"] {
            try FileManager.default.createDirectory(atPath: path(name), withIntermediateDirectories: true)
        }
        let legacy = LedgerStore(root: URL(fileURLWithPath: path("gujo-wiki")))
        let decision = try legacy.publish(author: "agent:old", title: "결정: 전신 판결", body: "전신 판결 본문")
        let knowledge = try legacy.publish(author: "agent:old", title: "전신 지식", body: "배포는 화요일에 한다")
        let other = try legacy.publish(author: "agent:old", title: "쓰이지 않은 전신", body: "다른 본문")
        let file = BoundLedgerFile(
            worlds: [
                BoundWorld(name: "gujo-wiki", rootPath: path("gujo-wiki"), layer: "remoteShared"),
                BoundWorld(name: "agent-law", rootPath: path("law"), key: "law", predecessor: "gujo-wiki"),
                BoundWorld(name: "agent-law-person-a", rootPath: path("person-a"), layer: "tenant",
                           parent: "agent-law", key: "person-a"),
            ],
            currentWorld: "agent-law", tenantMap: ["personal": "agent-law-person-a"],
            devices: ["mac", "mini"], currentDevice: "mac", dreamDevice: dreamDevice)
        return Fixture(dir: dir, file: file, clock: ManualClock(start), decision: decision, knowledge: knowledge, other: other)
    }

    /// 적재된 세션 하나(조각 + 적재 실행 요약)를 메모리 R2 에 둔다.
    static func seedSession(
        _ fx: Fixture, ledgerKey: String = "person-a", device: String = "mac", session: String, lines: [String]
    ) throws {
        let run = LawArchiveKeys.runVersion(fx.now)
        let archived = lines.enumerated().map { LawArchivedUtterance(index: $0.offset, role: $0.offset % 2 == 0 ? "user" : "assistant", text: $0.element) }
        let data = try LawSessionChunks.encode(archived)
        let key = LawArchiveKeys.chunk(ledgerKey: ledgerKey, device: device, runtime: "claude-code", sessionID: session, run: run)
        fx.store.seed(key, data)
        let manifest = LawArchiveManifest(
            kind: "archive", ledgerKey: ledgerKey, device: device, run: run, startedAt: "", finishedAt: "",
            enabledAt: LawTime.format(start),
            chunks: [LawArchiveManifest.Chunk(
                key: key, runtime: "claude-code", session: session, tenant: "personal", from: 0, to: lines.count,
                sha256: LawHash.sha256Hex(data), bytes: data.count)],
            unassigned: [:], failures: [])
        fx.store.seed(LawArchiveKeys.manifest(ledgerKey: ledgerKey, device: device, run: run),
                      try JSONEncoder().encode(manifest))
    }

    static func enact(
        _ fx: Fixture, _ target: LawLedgerTarget, title: String, type: String = "record", body: String = "본문",
        actor: LawActor = agent, origin: String? = nil, batch: String? = nil
    ) throws -> LawStoredRecord {
        try LawEnactService.enact(
            LawDraft(actor: actor, title: title, type: type, origin: origin, batch: batch, body: body),
            target: target, now: fx.now)
    }

    static func respond(_ proposals: [[String: Any]]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["proposals": proposals], options: [.sortedKeys])
        return "결과:\n```json\n" + String(decoding: data, as: UTF8.self) + "\n```"
    }

    static func prompt(_ spec: CommandSpecification) -> String {
        spec.arguments.joined(separator: " ") + String(decoding: spec.input ?? Data(), as: UTF8.self)
    }

    static func records(_ target: LawLedgerTarget) -> [LawStoredRecord] { target.store.scan() }

    // MARK: - 기기·실행 조건

    @Test func refusesOnNonDreamDevice() throws {
        var fx = try Self.fixture(dreamDevice: "mini")
        defer { fx.cleanup() }
        let ai = FakeAI([])
        #expect(throws: LawDreamError.notDreamDevice(current: "mac", dream: "mini")) {
            try fx.service(ai).run(trigger: .manual)
        }
        fx.file.dreamDevice = nil
        #expect(throws: LawDreamError.dreamDeviceUnset) { try fx.service(ai).run(trigger: .scheduled) }
        #expect(ai.calls == 0)
    }

    @Test func scheduledRunNeedsTwentyFourHoursAndNewSessions() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let ai = FakeAI(Array(repeating: Self.respond([]), count: 10))
        // 새 세션 없음 → 건너뜀(아무것도 쓰지 않음).
        let idle = try fx.service(ai).run(trigger: .scheduled)
        #expect(idle.skipped == "새로 적재된 세션 없음")
        #expect(ai.calls == 0)

        try Self.seedSession(fx, session: "s-1", lines: ["배포 순서를 정하자"])
        let first = try fx.service(ai).run(trigger: .scheduled)
        #expect(first.skipped == nil)
        #expect(ai.calls == 1)  // 새 세션이 있는 원장만 정리한다

        fx.clock.advance(3600)
        try Self.seedSession(fx, session: "s-2", lines: ["또 다른 대화"])
        let tooSoon = try fx.service(ai).run(trigger: .scheduled)
        #expect(tooSoon.skipped?.contains("24시간") == true)

        fx.clock.advance(24 * 3600)
        let due = try fx.service(ai).run(trigger: .scheduled)
        #expect(due.skipped == nil)
        #expect(due.ledgers.first { $0.world == "agent-law-person-a" }?.materials.chunks == 1)  // s-2 만(s-1 은 소비됨)

        // 직접 실행은 조건 없이 돈다.
        fx.clock.advance(60)
        let manual = try fx.service(ai).run(trigger: .manual)
        #expect(manual.skipped == nil)
        #expect(LawDreamTrigger.detect(environment: ["XPC_SERVICE_NAME": LawDreamTrigger.scheduleLabel]) == .scheduled)
        #expect(LawDreamTrigger.detect(environment: [:]) == .manual)
    }

    // MARK: - 재료

    @Test func materialsExcludeDreamRecordsAndFindPredecessors() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        _ = try Self.enact(fx, fx.person, title: "사람 기록", body: "사람 기록 본문 표지")
        _ = try Self.enact(
            fx, fx.person, title: "정리본", body: "정리본 본문 표지",
            actor: LawActor(author: "app:agent-wiki", kind: .app, device: "mac", runtime: "app", app: "agent-wiki", appVersion: "1"),
            origin: "dream")
        try Self.seedSession(fx, session: "s-1", lines: ["전신 \(fx.knowledge.id.prefix(12)) 를 봤다", "알겠습니다"])
        let ai = FakeAI([Self.respond([]), Self.respond([])])
        let outcome = try fx.service(ai).run(trigger: .manual)
        let person = try #require(outcome.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(person.materials.recentRecords == 1)
        #expect(person.materials.utterances == 2)
        #expect(person.materials.predecessors == [fx.knowledge.id])
        let prompt = Self.prompt(ai.specs.first { Self.prompt($0).contains("agent-law-person-a") }!)
        #expect(prompt.contains("사람 기록 본문 표지"))
        #expect(!prompt.contains("정리본 본문 표지"))
        #expect(prompt.contains("배포는 화요일에 한다"))
    }

    // MARK: - 할 수 없는 것

    @Test func forbiddenProposalsAreDiscardedOrRerouted() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let judgment = try Self.enact(fx, fx.law, title: "판결", type: "judgment", body: "판결 본문")
        let userRecord = try Self.enact(fx, fx.law, title: "사용자 기록", body: "사용자 말", actor: Self.human)
        let article = try Self.enact(fx, fx.law, title: "조문", type: "article", body: "조문 본문")
        let dream = try Self.enact(
            fx, fx.law, title: "정리본", body: "정리본",
            actor: LawActor(author: "app:agent-wiki", kind: .app, device: "mac", runtime: "app", app: "agent-wiki", appVersion: "1"),
            origin: "dream")
        try Self.seedSession(fx, ledgerKey: "law", session: "s-1", lines: ["\(fx.decision.id.prefix(12)) 판결을 옮기자"])
        let ai = FakeAI([Self.respond([
            ["kind": "amend", "target": String(judgment.id.prefix(8)), "body": "판결 고침"],
            ["kind": "repeal", "target": String(userRecord.id.prefix(8)), "reason": "틀렸다"],
            ["kind": "amend", "target": String(article.id.prefix(8)), "body": "조문 고침", "scope": "agent-law"],
            ["kind": "migrate", "target": String(fx.decision.id.prefix(8)), "subject": "project", "certainty": "probable",
             "domain": "dev-workflow", "reason": "쓰임"],
            ["kind": "enact", "title": "새 지식", "body": "본문", "cites": [["id": String(dream.id.prefix(8)), "rel": "testifies"]]],
            ["kind": "enact", "title": "판결 새로", "type": "judgment", "body": "x"],
            ["kind": "amend", "target": "docs/business-rules.md", "body": "저장소 조문 고침"],
        ]), Self.respond([])])
        let outcome = try fx.service(ai).run(trigger: .manual)
        let law = try #require(outcome.ledgers.first { $0.world == "agent-law" })
        #expect(Set(law.applied.map(\.kind)) == ["propose", "appeal"])
        #expect(law.applied.count == 3)
        #expect(law.discarded.count == 4)
        #expect(law.discarded.contains { $0.reason.contains("judgment") })
        #expect(law.discarded.contains { $0.reason.contains("정리본") })
        #expect(law.discarded.contains { $0.reason.contains("저장소의 판결·조문은 고칠 수 없다") })

        let records = Self.records(fx.law)
        let view = LawLedgerView(records: records)
        #expect(view.isInForce(judgment.id) && view.isInForce(userRecord.id) && view.isInForce(article.id))
        let proposals = records.filter { $0.record.type == "proposal" }
        #expect(Set(proposals.flatMap { $0.record.cites.map(\.id) }) == [userRecord.id, article.id])
        let appeal = try #require(records.first { $0.record.type == "appeal" })
        #expect(appeal.record.cites == [LawCite(id: fx.decision.id, rel: "appeals")])
        #expect(appeal.record.body.contains("이관 신청"))
        #expect(!records.contains { $0.record.origin == "migration" })
    }

    // MARK: - 안전장치

    @Test func capsChangesAndCarriesOverflowToNextRun() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.seedSession(fx, session: "s-1", lines: ["많이 배웠다"])
        let many = (1...12).map { ["kind": "enact", "title": "지식 \($0)", "body": "본문 \($0)"] as [String: Any] }
        let ai = FakeAI([Self.respond([]), Self.respond(many), Self.respond([]), Self.respond([])])
        let first = try fx.service(ai).run(trigger: .manual)
        let person = try #require(first.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(person.applied.count == 10)
        #expect(person.deferred == 2)
        #expect(LawDreamStateStore(directory: fx.stateDirectory).load()?.deferred.count == 2)

        fx.clock.advance(60)
        let second = try fx.service(ai).run(trigger: .manual)
        let carried = try #require(second.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(carried.applied.count == 2)
        #expect(LawDreamStateStore(directory: fx.stateDirectory).load()?.deferred.isEmpty == true)
        #expect(Self.records(fx.person).filter { $0.record.title?.hasPrefix("지식 ") == true }.count == 12)
    }

    @Test func tooManyRepealsBlocksBatchAndRaisesAlert() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let targets = try (1...4).map { try Self.enact(fx, fx.person, title: "옛 기록 \($0)", body: "옛 \($0)") }
        try Self.seedSession(fx, session: "s-1", lines: ["정리하자"])
        let ai = FakeAI([Self.respond([]), Self.respond(targets.map {
            ["kind": "repeal", "target": String($0.id.prefix(8)), "reason": "중복"] as [String: Any]
        })])
        let outcome = try fx.service(ai).run(trigger: .manual)
        let person = try #require(outcome.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(person.applied.isEmpty)
        #expect(person.alerts.contains { $0.contains("폐지 4건") })
        let view = LawLedgerView(records: Self.records(fx.person))
        #expect(targets.allSatisfy { view.isInForce($0.id) })
        let contents = try #require(LawContents.current(in: Self.records(fx.person)))
        #expect(contents.record.body.hasPrefix("경보: 드리밍 묶음의 폐지 4건"))
    }

    @Test func restoredDreamBatchPausesUntilHumanResumes() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.seedSession(fx, session: "s-1", lines: ["새 사실"])
        // 예약 실행은 새 세션이 있는 원장(person-a)만 정리한다 — 첫 응답이 그 원장의 것.
        let ai = FakeAI([Self.respond([["kind": "enact", "title": "드리밍 지식", "body": "본문"]])]
                        + Array(repeating: Self.respond([]), count: 6))
        let first = try fx.service(ai).run(trigger: .scheduled)
        let batch = try #require(first.batch)
        #expect(!fx.service(ai).pause().isPaused)

        fx.clock.advance(60)
        let restored = try LawEnactService.restore(batch: batch, actor: Self.agent, target: fx.person, now: fx.now)
        let pause = fx.service(ai).pause()
        #expect(pause.unacknowledgedRestores == restored.map(\.id))
        #expect(fx.service(ai).status().paused)

        fx.clock.advance(25 * 3600)
        try Self.seedSession(fx, session: "s-2", lines: ["또"])
        let blocked = try fx.service(ai).run(trigger: .scheduled)
        #expect(blocked.skipped?.contains("정지") == true)

        #expect(throws: LawDreamError.notHuman("agent:claude@mac")) {
            try fx.service(ai).resume(actor: Self.agent, target: fx.law)
        }
        let resumed = try #require(try fx.service(ai).resume(actor: Self.human, target: fx.law))
        #expect(resumed.record.authorKind == "human")
        #expect(!fx.service(ai).pause().isPaused)
        #expect(try fx.service(ai).resume(actor: Self.human, target: fx.law) == nil)
        let again = try fx.service(ai).run(trigger: .scheduled)
        #expect(again.skipped == nil)
    }

    // MARK: - 이관

    @Test func migrationOnlyForUsedPredecessorsIntoOwningLedger() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        // 테넌트 세션이 공유 원장의 전신 객체를 인용 → 이관은 그 전신을 가진 공유 원장으로 고정.
        try Self.seedSession(fx, session: "s-1", lines: ["\(fx.knowledge.id.prefix(10)) 참고"])
        let migrate: [String: Any] = [
            "kind": "migrate", "target": String(fx.knowledge.id.prefix(8)), "subject": "project",
            "certainty": "confirmed", "domain": "dev-workflow", "reason": "세션에서 다시 쓰임",
        ]
        let unused: [String: Any] = [
            "kind": "migrate", "target": String(fx.other.id.prefix(8)), "subject": "project",
            "certainty": "confirmed", "domain": "dev-workflow", "reason": "x",
        ]
        let ai = FakeAI([Self.respond([]), Self.respond([migrate, unused]), Self.respond([]), Self.respond([migrate])])
        let outcome = try fx.service(ai).run(trigger: .manual)
        let person = try #require(outcome.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(person.migrations == 1)
        #expect(person.discarded.contains { $0.reason.contains("쓰일 때만 이관") })
        #expect(Self.records(fx.person).allSatisfy { $0.record.origin != "migration" })

        let lawRecords = Self.records(fx.law)
        let migrated = try #require(lawRecords.first { $0.record.origin == "migration" })
        #expect(migrated.record.cites == [LawCite(id: fx.knowledge.id, rel: "migrated-from")])
        #expect(migrated.record.body == "배포는 화요일에 한다\n" || migrated.record.body == "배포는 화요일에 한다")
        let finding = try #require(lawRecords.first { $0.record.type == "finding" })
        #expect(finding.record.cites == [LawCite(id: migrated.id, rel: "finds")])
        #expect(LawLedgerView(records: lawRecords).currentFinding(for: migrated.id)?.id == finding.id)

        fx.clock.advance(60)
        try Self.seedSession(fx, session: "s-2", lines: ["\(fx.knowledge.id.prefix(10)) 다시 참고"])
        let again = try fx.service(ai).run(trigger: .manual)
        #expect(again.ledgers.first { $0.world == "agent-law-person-a" }?.discarded.contains { $0.reason.contains("이미 이관됨") } == true)
    }

    // MARK: - 목차

    @Test func contentsLinesFormatLimitsAndNoticesFirst() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let long = String(repeating: "가", count: 300)
        let first = try Self.enact(fx, fx.law, title: long, body: "긴 제목")
        for index in 1...6 {
            fx.clock.advance(1)
            _ = try Self.enact(fx, fx.law, title: "기록 \(index)", body: "본문 \(index)")
        }
        // 대법원 회부(다른 중재자 없음) + 이의 기간 중 개정안.
        let court = LawCourtService(
            target: fx.law, settings: LawCourtSettings(arbiters: [LawArbiterCandidate(cli: .claude, model: "claude-opus-5-5")]),
            runner: FakeAI([]).runner, appVersion: "9.9.9")
        fx.clock.advance(1)
        let appeal = try court.appeal(first.id, reason: "이의", actor: Self.agent, now: fx.now)
        _ = court.hear(now: fx.now)
        let proposal = try court.propose(first.id, scope: "전체", content: "새 본문", actor: Self.agent, now: fx.now)

        let all = LawContents.lines(for: fx.law, maxLines: 200, now: fx.now)
        #expect(all.allSatisfy { $0.count <= 150 })
        #expect(all[0].hasPrefix("대법원 공지: \(appeal.id.prefix(8))"))
        #expect(all.contains { $0.hasPrefix("이의 기간 개정안: \(proposal.id.prefix(8))") })
        let firstLine = try #require(all.first { $0.hasPrefix(String(first.id.prefix(8))) })
        #expect(firstLine.count == 150 && firstLine.hasSuffix("…"))

        let short = LawContents.lines(for: fx.law, maxLines: 5, now: fx.now)
        #expect(short.count == 5)
        #expect(short.last?.hasPrefix("… 외") == true)
        #expect(LawContents.lines(
            records: [], notices: LawCourtNotices(supreme: [], proposalsInObjection: []), alerts: ["a", "b", "c"],
            maxLines: 2, objectionPeriod: 0) == ["경보: a", "… 공지 2건 더"])
    }

    @Test func contentsPublishAmendsPreviousAndHookShowsLedgers() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        _ = try Self.enact(fx, fx.person, title: "개인 기록")
        _ = try Self.enact(fx, fx.law, title: "공유 기록")
        try Self.seedSession(fx, session: "s-1", lines: ["안녕"])
        let ai = FakeAI([Self.respond([]), Self.respond([]), Self.respond([]), Self.respond([])])
        let outcome = try fx.service(ai).run(trigger: .manual)
        let personContents = try #require(outcome.ledgers.first { $0.world == "agent-law-person-a" }?.contents)
        #expect(Self.records(fx.person).first { $0.id == personContents }?.record.amends == nil)

        fx.clock.advance(60)
        _ = try Self.enact(fx, fx.person, title: "개인 기록 2")
        let second = try fx.service(ai).run(trigger: .manual)
        let next = try #require(second.ledgers.first { $0.world == "agent-law-person-a" }?.contents)
        #expect(Self.records(fx.person).first { $0.id == next }?.record.amends == personContents)
        #expect(LawContents.current(in: Self.records(fx.person))?.id == next)

        let text = LawContents.sessionStartText(tenant: nil, file: fx.file, catalog: fx.catalog)
        #expect(text.contains("# agent-law 목차 — agent-law-person-a"))
        #expect(text.contains("# agent-law 목차 — agent-law\n"))
        #expect(text.contains("개인 기록 2") && text.contains("공유 기록"))
        #expect(LawContents.sessionLedgers(tenant: "acme", file: fx.file, catalog: fx.catalog) == ["agent-law"])
    }

    // MARK: - 보고·기록

    @Test func dreamRecordsCarryAuthorModelAndReportContent() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let old = try Self.enact(fx, fx.person, title: "옛 기록", body: "옛 본문")
        let judged = try Self.enact(fx, fx.person, title: "판단할 기록", body: "판단 본문")
        try Self.seedSession(fx, session: "s-1", lines: ["새 지식을 배웠다"])
        let ai = FakeAI([Self.respond([]), Self.respond([
            ["kind": "enact", "title": "새 지식", "body": "새 본문"],
            ["kind": "amend", "target": String(old.id.prefix(8)), "body": "고친 본문"],
            ["kind": "finding", "target": String(judged.id.prefix(8)), "subject": "project", "certainty": "probable",
             "domain": "dev-workflow", "reason": "세션"],
            ["kind": "alert", "message": "저장소 판결 2026-0001 과 원장이 어긋남"],
            ["kind": "bogus"],
        ])])
        let outcome = try fx.service(ai, settings: LawDreamSettings(model: "claude-sonnet-5-5", effort: "max"))
            .run(trigger: .manual)
        #expect(outcome.ok)
        let person = try #require(outcome.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(person.applied.map(\.kind) == ["enact", "amend", "finding"])
        let records = Self.records(fx.person)
        for id in person.applied.flatMap(\.ids) {
            let record = try #require(records.first { $0.id == id }?.record)
            #expect(record.author == "app:agent-wiki")
            #expect(record.authorKind == "app")
            #expect(record.runtime == "claude-code")
            #expect(record.model == "claude-sonnet-5-5")
            #expect(record.effort == "max")
            #expect(record.app == "agent-wiki" && record.appVersion == "9.9.9")
            #expect(record.origin == "dream")
            #expect(record.batch == outcome.batch)
        }
        let contents = try #require(records.first { $0.id == person.contents }?.record)
        #expect(contents.model == nil && contents.runtime == "app")
        let report = try #require(records.first { $0.id == person.report }?.record)
        #expect(report.type == "report" && report.model == "claude-sonnet-5-5" && report.origin == "dream")
        for part in ["batch: \(outcome.batch ?? "")", "## 읽은 재료", "## 적용한 변경 3건", "## 버린 제안",
                     "모르는 제안 종류: bogus", "경보: 저장소 판결 2026-0001", "## 이관 0건", "## 적재 보고"] {
            #expect(report.body.contains(part))
        }
        #expect(LawDreamMarks(records: records).dreamBatches == [outcome.batch!])
        #expect(LawDreamMarks(records: records).openAlerts == ["저장소 판결 2026-0001 과 원장이 어긋남"])
    }

    @Test func malformedAIResponseEnactsNothingAndRetriesMaterials() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.seedSession(fx, session: "s-1", lines: ["새 사실"])
        let before = Self.records(fx.person).count
        let ai = FakeAI([Self.respond([]), "모르겠습니다", Self.respond([]), Self.respond([])])
        let outcome = try fx.service(ai).run(trigger: .manual)
        #expect(!outcome.ok)
        let person = try #require(outcome.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(person.aiError != nil)
        #expect(person.contents == nil && person.report == nil)
        #expect(Self.records(fx.person).count == before)

        fx.clock.advance(60)
        let retry = try fx.service(ai).run(trigger: .manual)
        #expect(retry.ledgers.first { $0.world == "agent-law-person-a" }?.materials.chunks == 1)
    }

    @Test func runSummaryIsWrittenLastAfterSync() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.seedSession(fx, session: "s-1", lines: ["새 사실"])
        let ai = FakeAI([Self.respond([]), Self.respond([])])
        let outcome = try fx.service(ai).run(trigger: .manual)
        let run = try #require(outcome.run)
        let dreamWrites = fx.store.writes.filter { $0.contains("/runs/dream/\(run)/") }
        #expect(dreamWrites.suffix(outcome.summaries.count).allSatisfy { $0.hasSuffix("/summary.json") })
        #expect(dreamWrites.filter { $0.hasSuffix("/summary.json") }.count == 2)
        #expect(dreamWrites.contains("person-a/runs/dream/\(run)/materials.json"))
        let summary = try JSONDecoder().decode(
            LawDreamSummary.self, from: try #require(fx.store.object("person-a/runs/dream/\(run)/summary.json")))
        #expect(summary.sync == ["synced"])
        #expect(summary.consumedManifests.count == 1)
        // 로컬 상태가 없으면 R2 요약에서 다시 만든다.
        try FileManager.default.removeItem(at: fx.stateDirectory)
        let rebuilt = try #require(try LawDreamState.rebuild(store: fx.store, ledgerKeys: ["law", "person-a"]))
        #expect(rebuilt.lastRun == run)
        #expect(rebuilt.consumedManifests == summary.consumedManifests)
    }

    @Test func statusShowsLastNextPauseAndAlerts() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let ai = FakeAI([Self.respond([["kind": "alert", "message": "확인 필요"]]), Self.respond([])])
        let empty = fx.service(ai).status()
        #expect(empty.lastRun == nil && empty.nextDue == nil && !empty.paused && empty.isDreamDevice)
        let outcome = try fx.service(ai).run(trigger: .manual)
        let status = fx.service(ai).status()
        #expect(status.lastRun == outcome.run)
        #expect(status.nextDue == LawTime.format(fx.now.addingTimeInterval(24 * 3600)))
        #expect(status.alerts == [LawDreamAlertEntry(world: "agent-law", alert: "확인 필요")])
        #expect(status.runner == "claude:claude-opus-5-5:high")
    }

    // MARK: - report models

    @Test func modelReportCountsAmendRepealAndOverturnRates() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let a1 = try Self.enact(fx, fx.law, title: "a1")
        let a2 = try Self.enact(fx, fx.law, title: "a2")
        let a3 = try Self.enact(fx, fx.law, title: "a3")
        let a4 = try Self.enact(fx, fx.law, title: "a4")
        _ = try Self.enact(fx, fx.law, title: "c1", actor: Self.codexAgent)
        fx.clock.advance(1)
        _ = try LawEnactService.enact(
            LawDraft(actor: Self.codexAgent, title: "a1 개정", amends: a1.id, body: "개정"), target: fx.law, now: fx.now)
        _ = try LawEnactService.enact(
            LawDraft(actor: Self.codexAgent, title: "폐지", repeals: a2.id, body: "x"), target: fx.law, now: fx.now)
        let court = LawCourtService(target: fx.law, runner: FakeAI([]).runner, appVersion: "9.9.9")
        let appeal = try court.appeal(a3.id, reason: "틀림", actor: Self.codexAgent, now: fx.now)
        _ = try LawEnactService.enact(LawDraft(
            actor: LawActor(author: "app:agent-wiki", kind: .app, device: "mac", runtime: "codex", model: "gpt-6",
                            effort: "high", app: "agent-wiki", appVersion: "1"),
            title: "항소심 결정", type: "ruling",
            cites: [LawCite(id: appeal.id, rel: "hears"), LawCite(id: a3.id)],
            body: "level: appellate\noutcome: overturn\n\n뒤집음\n"), target: fx.law, path: .court, now: fx.now)

        let rows = LawModelReport.rows(records: Self.records(fx.law))
        let opus = try #require(rows.first { $0.model == "claude-opus-5-5" })
        #expect(opus.runtime == "claude-code" && opus.effort == "high")
        #expect(opus.enacted == 4)
        #expect(opus.amendedRate == 0.25 && opus.repealedRate == 0.25 && opus.overturnedRate == 0.25)
        let codex = try #require(rows.first { $0.model == "gpt-6" && $0.runtime == "codex" })
        #expect(codex.enacted == 2)  // c1 + a1 개정(폐지 기록은 세지 않는다)
        #expect(codex.amended == 0 && codex.repealed == 0)
        _ = a4
        let since = LawModelReport.rows(records: Self.records(fx.law), since: fx.now)
        #expect(since.first { $0.model == "claude-opus-5-5" } == nil)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(opus)) as? [String: Any]
        #expect(json?["amendedRate"] as? Double == 0.25)
    }

    @Test func settingsRoundTripInHostFile() throws {
        let settings = LawDreamSettings(cli: .codex, model: "gpt-6", effort: "xhigh", intervalHours: 12, maxChanges: 5,
                                        maxRepeals: 1, contentsMaxLines: 50, repositories: ["/repo"])
        let file = BoundLedgerFile(dreamDevice: "mac", dream: settings)
        let decoded = try JSONDecoder().decode(BoundLedgerFile.self, from: JSONEncoder().encode(file))
        #expect(decoded.dream == settings)
        #expect(decoded.dreamDevice == "mac")
        #expect(settings.interval == 12 * 3600 && settings.resolvedMaxChanges == 5)
        #expect(LawDreamSettings().resolvedMaxChanges == 10 && LawDreamSettings().resolvedMaxRepeals == 3)
        #expect(LawDreamSettings().resolvedContentsMaxLines == 200 && LawDreamSettings().interval == 24 * 3600)
        let request = settings.request(prompt: "p")
        #expect(request.modelRecord == LawModelRecord(runtime: "codex", model: "gpt-6", effort: "xhigh"))
    }
}
