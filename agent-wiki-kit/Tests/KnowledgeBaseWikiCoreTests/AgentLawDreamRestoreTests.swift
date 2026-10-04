import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// 드리밍 묶음 원상회복·승격 영수증 시험.
/// - 드리밍 묶음(드리밍 보고가 적은 묶음)은 사실인정·개정안이 들어 있어도 되돌릴 수 있고, 되돌리면 자동 드리밍이 정지한다
///   (사용자 결정 "자동 적용 + 묶음 되돌리기"). 이미 결정이 난 드리밍 개정안이 들어 있으면 아무것도 쓰지 않고 거부한다.
/// - 드리밍 보고가 없는 묶음은 지금 규칙 그대로다.
/// - 승격 영수증은 어느 경로로도 개정·폐지하지 못한다.
/// 근거: docs/business-rules.md "드리밍"(안전장치)·"공포·개정·폐지·원상회복"·"유형", `LawRestorePaths`.
/// 실제 AI·R2·세션은 쓰지 않는다(주입 실행기·메모리 R2·임시 루트).
@Suite struct AgentLawDreamRestoreTests {
    typealias Dream = AgentLawDreamTests
    typealias FakeAI = AgentLawCourtTests.FakeAI
    typealias Repeal = AgentLawRepealTargetTests

    struct DreamBatch {
        let batch: String
        let old: LawStoredRecord
        let judged: LawStoredRecord
        let userRecord: LawStoredRecord
        let applied: [String]
    }

    /// person-a 원장에 드리밍 묶음 하나 — 새 지식·개정·사실인정·(사용자 기록 직접 개정 → 개정안).
    static func dreamBatch(_ fx: Dream.Fixture, ai: FakeAI? = nil) throws -> DreamBatch {
        let old = try Dream.enact(fx, fx.person, title: "옛 기록", body: "옛 본문")
        let judged = try Dream.enact(fx, fx.person, title: "판단할 기록", body: "판단 본문")
        let userRecord = try Dream.enact(fx, fx.person, title: "사용자 기록", body: "사용자 말", actor: Dream.human)
        try Dream.seedSession(fx, session: "s-1", lines: ["새 지식을 배웠다"])
        let ai = ai ?? FakeAI([Dream.respond([]), Dream.respond([
            ["kind": "enact", "title": "새 지식", "body": "새 본문"],
            ["kind": "amend", "target": String(old.id.prefix(8)), "body": "고친 본문"],
            ["kind": "finding", "target": String(judged.id.prefix(8)), "subject": "project", "certainty": "probable",
             "domain": "dev-workflow", "reason": "세션"],
            ["kind": "amend", "target": String(userRecord.id.prefix(8)), "body": "사용자 말 고침"],
        ])] + Array(repeating: Dream.respond([]), count: 4))
        let outcome = try fx.service(ai).run(trigger: .manual)
        let person = try #require(outcome.ledgers.first { $0.world == "agent-law-person-a" })
        #expect(person.applied.map(\.kind) == ["enact", "amend", "finding", "propose"])
        return DreamBatch(
            batch: try #require(outcome.batch), old: old, judged: judged, userRecord: userRecord,
            applied: person.applied.flatMap(\.ids))
    }

    @Test func dreamBatchWithFindingAndProposalRestoresAndPausesDreaming() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let dream = try Self.dreamBatch(fx)
        let records = Dream.records(fx.person)
        let batchTypes = Set(records.filter { $0.record.batch == dream.batch }.compactMap(\.record.type))
        #expect(batchTypes == ["record", "finding", "proposal"])
        #expect(LawDreamMarks(records: records).dreamBatches == [dream.batch])
        #expect(!fx.service(FakeAI([])).pause().isPaused)

        // CLI `restore` 와 같은 일반 경로로 되돌린다.
        fx.clock.advance(60)
        let restored = try LawEnactService.restore(batch: dream.batch, actor: Dream.agent, target: fx.person, now: fx.now)
        #expect(restored.count == dream.applied.count)
        let view = LawLedgerView(records: Dream.records(fx.person))
        for id in dream.applied { #expect(!view.isInForce(id), "\(id.prefix(8)) 이 현행에 남음") }
        #expect(view.isInForce(dream.judged.id) && view.isInForce(dream.userRecord.id))
        // 개정이었던 기록은 이전 판으로 돌아왔다.
        let back = try #require(restored.first { $0.record.title == "옛 기록" })
        #expect(back.record.body == "옛 본문")
        #expect(view.isInForce(back.id))
        // 개정안이 폐지되어 사건 목록에서 빠진다.
        #expect(LawCourtDocket.of(fx.person).open.isEmpty)

        // 드리밍 묶음 원상회복 → 자동 드리밍 정지(사람의 재개 전까지).
        let pause = fx.service(FakeAI([])).pause()
        #expect(Set(pause.unacknowledgedRestores) == Set(restored.map(\.id)))
        #expect(fx.service(FakeAI([])).status().paused)
        fx.clock.advance(25 * 3600)
        try Dream.seedSession(fx, session: "s-2", lines: ["또"])
        let blocked = try fx.service(FakeAI([])).run(trigger: .scheduled)
        #expect(blocked.skipped?.contains("정지") == true)
    }

    @Test func dreamBatchWithDecidedProposalIsRefusedWhole() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let dream = try Self.dreamBatch(fx)
        let proposal = try #require(Dream.records(fx.person).first {
            $0.record.batch == dream.batch && $0.record.type == "proposal"
        })
        // 개정안에 항소심 결정이 났다.
        _ = try fx.person.store.enact(LawDraft(
            actor: LawActor(author: "app:agent-wiki", kind: .app, device: "mac", runtime: "claude-code",
                            model: "claude-sonnet-5-5", effort: "high", app: "agent-wiki", appVersion: "9.9.9"),
            title: "항소심 결정", type: "ruling", cites: [LawCite(id: proposal.id, rel: "hears")],
            body: "level: appellate\noutcome: uphold\n\n유지\n"), now: fx.now)
        let before = try FileManager.default.subpathsOfDirectory(atPath: fx.person.root.path).sorted()
        fx.clock.advance(60)
        for path in [LawEnactPath.general, .court] {
            let error = Repeal.refusal {
                try LawEnactService.restore(batch: dream.batch, actor: Dream.agent, target: fx.person, path: path, now: fx.now)
            }
            guard case .restoreRefused(let reasons)? = error else {
                Issue.record("결정이 난 개정안이 든 드리밍 묶음이 \(path) 로 되돌려짐: \(String(describing: error))")
                continue
            }
            #expect(reasons.count == 1)
            #expect(reasons.first?.hasPrefix(String(proposal.id.prefix(8))) == true)
            #expect(reasons.first?.contains("이미 결정") == true)
        }
        #expect(try FileManager.default.subpathsOfDirectory(atPath: fx.person.root.path).sorted() == before)
        #expect(!fx.service(FakeAI([])).pause().isPaused)
    }

    @Test func batchWithoutDreamReportKeepsGeneralRules() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        // 드리밍 앱 작성자로 적었어도 드리밍 보고가 그 묶음을 적지 않았으면 드리밍 묶음이 아니다.
        let app = LawActor(author: "app:agent-wiki", kind: .app, device: "mac", runtime: "app", app: "agent-wiki", appVersion: "1")
        let base = try Dream.enact(fx, fx.person, title: "대상", body: "대상 본문")
        let finding = try fx.person.store.enact(LawDraft(
            actor: app, title: "사실인정", type: "finding", origin: "dream", batch: "lookalike",
            cites: [LawCite(id: base.id, rel: "finds")],
            body: "subject: project\ncertainty: probable\ndomain: dev-workflow\nreason: r\n"), now: fx.now)
        let proposal = try fx.person.store.enact(LawDraft(
            actor: app, title: "개정안", type: "proposal", batch: "lookalike",
            cites: [LawCite(id: base.id, rel: "proposes")], body: "scope: 본문\n\n새 본문"), now: fx.now)
        let error = Repeal.refusal {
            try LawEnactService.restore(batch: "lookalike", actor: Dream.human, target: fx.person, now: fx.now)
        }
        guard case .restoreRefused(let reasons)? = error else {
            Issue.record("드리밍 보고 없는 묶음이 일반 경로로 되돌려짐: \(String(describing: error))")
            return
        }
        #expect(reasons.contains { $0.hasPrefix(String(finding.id.prefix(8))) })
        #expect(reasons.contains { $0.hasPrefix(String(proposal.id.prefix(8))) })
        let view = LawLedgerView(records: Dream.records(fx.person))
        #expect(view.isInForce(finding.id) && view.isInForce(proposal.id))
    }

    @Test func promotionReceiptsAreIrreversibleOnEveryPath() throws {
        let fx = try AgentLawEnactPathTests.fixture()
        defer { fx.cleanup() }
        let person = fx.target("agent-law-person-a")
        let law = fx.target("agent-law")
        let base = try LawEnactService.enact(AgentLawEnactPathTests.draft("승격할 기록"), target: person)
        let result = try LawPromotionService.promote(
            sourceID: base.id, source: person, targetWorld: "agent-law", actor: AgentLawEnactPathTests.agent)
        let receipts: [(LawLedgerTarget, String)] = [(person, result.sourceReceiptObjectId)]
            + (result.targetReceiptObjectId.map { [(law, $0)] } ?? [])
        #expect(!receipts.isEmpty)
        for (target, id) in receipts {
            let stored = try #require(target.store.scan().first { $0.id == id })
            #expect(stored.record.type == "promotion-receipt")
            for path in LawEnactPath.allCases {
                #expect(Repeal.refusal {
                    try LawEnactService.enact(Repeal.repeal(stored, actor: AgentLawEnactPathTests.agent), target: target, path: path)
                } == .targetIrreversible(target: id, type: "promotion-receipt"), "\(path) 폐지")
                #expect(Repeal.refusal {
                    try LawEnactService.enact(LawDraft(
                        actor: AgentLawEnactPathTests.agent, title: "고침", amends: id, body: "고친 본문"),
                        target: target, path: path)
                } == .targetIrreversible(target: id, type: "promotion-receipt"), "\(path) 개정")
            }
            #expect(LawLedgerView(records: target.store.scan()).isInForce(id))
        }
    }
}
