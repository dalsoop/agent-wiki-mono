import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// ledger 3 원장 화면의 표시 모델 시험 — 원장 종류 판정, 목차, 기록 상세(출처 패널), 기록 목록, 심급, 드리밍(보고 본문 왕복·상태·
/// 이력·묶음 기록·여러 원장 되돌리기·재개), 모델 신빙성, 빈 상태.
/// 실제 원장·설정·AI·R2·세션은 쓰지 않는다(임시 루트·주입 실행기·메모리 R2).
/// 근거: docs/business-rules.md "# agent-law(ledger 3)" — "드리밍"·"심급제"·"사실인정과 4종류"·"전신"·"공포·개정·폐지·원상회복".
@Suite struct AgentLawScreenTests {
    typealias Court = AgentLawCourtTests
    typealias Dream = AgentLawDreamTests
    typealias FakeAI = AgentLawCourtTests.FakeAI

    static let contentsActor = LawActor(
        author: "app:agent-wiki", kind: .app, device: "mac", runtime: "app", app: "agent-wiki", appVersion: "1")

    static func finding(_ target: LawLedgerTarget, of id: String, subject: String = "project", at date: Date) throws
        -> LawStoredRecord {
        try LawEnactService.enact(LawDraft(
            actor: Court.opus, title: "사실인정", type: "finding", cites: [LawCite(id: id, rel: "finds")],
            body: "subject: \(subject)\ncertainty: probable\ndomain: dev-workflow\nreason: 시험\n"),
            target: target, path: .finding, now: date)
    }

    // MARK: - 원장 종류 판정

    @Test func screenKindFollowsConfigurationNotFolderShape() {
        let catalog = WorldBindingCatalog(worlds: [
            BoundWorld(name: "gujo-wiki", rootPath: "/tmp/x-gujo", layer: "remoteShared"),
            BoundWorld(name: "agent-law", rootPath: "/tmp/x-law", key: "law", predecessor: "gujo-wiki"),
            BoundWorld(name: "repo-wiki", rootPath: "/tmp/x-repo/.wiki"),
            BoundWorld(name: "agent-law-person-a", rootPath: "/tmp/x-p", layer: "tenant", parent: "agent-law", key: "person-a"),
        ])
        let law = LawLedgerScreenKind(worldName: "agent-law", catalog: catalog)
        #expect(law.usesLawScreens && law.menus == [.contents, .records, .court, .dream, .credibility])
        #expect(!law.mayInspectRepository)  // ledger 3 원장은 저장소 위키가 아니다
        #expect(!law.isArchived && !law.isReadOnly)
        #expect(law.recordedLayer == nil)  // 층이 기록되지 않았으면 이름으로 추정하지 않는다
        #expect(LawLedgerScreenKind(worldName: "agent-law-person-a", catalog: catalog).recordedLayer == .tenant)

        let legacy = LawLedgerScreenKind(worldName: "gujo-wiki", catalog: catalog)
        #expect(!legacy.usesLawScreens && legacy.menus.isEmpty)
        #expect(legacy.isArchived && legacy.isReadOnly)
        #expect(legacy.recordedLayer == .remoteShared)

        let repo = LawLedgerScreenKind(worldName: "repo-wiki", catalog: catalog)
        #expect(!repo.usesLawScreens && repo.mayInspectRepository && !repo.isReadOnly)
    }

    // MARK: - 목차

    @Test func contentsComputedWhenNoContentsRecordThenCurrentRecord() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let first = try Court.enact(fx, title: "첫 지식", at: 0)
        let second = try Court.enact(fx, title: "둘째 지식", at: 1)
        _ = try Self.finding(fx.target, of: first.id, at: Court.at(2))
        let now = Court.at(5)

        let computed = LawContentsScreen.load(target: fx.target, now: now)
        #expect(computed.isComputed && computed.contentsRecordID == nil)
        #expect(computed.summary == LawLedgerSummary(knowledgeInForce: 2, pendingJudgment: 1, violations: 0))
        #expect(!computed.isEmptyLedger)
        #expect(computed.pending.isEmpty)
        let linked = computed.lines.compactMap(\.recordID)
        #expect(Set(linked) == [first.id, second.id])
        #expect(computed.recordID(forPrefix: String(second.id.prefix(8))) == second.id)
        #expect(computed.recordID(forPrefix: "zz") == nil)

        _ = try LawContents.publish(
            lines: LawContents.lines(for: fx.target, maxLines: 200, now: now), target: fx.target,
            actor: Self.contentsActor, now: Court.at(6))
        let current = LawContentsScreen.load(target: fx.target, now: Court.at(7))
        #expect(!current.isComputed)
        let contents = try #require(LawContents.current(in: fx.records))
        #expect(current.contentsRecordID == contents.id)
        #expect(current.lines.map(\.text) == contents.record.body.split(separator: "\n").map(String.init))
        #expect(Set(current.lines.compactMap(\.recordID)) == [first.id, second.id])
        // 목차 기록은 지식 기록이 아니므로 요약 수는 그대로다.
        #expect(current.summary.knowledgeInForce == 2)
    }

    @Test func contentsPendingDecisionsShowSupremeAndObjectionWindow() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let (_, proposal) = try Court.referredArticleProposal(fx)
        let now = Court.at(10 + 2 * Court.hour)
        let screen = LawContentsScreen.load(target: fx.target, now: now)
        #expect(screen.pending.supreme.map(\.id) == [proposal.id])
        let window = try #require(screen.pending.objections.first)
        #expect(window.proposal.id == proposal.id)
        #expect(window.endsAt == Court.at(10 + 72 * Court.hour))
        #expect(window.remaining == 70 * Court.hour)
        #expect(!screen.pending.dreamingPaused)
        // 공지 줄의 id 앞자리도 그 기록으로 간다.
        #expect(screen.lines.contains { $0.recordID == proposal.id })
        #expect(LawContentsScreen.idPrefix(ofLine: "대법원 공지: \(proposal.id.prefix(8)) 제목") == String(proposal.id.prefix(8)))
        #expect(LawContentsScreen.idPrefix(ofLine: "경보: 무언가") == nil)
    }

    @Test func emptyLedgerScreens() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let contents = LawContentsScreen.load(target: fx.target, now: Court.at(0))
        #expect(contents.isEmptyLedger && contents.isComputed && contents.lines.isEmpty)
        #expect(contents.summary == LawLedgerSummary(knowledgeInForce: 0, pendingJudgment: 0, violations: 0))
        #expect(LawCourtScreen.load(target: fx.target).isEmpty)
        #expect(LawCredibilityScreen.load(target: fx.target, period: .all, now: Court.at(0)).isEmpty)
        #expect(LawRecordList.load(target: fx.target, filter: LawRecordListFilter()).isEmpty)
        #expect(LawRecordDetail.load(id: String(repeating: "a", count: 64), target: fx.target) == nil)
        let file = try #require(fx.target.file)
        let dream = LawDreamScreen.load(file: file, catalog: fx.target.catalog)
        #expect(dream.runs.isEmpty && dream.lastRunAt == nil && dream.nextDueAt == nil && !dream.paused)
        #expect(dream.gaps == [.dreamDevice, .ai, .storageEndpoint])
        #expect(dream.gaps.map(\.guidance).allSatisfy { $0.contains("agent-wiki world") })
    }

    // MARK: - 기록 상세

    @Test func recordDetailProvenancePanel() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let evidence = try Court.userEvidence(fx, at: 0)
        let a1 = try Court.enact(fx, title: "갈래 A", body: "A1", at: 1)
        let a2 = try LawEnactService.enact(
            LawDraft(actor: Court.opus, title: "갈래 A", amends: a1.id, body: "A2"), target: fx.target, now: Court.at(2))
        let b = try Court.enact(fx, title: "갈래 B", body: "B", at: 3)
        let merged = try fx.target.store.enact(
            LawDraft(actor: Court.opus, speaker: "user", title: "병합", cites: [LawCite(id: evidence.id, rel: "testifies")],
                     amends: a2.id, amendsAlso: [b.id], body: "병합 본문"),
            now: Court.at(4), context: LawEnactContext(testimony: Court.FakeTestimony()))
        let finding = try Self.finding(fx.target, of: merged.id, subject: "agent-self", at: Court.at(5))
        let appeal = try fx.service(FakeAI([])).appeal(merged.id, reason: "이의", actor: Court.opus, now: Court.at(6))
        _ = fx.service(FakeAI([#"{"outcome":"uphold","reason":"유지"}"#])).hear(now: Court.at(7))
        let proposal = try fx.service(FakeAI([])).propose(
            merged.id, scope: "본문", content: "새 본문", actor: Court.opus, now: Court.at(8))

        let detail = try #require(LawRecordDetail.load(id: String(merged.id.prefix(10)), target: fx.target))
        #expect(detail.record.id == merged.id && detail.isInForce && detail.world == "agent-law")
        #expect(detail.provenance.author == "agent:claude@mac" && detail.provenance.authorKind == "agent")
        #expect(detail.provenance.model == "claude-opus-5-5" && detail.provenance.effort == "high")
        #expect(detail.provenance.runtime == "claude-code" && detail.provenance.device == "mac")
        #expect(detail.provenance.speaker == "user" && detail.provenance.promulgated == Court.at(4))

        let testimony = try #require(detail.testimonies.first)
        #expect(testimony.evidenceID == evidence.id && testimony.found && testimony.speaker == "user")
        #expect(testimony.session == "s-1" && testimony.utteranceAt == "2026-10-04T00:00:00Z")
        #expect(testimony.quote == "인용")
        #expect(!testimony.exhibitMissing)
        // 증거물 파일이 이 기기에 없으면 "증거물 없음(동기화 전)".
        let records = fx.records
        let offline = try #require(LawRecordDetail.make(
            id: merged.id, world: "agent-law", records: records, docket: LawCourtDocket(records: records),
            exhibitExists: { _, _ in false }))
        #expect(offline.testimonies.first?.missingExhibits == evidence.record.exhibits)

        let current = try #require(detail.finding)
        #expect(current.id == finding.id && current.subject == "agent-self" && current.domain == "dev-workflow")
        #expect(current.reason == "시험" && current.provenance.model == "claude-opus-5-5")
        #expect(detail.memoryKind == .feedback)  // speaker user + agent-self = 지적

        #expect(detail.history.map(\.record.id) == [merged.id, a2.id, a1.id])
        #expect(detail.history.first?.mergedBranches.map(\.id) == [b.id])
        #expect(detail.history.dropFirst().allSatisfy { !$0.isInForce })

        #expect(detail.disputes.map(\.caseRecord.id) == [appeal.id, proposal.id])
        let closed = try #require(detail.disputes.first?.closed)
        #expect(closed.outcome == .uphold && closed.decidingModel == "claude-sonnet-5-5")
        #expect(detail.disputes.first?.rulings.count == 1)
        #expect(detail.disputes.last?.openLevel == .appellate && detail.disputes.last?.closed == nil)

        #expect(detail.cites.contains { $0.id == evidence.id && $0.rel == "testifies" && $0.title == "증언" })
        let citedBy = Set(detail.citedBy.map { "\($0.rel) \($0.id)" })
        #expect(citedBy.isSuperset(of: ["finds \(finding.id)", "appeals \(appeal.id)", "proposes \(proposal.id)"]))
    }

    // MARK: - 심급

    @Test func courtScreenClosedCasesUseEngineValidity() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let target = try Court.enact(fx, at: 0)
        let upheld = try fx.service(FakeAI([])).appeal(target.id, reason: "이의", actor: Court.opus, now: Court.at(1))
        let ruling = try #require(fx.service(FakeAI([#"{"outcome":"uphold","reason":"유지"}"#]))
            .hear(now: Court.at(2)).decided.first?.ruling)
        // 위조 결정 — 에이전트가 직접 쓴 항소심 결정은 사건을 닫지 않는다.
        let other = try Court.enact(fx, title: "다른 기록", at: 3)
        let forgedCase = try fx.service(FakeAI([])).appeal(other.id, reason: "이의", actor: Court.opus, now: Court.at(4))
        _ = try fx.target.store.enact(LawDraft(
            actor: Court.opus, title: "위조 결정", type: "ruling", cites: [LawCite(id: forgedCase.id, rel: "hears")],
            body: "level: appellate\noutcome: uphold\n\n위조\n"), now: Court.at(5))
        // 상고 → 대법원 결정(사용자 증언).
        let finalAppeal = try fx.service(FakeAI([])).appeal(ruling.id, reason: "상고", actor: Court.opus, now: Court.at(6))
        let evidence = try Court.userEvidence(fx, at: 7)
        let decision = try fx.service(FakeAI([])).decide(
            caseID: finalAppeal.id, approve: false, testimony: evidence.id, actor: Court.human,
            now: Court.at(6 + 73 * Court.hour))

        let screen = LawCourtScreen.load(target: fx.target)
        #expect(screen.appellate.map(\.id) == [forgedCase.id])
        #expect(screen.supreme.isEmpty)
        #expect(Set(screen.closed.map(\.id)) == [upheld.id, finalAppeal.id])
        #expect(!screen.closed.contains { $0.id == forgedCase.id })
        let supremeClosed = try #require(screen.closed.first { $0.id == finalAppeal.id })
        #expect(supremeClosed.level == .supreme && supremeClosed.outcome == .reject)
        #expect(supremeClosed.ruling.id == decision.ruling.id && supremeClosed.testimonies == [evidence.id])
        let appellateClosed = try #require(screen.closed.first { $0.id == upheld.id })
        #expect(appellateClosed.level == .appellate && appellateClosed.decidingModel == "claude-sonnet-5-5")
        #expect(screen.closed.first?.id == finalAppeal.id)  // 결정 시각 새것 먼저
    }

    // MARK: - 기록 목록

    @Test func recordListSearchIncludesPredecessorsAndFilters() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let rule = try Dream.enact(fx, fx.law, title: "배포 규칙", body: "배포는 화요일에 한다")
        let article = try Dream.enact(fx, fx.law, title: "배포 조문", type: "article", body: "배포 조문 본문")
        _ = try Self.finding(fx.law, of: rule.id, at: fx.now)
        let personal = try Dream.enact(fx, fx.person, title: "개인 메모", body: "개인 배포 메모")

        let all = LawRecordList.load(target: fx.law, filter: LawRecordListFilter())
        #expect(Set(all.map(\.id)) == [rule.id, article.id])
        #expect(all.allSatisfy { $0.scopeMark.isEmpty && $0.score == nil })

        let hits = LawRecordList.load(target: fx.law, filter: LawRecordListFilter(query: "배포"))
        #expect(hits.contains { $0.id == rule.id && $0.scopeMark.isEmpty })
        let predecessor = try #require(hits.first { $0.id == fx.knowledge.id })
        #expect(predecessor.isPredecessor && predecessor.scopeMark == "[전신 gujo-wiki]" && predecessor.memoryKind == nil)
        #expect(!hits.contains { $0.id == personal.id })  // 하위 원장은 범위 밖
        // CLI 와 같은 엔진 검색.
        let index = LawScopeIndex(current: "agent-law", catalog: fx.catalog)
        let engine = LawScopedSearch.hits(index: index, parsed: WorldScopedSearchParse(queryText: "배포", limit: 50))
        #expect(engine.contains { $0.item.id == fx.knowledge.id && $0.item.isPredecessor })

        let noPredecessors = LawRecordList.load(
            target: fx.law, filter: LawRecordListFilter(query: "배포", includePredecessors: false))
        #expect(!noPredecessors.contains { $0.isPredecessor })

        let projects = LawRecordList.load(target: fx.law, filter: LawRecordListFilter(memoryKind: .project))
        #expect(projects.map(\.id) == [rule.id])
        #expect(LawRecordList.load(target: fx.law, filter: LawRecordListFilter(memoryKind: .person)).isEmpty)
        let articles = LawRecordList.load(target: fx.law, filter: LawRecordListFilter(type: .article))
        #expect(articles.map(\.id) == [article.id])
        let typedSearch = LawRecordList.load(target: fx.law, filter: LawRecordListFilter(query: "배포", type: .record))
        #expect(typedSearch.map(\.id) == [rule.id])  // 유형 거르기는 전신 객체를 뺀다

        // 테넌트 원장에서는 공유 원장 기록에 `[상위 …]` 표시.
        let fromPerson = LawRecordList.load(target: fx.person, filter: LawRecordListFilter(query: "배포"))
        #expect(fromPerson.contains { $0.id == rule.id && $0.scopeMark == "[상위 agent-law]" && $0.memoryKind == .project })
        #expect(fromPerson.contains { $0.id == personal.id && $0.scopeMark.isEmpty })
    }

    // MARK: - 드리밍

    @Test func dreamReportBodyRoundTrips() {
        let target = String(repeating: "a", count: 64)
        let made = String(repeating: "b", count: 64)
        let ledger = LawDreamLedgerOutcome(
            world: "agent-law", ledgerKey: "law", active: true, materials: LawDreamMaterials(),
            applied: [
                LawDreamApplied(kind: "amend", world: "agent-law", target: target, ids: [made], note: "메모"),
                LawDreamApplied(kind: "enact", world: "agent-law", target: nil, ids: [made, target], note: nil),
            ],
            discarded: [LawDreamDiscard(proposal: "repeal 12345678", reason: "폐지 상한\n초과: 묶음")],
            deferred: 2, alerts: ["드리밍 경보 하나", "둘째 경보"], migrations: 1)
        let body = LawDreamService.reportBody(
            ledger, run: "v261004000000", batch: "batch-1", trigger: .scheduled, archive: nil, archiveError: nil)
        let parsed = LawDreamReportSummary.parse(body)
        #expect(parsed.batch == "batch-1" && parsed.run == "v261004000000")
        #expect(parsed.ledgerKey == "law" && parsed.trigger == "scheduled")
        #expect(parsed.appliedCount == 2)
        #expect(parsed.applied == ["amend aaaaaaaa → bbbbbbbb (메모)", "enact → bbbbbbbb aaaaaaaa"])
        #expect(parsed.discardedCount == 1)
        #expect(parsed.discarded == [.init(proposal: "repeal 12345678", reason: "폐지 상한 초과: 묶음")])
        #expect(parsed.deferredCount == 2 && parsed.migrations == 1)
        #expect(parsed.alerts == ["드리밍 경보 하나", "둘째 경보"])
        // 기존 읽기(묶음·경보)와 같은 값.
        #expect(LawDreamRecordFormat.values(body, prefix: LawDreamRecordFormat.batchPrefix) == [parsed.batch].compactMap { $0 })
        #expect(LawDreamRecordFormat.values(body, prefix: LawDreamRecordFormat.alertPrefix) == parsed.alerts)
        #expect(LawDreamReportSummary.parse("") == LawDreamReportSummary())
    }

    /// 두 원장(공유·개인)을 함께 바꾼 드리밍 묶음 하나.
    struct MultiDream {
        let batch: String
        let lawApplied: [String]
        let personApplied: [String]
        let userRecord: LawStoredRecord
        let old: LawStoredRecord
    }

    static func multiDream(_ fx: Dream.Fixture) throws -> MultiDream {
        let old = try Dream.enact(fx, fx.person, title: "옛 기록", body: "옛 본문")
        let userRecord = try Dream.enact(fx, fx.person, title: "사용자 기록", body: "사용자 말", actor: Dream.human)
        try Dream.seedSession(fx, ledgerKey: "law", session: "s-law", lines: ["공유 지식"])
        try Dream.seedSession(fx, session: "s-person", lines: ["개인 지식"])
        let ai = FakeAI([
            Dream.respond([["kind": "enact", "title": "공유 새 지식", "body": "공유 본문"]]),
            Dream.respond([
                ["kind": "enact", "title": "새 지식", "body": "새 본문"],
                ["kind": "amend", "target": String(old.id.prefix(8)), "body": "고친 본문"],
                ["kind": "amend", "target": String(userRecord.id.prefix(8)), "body": "사용자 말 고침"],
            ]),
        ] + Array(repeating: Dream.respond([]), count: 4))
        let outcome = try fx.service(ai).run(trigger: .manual)
        let law = try #require(outcome.ledgers.first { $0.world == "agent-law" })
        let person = try #require(outcome.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(law.applied.map(\.kind) == ["enact"])
        #expect(person.applied.map(\.kind) == ["enact", "amend", "propose"])
        return MultiDream(
            batch: try #require(outcome.batch), lawApplied: law.applied.flatMap(\.ids),
            personApplied: person.applied.flatMap(\.ids), userRecord: userRecord, old: old)
    }

    @Test func dreamScreenStatusHistoryAndBatchChanges() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let dream = try Self.multiDream(fx)
        let screen = LawDreamScreen.load(file: fx.file, catalog: fx.catalog)
        #expect(screen.isDreamDevice && screen.dreamDevice == "mac" && screen.canWrite)
        #expect(screen.ledgers == ["agent-law", "agent-law-person-a"])
        #expect(screen.gaps == [.ai, .storageEndpoint])  // 시험 서비스는 설정 밖 AI 를 쓰고, 설정에는 없다
        #expect(!screen.paused)
        let reports = (Dream.records(fx.law) + Dream.records(fx.person)).filter {
            LawDreamRecordFormat.isDreamReport($0.record)
        }
        let latest = try #require(reports.map(\.record.promulgated).max())
        #expect(screen.lastRunAt == latest)
        #expect(screen.nextDueAt == latest.addingTimeInterval(24 * 3600))
        #expect(screen.runs.count == 2 && screen.runs.allSatisfy { $0.batch == dream.batch })
        let personRun = try #require(screen.runs.first { $0.world == "agent-law-person-a" })
        #expect(personRun.summary.appliedCount == 3 && personRun.summary.applied.count == 3)
        #expect(personRun.summary.ledgerKey == "person-a" && personRun.summary.trigger == "manual")

        let changes = LawDreamBatchChanges.load(batch: dream.batch, file: fx.file, catalog: fx.catalog)
        #expect(Set(changes.map(\.id)) == Set(dream.lawApplied + dream.personApplied))
        #expect(changes.filter { $0.world == "agent-law" }.map(\.kind) == [.enacted])
        #expect(changes.contains { $0.kind == .amended(target: dream.old.id) && $0.world == "agent-law-person-a" })

        // 드리밍 기기가 아닌 기기 — 보기는 되고, 쓰기 게이트가 거부하면 그 이유를 보인다.
        var elsewhere = fx.file
        elsewhere.dreamDevice = "mini"
        let viewer = LawDreamScreen.load(file: elsewhere, catalog: fx.catalog)
        #expect(!viewer.isDreamDevice && viewer.runs.count == 2 && viewer.canWrite)
        var unregistered = fx.file
        unregistered.currentDevice = "stranger"
        let denied = LawDreamScreen.load(file: unregistered, catalog: fx.catalog)
        #expect(!denied.canWrite && denied.writeDenials.count == 2)
        #expect(denied.writeDenials.allSatisfy { $0.contains("not registered") })
        guard case .refused(let reasons) = try LawDreamBatchRestore.restore(
            batch: dream.batch, actor: Dream.human, file: unregistered, catalog: fx.catalog, now: fx.now)
        else { Issue.record("미등록 기기에서 되돌리기가 통과함"); return }
        #expect(reasons.count == 2)
    }

    @Test func multiLedgerBatchRestoreIsAllOrNothingAndPauses() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let dream = try Self.multiDream(fx)
        fx.clock.advance(60)
        guard case .restored(let ledgers) = try LawDreamBatchRestore.restore(
            batch: dream.batch, actor: Dream.human, file: fx.file, catalog: fx.catalog, now: fx.now)
        else { Issue.record("드리밍 묶음 되돌리기가 거부됨"); return }
        #expect(ledgers.map(\.world) == ["agent-law", "agent-law-person-a"])
        #expect(ledgers.map(\.records.count) == [dream.lawApplied.count, dream.personApplied.count])
        let restoreBatches = Set(ledgers.flatMap(\.records).compactMap(\.record.batch))
        #expect(restoreBatches.count == 1 && !restoreBatches.contains(dream.batch))
        let lawView = LawLedgerView(records: Dream.records(fx.law))
        let personView = LawLedgerView(records: Dream.records(fx.person))
        for id in dream.lawApplied { #expect(!lawView.isInForce(id)) }
        for id in dream.personApplied { #expect(!personView.isInForce(id)) }
        let back = try #require(ledgers.last?.records.first { $0.record.title == "옛 기록" })
        #expect(back.record.body == "옛 본문" && personView.isInForce(back.id))
        // 되돌리면 자동 드리밍 정지(엔진 규칙) — 화면 상태도 정지.
        let screen = LawDreamScreen.load(file: fx.file, catalog: fx.catalog)
        #expect(screen.paused && Set(screen.pausedBy) == Set(ledgers.flatMap(\.records).map(\.id)))
        #expect(LawContentsScreen.load(target: fx.person, now: fx.now).pending.dreamingPaused)

        // 재개 — 사람 작성자로.
        let resumed = try #require(try LawDreamScreen.resume(
            file: fx.file, catalog: fx.catalog, target: fx.person, author: "user:tester", now: fx.now))
        #expect(resumed.record.authorKind == "human" && resumed.record.author == "user:tester")
        #expect(resumed.record.runtime == "human" && resumed.record.model == nil)
        #expect(!LawDreamScreen.load(file: fx.file, catalog: fx.catalog).paused)
        #expect(try LawDreamScreen.resume(file: fx.file, catalog: fx.catalog, target: fx.person, now: fx.now) == nil)
    }

    @Test func multiLedgerBatchRestoreRefusedLeavesEveryLedgerUntouched() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let dream = try Self.multiDream(fx)
        let proposal = try #require(Dream.records(fx.person).first {
            $0.record.batch == dream.batch && $0.record.type == "proposal"
        })
        // 개인 원장의 드리밍 개정안에 결정이 났다 → 그 원장은 되돌릴 수 없다.
        _ = try fx.person.store.enact(LawDraft(
            actor: LawActor(author: "app:agent-wiki", kind: .app, device: "mac", runtime: "claude-code",
                            model: "claude-sonnet-5-5", effort: "high", app: "agent-wiki", appVersion: "9.9.9"),
            title: "항소심 결정", type: "ruling", cites: [LawCite(id: proposal.id, rel: "hears")],
            body: "level: appellate\noutcome: uphold\n\n유지\n"), now: fx.now)
        let before = try [fx.law, fx.person].map {
            try FileManager.default.subpathsOfDirectory(atPath: $0.root.path).sorted()
        }
        fx.clock.advance(60)
        guard case .refused(let reasons) = try LawDreamBatchRestore.restore(
            batch: dream.batch, actor: Dream.human, file: fx.file, catalog: fx.catalog, now: fx.now)
        else { Issue.record("결정이 난 개정안이 든 묶음이 되돌려짐"); return }
        #expect(reasons.count == 1)
        #expect(reasons.first?.hasPrefix("agent-law-person-a \(proposal.id.prefix(8))") == true)
        let after = try [fx.law, fx.person].map {
            try FileManager.default.subpathsOfDirectory(atPath: $0.root.path).sorted()
        }
        #expect(after == before)
        #expect(!LawDreamScreen.load(file: fx.file, catalog: fx.catalog).paused)

        // 드리밍 묶음이 아닌 묶음은 이 경로로 되돌리지 않는다.
        let plain = try Dream.enact(fx, fx.law, title: "일반", batch: "plain-batch")
        guard case .refused(let plainReasons) = try LawDreamBatchRestore.restore(
            batch: "plain-batch", actor: Dream.human, file: fx.file, catalog: fx.catalog, now: fx.now)
        else { Issue.record("일반 묶음이 드리밍 묶음 되돌리기로 통과함"); return }
        #expect(plainReasons.first?.contains("드리밍 묶음이 아님") == true)
        #expect(LawLedgerView(records: Dream.records(fx.law)).isInForce(plain.id))
    }

    /// 보고 본문 바이트 고정 — 상수로 옮기기 전(옛 문자열 리터럴) 출력과 바이트 단위로 같아야 한다.
    @Test func dreamReportBodyBytesAreUnchanged() {
        let ledger = LawDreamLedgerOutcome(
            world: "agent-law", ledgerKey: "law", active: true, materials: LawDreamMaterials(),
            applied: [LawDreamApplied(
                kind: "amend", world: "agent-law", target: String(repeating: "a", count: 64),
                ids: [String(repeating: "b", count: 64)], note: "메모")],
            discarded: [LawDreamDiscard(proposal: "repeal 12345678", reason: "폐지 상한\n초과")],
            deferred: 2, alerts: ["경보 하나"], migrations: 1)
        let body = LawDreamService.reportBody(
            ledger, run: "v261004000000", batch: "batch-1", trigger: .manual, archive: nil, archiveError: "끊김\n두 줄")
        let expected = """
            batch: batch-1
            run: v261004000000
            ledger: law
            trigger: manual

            ## 읽은 재료
            - 적재 실행 요약 0건, 세션 조각 0건(가린 조각 0), 세션 0, 발화 0
            - 전신 객체 0건
            - 저장소 문서 0건
            - 최근 바뀐 기록 0건, 지난 실행에서 미룬 제안 0건

            ## 적용한 변경 1건
            - amend aaaaaaaa → bbbbbbbb (메모)

            ## 버린 제안 1건
            - repeal 12345678: 폐지 상한 초과

            ## 미룬 제안 2건

            ## 경보 1건
            경보: 경보 하나

            ## 이관 1건

            ## 적재 보고
            - 적재 없음 — 실패: 끊김 두 줄

            """
        #expect(Data(body.utf8) == Data(expected.utf8))
    }

    /// 검사는 모두 통과했는데 쓰는 도중 한 원장이 실패하면(경합) 어느 원장까지 썼는지 돌려준다.
    @Test func multiLedgerBatchRestoreReportsPartialWrite() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let dream = try Self.multiDream(fx)
        fx.clock.advance(60)
        let outcome = try LawDreamBatchRestore.restore(
            batch: dream.batch, actor: Dream.human, targets: LawDreamService.targets(file: fx.file, catalog: fx.catalog),
            now: fx.now, testimony: nil,
            writer: { target, plan in
                if target.worldName == "agent-law-person-a" {
                    throw LawEnactError.restorePartiallyApplied(applied: [], remaining: [], reason: "경합")
                }
                return try target.store.applyRestore(plan)
            })
        guard case .partial(let written, let failed, let untouched, let reason) = outcome else {
            Issue.record("쓰기 도중 실패가 partial 로 오지 않음: \(outcome)")
            return
        }
        #expect(written.map(\.world) == ["agent-law"] && written.first?.records.count == dream.lawApplied.count)
        #expect(failed.world == "agent-law-person-a" && failed.records.isEmpty)
        #expect(untouched.isEmpty && reason == "경합")
        let lawView = LawLedgerView(records: Dream.records(fx.law))
        for id in dream.lawApplied { #expect(!lawView.isInForce(id)) }
        let personView = LawLedgerView(records: Dream.records(fx.person))
        for id in dream.personApplied { #expect(personView.isInForce(id)) }
    }

    /// 화면 한 벌이 기록을 한 번만 읽는 길(기록을 넘겨 만들기)과 범위 색인 길이 같은 목록을 낸다.
    @Test func recordsBasedLoadsMatchScopeLoads() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let rule = try Dream.enact(fx, fx.law, title: "배포 규칙", body: "배포는 화요일")
        _ = try Dream.enact(fx, fx.law, title: "조문", type: "article", body: "조문 본문")
        _ = try Self.finding(fx.law, of: rule.id, at: fx.now)
        let records = Dream.records(fx.law)
        let index = LawScopeIndex(current: "agent-law", catalog: fx.catalog)
        for filter in [LawRecordListFilter(), LawRecordListFilter(memoryKind: .project), LawRecordListFilter(type: .article)] {
            #expect(LawRecordList.load(target: fx.law, filter: filter, records: records)
                    == LawRecordList.rows(index: index, filter: filter))
        }
        let before = fx.law.store.objectsFingerprint()
        #expect(before == fx.law.store.objectsFingerprint())
        _ = try Dream.enact(fx, fx.law, title: "새 기록", body: "새 본문")
        #expect(fx.law.store.objectsFingerprint() != before)
        #expect(fx.law.store.objectsFingerprint().count == records.count + 1)
        // 목차 공지 머리말은 쓰는 쪽과 읽는 쪽이 같은 상수를 쓴다.
        #expect(LawContentsScreen.idPrefix(ofLine: LawContents.objectionNoticePrefix + "abcdef12 제목") == "abcdef12")
    }

    // MARK: - 모델 신빙성

    @Test func credibilityRowsPeriodAndExpansion() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let r1 = try Court.enact(fx, title: "하나", at: 0)
        let r2 = try Court.enact(fx, title: "둘", at: 1)
        let r3 = try Court.enact(fx, title: "셋", at: 2)
        _ = try LawEnactService.enact(
            LawDraft(actor: AgentLawDreamTests.codexAgent, title: "넷", body: "codex"), target: fx.target, now: Court.at(3))
        _ = try LawEnactService.enact(
            LawDraft(actor: Court.opus, title: "하나", amends: r1.id, body: "하나 고침"), target: fx.target, now: Court.at(4))
        _ = try LawEnactService.enact(AgentLawRepealTargetTests.repeal(r2), target: fx.target, now: Court.at(5))
        _ = try fx.service(FakeAI([])).appeal(r3.id, reason: "틀림", actor: Court.opus, now: Court.at(6))
        _ = fx.service(FakeAI([#"{"outcome":"overturn","reason":"틀렸다","action":{"kind":"amend","body":"셋 고침"}}"#]))
            .hear(now: Court.at(7))

        let records = fx.records
        let screen = LawCredibilityScreen.load(target: fx.target, period: .all, now: Court.at(10))
        #expect(screen.rows == LawModelReport.rows(records: records))
        let opus = try #require(screen.rows.first { $0.model == "claude-opus-5-5" })
        #expect(opus.enacted == 4 && opus.amended == 2 && opus.repealed == 1 && opus.overturned == 1)
        let items = screen.items(for: opus)
        #expect(items.map(\.id) == [r1.id, r2.id, r3.id])
        #expect(items[0].amended && !items[0].repealed)
        #expect(items[1].repealed && items[2].overturned && items[2].amended)
        let codex = try #require(screen.rows.first { $0.runtime == "codex" })
        #expect(screen.items(for: codex).isEmpty)

        #expect(LawCredibilityScreen.load(target: fx.target, period: .last30Days, now: Court.at(10)).rows == screen.rows)
        let later = Court.at(31 * 86_400)
        #expect(LawCredibilityScreen.load(target: fx.target, period: .last30Days, now: later).isEmpty)
        #expect(LawCredibilityPeriod.last30Days.since(now: later) == later.addingTimeInterval(-30 * 86_400))
    }
}
