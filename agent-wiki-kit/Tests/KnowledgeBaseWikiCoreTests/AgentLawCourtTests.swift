import CommandKit
import Foundation
import SessionKit
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// 심급제(T9) 시험 — 이의·개정안·항소심·대법원·대기 목록. 실제 AI 실행 도구는 부르지 않는다(주입 실행기).
/// 근거: docs/business-rules.md "심급제", docs/contracts.md "agent-law 명령"(심급), 결정 0007.
/// 임시 디렉터리 루트만 쓴다.
@Suite struct AgentLawCourtTests {

    // MARK: - 준비

    /// 주입 실행기 — 받은 명세를 적고 정해 둔 응답을 돌려준다.
    final class FakeAI: @unchecked Sendable {
        private let lock = NSLock()
        private var responses: [String]
        private(set) var specs: [CommandSpecification] = []

        init(_ responses: [String]) { self.responses = responses }

        var runner: LawAIRunner {
            LawAIRunner { spec in
                self.lock.lock()
                defer { self.lock.unlock() }
                self.specs.append(spec)
                let stdout = self.responses.isEmpty ? "" : self.responses.removeFirst()
                return CommandResult(stdout: stdout, stderr: "", exitCode: 0)
            }
        }

        var calls: Int {
            lock.lock()
            defer { lock.unlock() }
            return specs.count
        }
    }

    struct FakeTestimony: LawTestimonyVerifying {
        func speaker(for request: LawTestimonyRequest) throws -> LawSpeaker? { .user }
    }

    struct Fixture {
        let dir: URL
        let target: LawLedgerTarget

        func service(_ ai: FakeAI, settings: LawCourtSettings? = nil) -> LawCourtService {
            LawCourtService(target: target, settings: settings, runner: ai.runner, appVersion: "9.9.9")
        }

        var records: [LawStoredRecord] { target.store.scan() }
        func record(_ id: String) -> LawRecord? { records.first { $0.id == id }?.record }
        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    static func fixture(court: LawCourtSettings? = nil) -> Fixture {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-law-court-\(UUID().uuidString)", isDirectory: true)
        let file = BoundLedgerFile(
            worlds: [BoundWorld(name: "agent-law", rootPath: dir.appendingPathComponent("law").path, key: "law")],
            currentWorld: "agent-law", devices: ["mac"], currentDevice: "mac", court: court)
        return Fixture(dir: dir, target: LawLedgerTarget(worldName: "agent-law", file: file))
    }

    static let base = Date(timeIntervalSince1970: 1_790_000_000)
    static func at(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
    static let hour: Double = 3600

    static let opus = LawActor(
        author: "agent:claude@mac", kind: .agent, device: "mac", runtime: "claude-code",
        model: "claude-opus-5-5", effort: "high")
    static let human = LawActor(author: "user:yun", kind: .human, device: "mac")

    static func enact(
        _ fx: Fixture, title: String = "기록", type: String = "record", body: String = "본문",
        batch: String? = nil, actor: LawActor = opus, at seconds: Double
    ) throws -> LawStoredRecord {
        try LawEnactService.enact(
            LawDraft(actor: actor, title: title, type: type, batch: batch, body: body), target: fx.target, now: at(seconds))
    }

    static func userEvidence(_ fx: Fixture, at seconds: Double) throws -> LawStoredRecord {
        let sha = try fx.target.store.putExhibit(Data("승인한다".utf8))
        return try fx.target.store.enact(
            LawDraft(actor: opus, speaker: "user", title: "증언", type: "evidence",
                     exhibits: [sha], body: "session: s-1\nutterance-at: 2026-10-04T00:00:00Z\n\n인용"),
            now: at(seconds), context: LawEnactContext(testimony: FakeTestimony()))
    }

    static func head(_ record: LawRecord?) -> LawHeadFieldBlock? {
        record.flatMap { try? LawHeadFields.parse(body: $0.body, type: $0.type) }
    }

    // MARK: - 이의·개정안

    @Test func appealKeepsTargetInForceAndQueuesAppellate() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let target = try Self.enact(fx, at: 0)
        let appeal = try fx.service(FakeAI([])).appeal(target.id, reason: "근거가 틀렸다", actor: Self.opus, now: Self.at(1))
        #expect(appeal.record.type == "appeal")
        #expect(appeal.record.cites == [LawCite(id: target.id, rel: "appeals")])
        #expect(LawLedgerView(records: fx.records).isInForce(target.id))
        let docket = LawCourtDocket.of(fx.target)
        #expect(docket.appellatePending.map(\.id) == [appeal.id])
        #expect(docket.supremePending.isEmpty)
        #expect(throws: LawCourtError.emptyReason) {
            try fx.service(FakeAI([])).appeal(target.id, reason: "  ", actor: Self.opus, now: Self.at(2))
        }
    }

    @Test func proposalCarriesScopeAndFullContent() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let target = try Self.enact(fx, at: 0)
        let proposal = try fx.service(FakeAI([])).propose(
            target.id, scope: "agent-law 전체", content: "바뀐 본문 전체\n둘째 줄\n", actor: Self.opus, now: Self.at(1))
        #expect(proposal.record.type == "proposal")
        #expect(proposal.record.cites == [LawCite(id: target.id, rel: "proposes")])
        #expect(Self.head(proposal.record)?["scope"] == "agent-law 전체")
        #expect(LawCourtService.proposalContent(proposal.record.body) == "바뀐 본문 전체\n둘째 줄\n")
        #expect(throws: LawCourtError.emptyContent) {
            try fx.service(FakeAI([])).propose(target.id, scope: "x", content: "\n", actor: Self.opus, now: Self.at(2))
        }
    }

    // MARK: - 항소심

    @Test func hearPicksDifferentModelAndRecordsRuling() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let target = try Self.enact(fx, at: 0)
        let appeal = try fx.service(FakeAI([])).appeal(target.id, reason: "이의", actor: Self.opus, now: Self.at(1))
        let ai = FakeAI([#"```json\#n{"outcome":"uphold","reason":"근거가 충분하다"}\#n```"#])
        let report = fx.service(ai).hear(now: Self.at(2))
        #expect(report.decided.count == 1)
        #expect(ai.calls == 1)
        let args = ai.specs[0].arguments
        #expect(args.first == SupportedAIAgentCLI.claude.executableName)
        #expect(args.contains("claude-sonnet-5-5"))
        #expect(ai.specs[0].input.flatMap { String(data: $0, encoding: .utf8) }?.contains(target.id) == true)

        let ruling = try #require(report.decided.first?.ruling).record
        #expect(ruling.type == "ruling")
        #expect(Self.head(ruling)?["level"] == "appellate")
        #expect(Self.head(ruling)?["outcome"] == "uphold")
        #expect(ruling.author == "app:agent-wiki")
        #expect(ruling.authorKind == "app")
        #expect(ruling.app == "agent-wiki")
        #expect(ruling.appVersion == "9.9.9")
        #expect(ruling.runtime == "claude-code")
        #expect(ruling.model == "claude-sonnet-5-5")
        #expect(ruling.effort == "high")
        #expect(ruling.cites.contains(LawCite(id: appeal.id, rel: "hears")))
        #expect(LawCourtDocket.of(fx.target).open.isEmpty)
        #expect(LawLedgerView(records: fx.records).isInForce(target.id))
    }

    @Test func overturnWithAmendEnactsPerRulingAmendment() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let target = try Self.enact(fx, at: 0)
        _ = try fx.service(FakeAI([])).appeal(target.id, reason: "틀림", actor: Self.opus, now: Self.at(1))
        let ai = FakeAI([#"{"outcome":"overturn","reason":"틀렸다","action":{"kind":"amend","body":"고친 본문"}}"#])
        let entry = try #require(fx.service(ai).hear(now: Self.at(2)).decided.first)
        let ruling = try #require(entry.ruling)
        #expect(entry.actions.count == 1)
        let amendment = try #require(fx.record(entry.actions[0]))
        #expect(amendment.amends == target.id)
        #expect(amendment.body == "고친 본문")
        #expect(amendment.cites.contains(LawCite(id: ruling.id, rel: "per-ruling")))
        #expect(amendment.model == "claude-sonnet-5-5")
        let view = LawLedgerView(records: fx.records)
        #expect(!view.isInForce(target.id))
        #expect(view.isInForce(entry.actions[0]))
    }

    @Test func overturnWithRestoreRestoresBatchPerRuling() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let target = try Self.enact(fx, batch: "dream-1", at: 0)
        _ = try fx.service(FakeAI([])).appeal(target.id, reason: "잘못 정리", actor: Self.opus, now: Self.at(1))
        let ai = FakeAI([#"{"outcome":"overturn","reason":"원상회복","action":{"kind":"restore","batch":"dream-1"}}"#])
        let entry = try #require(fx.service(ai).hear(now: Self.at(2)).decided.first)
        let restoredID = try #require(entry.actions.first)
        let restored = try #require(fx.record(restoredID))
        let rulingID = try #require(entry.ruling).id
        #expect(restored.repeals == target.id)
        #expect(restored.cites.contains(LawCite(id: rulingID, rel: "per-ruling")))
        #expect(!LawLedgerView(records: fx.records).isInForce(target.id))
    }

    @Test func relaxingArticleProposalIsAlwaysReferred() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let article = try Self.enact(fx, title: "조문", type: "article", body: "에이전트는 X 를 하지 않는다", at: 0)
        let proposal = try fx.service(FakeAI([])).propose(
            article.id, scope: "전체", content: "에이전트는 X 를 해도 된다", actor: Self.opus, now: Self.at(1))
        // relaxes 가 없으면 형식 오류 — 결정하지 않는다.
        let missing = fx.service(FakeAI([#"{"outcome":"overturn","reason":"좋다"}"#])).hear(now: Self.at(2))
        #expect(missing.decided.isEmpty)
        #expect(missing.undecided.map(\.caseID) == [proposal.id])
        // 완화 → 중재자가 뒤집기라 해도 회부.
        let ai = FakeAI([#"{"outcome":"overturn","reason":"좋다","relaxes":true}"#])
        let entry = try #require(fx.service(ai).hear(now: Self.at(3)).decided.first)
        #expect(entry.outcome == .refer)
        #expect(entry.actions.isEmpty)
        #expect(LawLedgerView(records: fx.records).isInForce(article.id))
        let pending = try #require(LawCourtDocket.of(fx.target).supremePending.first)
        #expect(pending.id == proposal.id)
        #expect(pending.referredBy == entry.ruling?.id)
        #expect(pending.noticedAt == entry.ruling?.record.promulgated)
    }

    @Test func sameModelOnlyRefersWithoutCallingAI() throws {
        let fx = Self.fixture(court: LawCourtSettings(
            arbiters: [LawArbiterCandidate(cli: .claude, model: "claude-opus-5-5", effort: "high")]))
        defer { fx.cleanup() }
        let target = try Self.enact(fx, at: 0)
        let appeal = try fx.service(FakeAI([])).appeal(target.id, reason: "이의", actor: Self.opus, now: Self.at(1))
        let ai = FakeAI([])
        let entry = try #require(fx.service(ai).hear(now: Self.at(2)).decided.first)
        #expect(ai.calls == 0)
        #expect(entry.outcome == .refer)
        let ruling = try #require(entry.ruling).record
        #expect(ruling.model == nil)
        #expect(ruling.runtime == "app")
        #expect(LawCourtDocket.of(fx.target).supremePending.map(\.id) == [appeal.id])
    }

    @Test func malformedResponseLeavesCaseUndecided() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let target = try Self.enact(fx, at: 0)
        let appeal = try fx.service(FakeAI([])).appeal(target.id, reason: "이의", actor: Self.opus, now: Self.at(1))
        for response in ["모르겠다", #"{"outcome":"maybe","reason":"x"}"#, #"{"outcome":"uphold"}"#,
                         #"{"outcome":"overturn","reason":"x"}"#] {
            let report = fx.service(FakeAI([response])).hear(now: Self.at(2))
            #expect(report.decided.isEmpty, "\(response)")
            #expect(report.undecided.first?.undecidedReason != nil)
        }
        #expect(!fx.records.contains { $0.record.type == "ruling" })
        #expect(LawCourtDocket.of(fx.target).appellatePending.map(\.id) == [appeal.id])
    }

    @Test func appealOfRulingGoesToSupremeAndSupremeIsFinal() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let target = try Self.enact(fx, at: 0)
        _ = try fx.service(FakeAI([])).appeal(target.id, reason: "이의", actor: Self.opus, now: Self.at(1))
        let ruling = try #require(fx.service(FakeAI([#"{"outcome":"uphold","reason":"유지"}"#]))
            .hear(now: Self.at(2)).decided.first?.ruling)
        let finalAppeal = try fx.service(FakeAI([])).appeal(ruling.id, reason: "상고", actor: Self.opus, now: Self.at(3))
        let docket = LawCourtDocket.of(fx.target)
        #expect(docket.appellatePending.isEmpty)
        let pending = try #require(docket.supremePending.first)
        #expect(pending.id == finalAppeal.id)
        #expect(pending.isFinalAppeal)
        #expect(pending.noticedAt == finalAppeal.record.promulgated)
        // 항소심은 상고를 다루지 않는다.
        let ai = FakeAI([])
        #expect(fx.service(ai).hear(now: Self.at(4)).entries.isEmpty)
        #expect(ai.calls == 0)

        // 대법원 결정 뒤 그 결정에 대한 이의는 거부.
        let evidence = try Self.userEvidence(fx, at: 5)
        let decision = try fx.service(FakeAI([])).decide(
            caseID: finalAppeal.id, approve: false, testimony: evidence.id, actor: Self.human,
            now: Self.at(3 + 73 * Self.hour))
        #expect(throws: LawCourtError.supremeRulingIsFinal(decision.ruling.id)) {
            try fx.service(FakeAI([])).appeal(
                decision.ruling.id, reason: "다시", actor: Self.opus, now: Self.at(4 + 73 * Self.hour))
        }
    }

    // MARK: - 대법원

    /// 조문 완화 개정안을 항소심에서 회부해 대법원 대기로 둔다. 공지 시각 = 회부 결정 공포일(10초).
    static func referredArticleProposal(_ fx: Fixture) throws -> (article: LawStoredRecord, proposal: LawStoredRecord) {
        let article = try enact(fx, title: "조문", type: "article", body: "에이전트는 X 를 하지 않는다", at: 0)
        let proposal = try fx.service(FakeAI([])).propose(
            article.id, scope: "전체", content: "에이전트는 X 를 해도 된다", actor: opus, now: at(1))
        _ = fx.service(FakeAI([#"{"outcome":"refer","reason":"완화","relaxes":true}"#])).hear(now: at(10))
        return (article, proposal)
    }

    @Test func decideRefusedDuringObjectionPeriod() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let (_, proposal) = try Self.referredArticleProposal(fx)
        let evidence = try Self.userEvidence(fx, at: 20)
        do {
            try fx.service(FakeAI([])).decide(
                caseID: proposal.id, approve: true, testimony: evidence.id, actor: Self.human,
                now: Self.at(10 + 71 * Self.hour))
            Issue.record("이의 기간 중 결정이 통과함")
        } catch LawCourtError.objectionPeriod {}
        // 조정 가능 — 1시간이면 2시간 뒤 결정할 수 있다.
        let short = LawCourtSettings(objectionPeriodHours: 1)
        let decided = try fx.service(FakeAI([]), settings: short).decide(
            caseID: proposal.id, approve: false, testimony: evidence.id, actor: Self.human, now: Self.at(10 + 2 * Self.hour))
        #expect(Self.head(decided.ruling.record)?["outcome"] == "reject")
    }

    @Test func decideRequiresUserSpeakerTestimony() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let (_, proposal) = try Self.referredArticleProposal(fx)
        let external = try Self.enact(fx, title: "외부", type: "evidence", body: "외부 문서", at: 20)
        let agentRecord = try Self.enact(fx, title: "에이전트 말", at: 21)
        let later = Self.at(10 + 73 * Self.hour)
        for (id, expected) in [
            (external.id, LawCourtError.testimonyNotUserEvidence(external.id)),
            (agentRecord.id, LawCourtError.testimonyNotUserEvidence(agentRecord.id)),
            (String(repeating: "a", count: 64), LawCourtError.testimonyNotFound(String(repeating: "a", count: 64))),
        ] {
            #expect(throws: expected) {
                try fx.service(FakeAI([])).decide(
                    caseID: proposal.id, approve: true, testimony: id, actor: Self.opus, now: later)
            }
        }
        #expect(LawCourtDocket.of(fx.target).supremePending.map(\.id) == [proposal.id])
    }

    @Test func decideWithTestimonyClosesCaseAndAppliesProposal() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let (article, proposal) = try Self.referredArticleProposal(fx)
        let evidence = try Self.userEvidence(fx, at: 20)
        // 항소심 대기가 아닌 건, 이의·개정안이 아닌 기록은 거부.
        #expect(throws: LawCourtError.caseNotFound(article.id)) {
            try fx.service(FakeAI([])).decide(
                caseID: article.id, approve: true, testimony: evidence.id, actor: Self.opus, now: Self.at(10 + 73 * Self.hour))
        }
        // 작성자 무관 — 에이전트가 공포해도 사용자 증언이 있으면 된다.
        let decision = try fx.service(FakeAI([])).decide(
            caseID: proposal.id, approve: true, testimony: evidence.id, actor: Self.opus, now: Self.at(10 + 73 * Self.hour))
        let ruling = decision.ruling.record
        #expect(Self.head(ruling)?["level"] == "supreme")
        #expect(Self.head(ruling)?["outcome"] == "approve")
        #expect(ruling.speaker == "user")
        #expect(ruling.cites.contains(LawCite(id: evidence.id, rel: "testifies")))
        #expect(ruling.cites.contains(LawCite(id: proposal.id, rel: "hears")))
        let amendmentID = try #require(decision.actions.first)
        let amendment = try #require(fx.record(amendmentID))
        #expect(amendment.amends == article.id)
        #expect(amendment.body == "에이전트는 X 를 해도 된다")
        #expect(amendment.cites.contains(LawCite(id: decision.ruling.id, rel: "per-ruling")))
        #expect(LawCourtDocket.of(fx.target).open.isEmpty)
        #expect(throws: LawCourtError.notPendingSupreme(proposal.id)) {
            try fx.service(FakeAI([])).decide(
                caseID: proposal.id, approve: true, testimony: evidence.id, actor: Self.opus, now: Self.at(11 + 73 * Self.hour))
        }
        let report = fx.target.store.audit(context: LawEnactService.context(index: LawEnactService.scope(of: fx.target)))
        #expect(report.passed, "\(report.violations)")
    }

    // MARK: - 목록

    @Test func listFiltersByLevelAndNoticesShowSupremeAndProposalsInObjection() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let (_, referred) = try Self.referredArticleProposal(fx)
        let other = try Self.enact(fx, title: "다른 기록", at: 30)
        let open = try fx.service(FakeAI([])).propose(
            other.id, scope: "이 기록", content: "새 내용", actor: Self.opus, now: Self.at(31))
        let docket = LawCourtDocket.of(fx.target)
        #expect(docket.cases(level: .supreme).map(\.id) == [referred.id])
        #expect(docket.cases(level: .appellate).map(\.id) == [open.id])
        #expect(Set(docket.cases(level: nil).map(\.id)) == [referred.id, open.id])

        let soon = docket.notices(now: Self.at(40))
        #expect(soon.supreme.map(\.id) == [referred.id])
        #expect(Set(soon.proposalsInObjection.map(\.id)) == [referred.id, open.id])
        let late = docket.notices(now: Self.at(31 + 73 * Self.hour))
        #expect(late.supreme.map(\.id) == [referred.id])
        #expect(late.proposalsInObjection.isEmpty)
    }

    // MARK: - 설정

    @Test func arbiterSelectionSkipsTargetModel() {
        let settings = LawCourtSettings()
        #expect(settings.arbiter(forTargetModel: "claude-opus-5-5")?.model == "claude-sonnet-5-5")
        #expect(settings.arbiter(forTargetModel: "gpt-5")?.model == "claude-opus-5-5")
        #expect(settings.arbiter(forTargetModel: nil)?.model == "claude-opus-5-5")
        let only = LawCourtSettings(arbiters: [LawArbiterCandidate(cli: .claude, model: "m")])
        #expect(only.arbiter(forTargetModel: "m") == nil)
        #expect(LawCourtSettings().objectionPeriod == 72 * 3600)
    }

    @Test func courtSettingsSurviveConfigSave() throws {
        let fx = Self.fixture()
        defer { fx.cleanup() }
        let url = fx.dir.appendingPathComponent("config.json")
        var file = try #require(fx.target.file)
        file.court = LawCourtSettings(
            arbiters: [LawArbiterCandidate(cli: .codex, model: "gpt-5", effort: "high")], objectionPeriodHours: 24)
        try WorldConfigStore.save(file, to: url)
        var config = try JSONDecoder().decode(LedgerConfig.self, from: Data(contentsOf: url))
        config.currentWorld = "agent-law"
        try config.save(to: url)
        let reloaded = WorldConfigStore.load(from: url)
        #expect(reloaded.court == file.court)
        #expect(reloaded.devices == ["mac"])
    }
}
