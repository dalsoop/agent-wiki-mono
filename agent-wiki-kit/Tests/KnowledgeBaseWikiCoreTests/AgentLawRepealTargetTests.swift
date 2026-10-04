import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// 개정·폐지 대상 판정 시험 — 처리 기록은 대상의 실제 유형으로 판정하고(`LawEnactPath.targetPaths`),
/// 대법원 결정·가림은 어느 경로로도 되돌리지 못하며, 원상회복은 되돌릴 수 없는 기록이 있으면 아무것도 쓰지 않는다.
/// 근거: docs/business-rules.md "유형"·"공포·개정·폐지·원상회복"·"심급제", docs/contracts.md "agent-law 명령", 결정 0007.
/// 임시 디렉터리 루트만 쓴다. 실제 원장·R2·AI 는 쓰지 않는다.
@Suite struct AgentLawRepealTargetTests {
    typealias Court = AgentLawCourtTests
    typealias Enact = AgentLawEnactPathTests

    /// 처리 기록 한 벌. 판결 등록·가림·목차·보고·결정은 저장소 직접 공포(경로 판정 없음)로 심는다.
    struct Seeded {
        let knowledge: LawStoredRecord
        let appellate: LawStoredRecord
        let supreme: LawStoredRecord
        let registration: LawStoredRecord
        let redaction: LawStoredRecord
        let contents: LawStoredRecord
        let report: LawStoredRecord
        let appeal: LawStoredRecord
        let proposal: LawStoredRecord

        var processRecords: [LawStoredRecord] {
            [appellate, supreme, registration, redaction, contents, report, appeal, proposal]
        }
    }

    static func seed(_ fx: Court.Fixture, batch: String? = nil) throws -> Seeded {
        let store = fx.target.store
        let knowledge = try Court.enact(fx, title: "지식", at: 0)
        let service = fx.service(Court.FakeAI([]))
        let appeal = try service.appeal(knowledge.id, reason: "이의", actor: Court.opus, now: Court.at(1))
        let proposal = try service.propose(
            knowledge.id, scope: "본문", content: "새 본문", actor: Court.opus, now: Court.at(2))
        func plain(_ title: String, _ type: String, _ body: String, cites: [LawCite] = [], exhibits: [String] = [],
                   at seconds: Double) throws -> LawStoredRecord {
            try store.enact(LawDraft(
                actor: Court.opus, title: title, type: type, batch: batch, cites: cites, exhibits: exhibits, body: body),
                now: Court.at(seconds))
        }
        let appellate = try plain(
            "항소심 결정", "ruling", "level: appellate\noutcome: uphold\n\n유지\n",
            cites: [LawCite(id: appeal.id, rel: "hears")], at: 3)
        let evidence = try Court.userEvidence(fx, at: 4)
        let supreme = try plain(
            "대법원 결정", "ruling", "level: supreme\noutcome: reject\n\n기각\n",
            cites: [LawCite(id: proposal.id, rel: "hears"), LawCite(id: evidence.id, rel: "testifies")], at: 5)
        let registration = try plain("판결 등록", "registration", "repo: r\nstatus: provisional\n", at: 6)
        let sha = try store.putExhibit(Data("지울 증거물".utf8))
        let redaction = try plain(
            "가림", "redaction", "target: \(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: sha))\nreason: r\n",
            exhibits: [sha], at: 7)
        let contents = try plain("목차: agent-law", "contents", "목차\n", at: 8)
        let report = try plain("보고", "report", "보고\n", at: 9)
        return Seeded(
            knowledge: knowledge, appellate: appellate, supreme: supreme, registration: registration,
            redaction: redaction, contents: contents, report: report, appeal: appeal, proposal: proposal)
    }

    static func repeal(_ target: LawStoredRecord, type: String? = nil, actor: LawActor = Court.opus) -> LawDraft {
        LawDraft(actor: actor, title: "폐지", type: type ?? target.record.type ?? "record", repeals: target.id, body: "폐지")
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

    // MARK: - 일반 경로의 폐지

    @Test func generalRepealRefusesEveryProcessRecordEvenWithADisguisedType() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let seeded = try Self.seed(fx)
        let before = fx.records.count
        for target in seeded.processRecords {
            for type in [target.record.type, "record"] {
                let error = Self.refusal {
                    try LawEnactService.enact(Self.repeal(target, type: type), target: fx.target, now: Court.at(20))
                }
                switch error {
                case .targetIrreversible(target.id, _)?, .targetRequiresDedicatedCommand(target.id, _, _)?: break
                default: Issue.record("일반 폐지가 \(target.record.type ?? "?")(\(type ?? "?")) 를 받음: \(String(describing: error))")
                }
            }
            #expect(LawLedgerView(records: fx.records).isInForce(target.id))
        }
        // 화면 편집의 폐지·개정도 같은 판정을 받는다.
        #expect(throws: LedgerHumanEditError.self) {
            try LedgerHumanEdit.perform(.repeal(target: seeded.supreme.id, reason: "x"), target: fx.target, author: "user:yun")
        }
        #expect(throws: LedgerHumanEditError.self) {
            try LedgerHumanEdit.perform(
                .amend(target: seeded.supreme.id, title: "x", body: "level: supreme\noutcome: approve\n\n뒤집기\n", cites: []),
                target: fx.target, author: "user:yun")
        }
        // 유형을 바꿔 적은 개정으로도 대법원 결정을 현행에서 빼지 못한다.
        let amend = LawDraft(actor: Court.opus, title: "x", amends: seeded.supreme.id, body: "본문")
        #expect(Self.refusal { try LawEnactService.enact(amend, target: fx.target, now: Court.at(21)) }
                == .targetIrreversible(target: seeded.supreme.id, type: "ruling(level: supreme)"))
        #expect(fx.records.count == before)

        // 지식 기록의 폐지는 지금처럼 일반 경로가 한다.
        try LawEnactService.enact(Self.repeal(seeded.knowledge), target: fx.target, now: Court.at(22))
        #expect(!LawLedgerView(records: fx.records).isInForce(seeded.knowledge.id))
    }

    // MARK: - 전용 경로의 폐지

    @Test func dedicatedPathsRepealOnlyWhatTheRulesAllow() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let seeded = try Self.seed(fx)
        // 대법원 결정은 최종 — 어느 경로도 폐지·개정하지 못한다.
        for path in LawEnactPath.allCases {
            #expect(Self.refusal {
                try LawEnactService.enact(Self.repeal(seeded.supreme), target: fx.target, path: path, now: Court.at(20))
            } == .targetIrreversible(target: seeded.supreme.id, type: "ruling(level: supreme)"), "\(path)")
            // 가림은 되돌릴 수 없다.
            #expect(Self.refusal {
                try LawEnactService.enact(Self.repeal(seeded.redaction), target: fx.target, path: path, now: Court.at(20))
            } == .targetIrreversible(target: seeded.redaction.id, type: "redaction"), "\(path)")
        }
        // 항소심 결정은 court 경로만 폐지한다(dream 은 못 함).
        #expect(Self.refusal {
            try LawEnactService.enact(Self.repeal(seeded.appellate), target: fx.target, path: .dream, now: Court.at(21))
        } == .targetRequiresDedicatedCommand(target: seeded.appellate.id, type: "ruling", command: "court"))
        try LawEnactService.enact(Self.repeal(seeded.appellate), target: fx.target, path: .court, now: Court.at(21))
        // 판결 등록은 judgment, 목차·보고는 dream·contents, 이의·개정안은 court.
        try LawEnactService.enact(Self.repeal(seeded.registration), target: fx.target, path: .judgment, now: Court.at(22))
        try LawEnactService.enact(Self.repeal(seeded.contents), target: fx.target, path: .dream, now: Court.at(23))
        try LawEnactService.enact(Self.repeal(seeded.report), target: fx.target, path: .contents, now: Court.at(24))
        #expect(Self.refusal {
            try LawEnactService.enact(Self.repeal(seeded.appeal), target: fx.target, path: .dream, now: Court.at(25))
        } == .targetRequiresDedicatedCommand(target: seeded.appeal.id, type: "appeal", command: "court"))
        try LawEnactService.enact(Self.repeal(seeded.proposal), target: fx.target, path: .court, now: Court.at(26))
        let view = LawLedgerView(records: fx.records)
        for gone in [seeded.appellate, seeded.registration, seeded.contents, seeded.report, seeded.proposal] {
            #expect(!view.isInForce(gone.id))
        }
        #expect(view.isInForce(seeded.supreme.id))
        #expect(view.isInForce(seeded.redaction.id))
        #expect(view.isInForce(seeded.appeal.id))
    }

    // MARK: - 원상회복

    @Test func restoreOfABatchWithProcessRecordsIsRefusedWhole() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let seeded = try Self.seed(fx, batch: "mixed")
        _ = try Court.enact(fx, title: "같은 묶음 지식", batch: "mixed", at: 10)
        let before = try FileManager.default.subpathsOfDirectory(atPath: fx.target.root.path).sorted()
        for path in LawEnactPath.allCases {
            let error = Self.refusal {
                try LawEnactService.restore(batch: "mixed", actor: Court.opus, target: fx.target, path: path, now: Court.at(30))
            }
            guard case .restoreRefused(let reasons)? = error else {
                Issue.record("처리 기록이 든 묶음의 원상회복이 \(path) 로 통과함: \(String(describing: error))")
                continue
            }
            // 대법원 결정과 가림은 어느 경로에서든 이유 목록에 오른다.
            #expect(reasons.contains { $0.hasPrefix(String(seeded.supreme.id.prefix(8))) && $0.contains("대법원 결정은 최종") })
            #expect(reasons.contains { $0.hasPrefix(String(seeded.redaction.id.prefix(8))) && $0.contains("되돌릴 수 없음") })
        }
        // 아무것도 쓰지 않았다.
        #expect(try FileManager.default.subpathsOfDirectory(atPath: fx.target.root.path).sorted() == before)
        let view = LawLedgerView(records: fx.records)
        #expect(view.isInForce(seeded.supreme.id))
        #expect(view.isInForce(seeded.redaction.id))
    }

    @Test func courtRestoreRepealsAppellateRulingsAndKnowledgeOnlyRestoreStillWorks() throws {
        let fx = Court.fixture()
        defer { fx.cleanup() }
        let knowledge = try Court.enact(fx, title: "지식", at: 0)
        let appeal = try fx.service(Court.FakeAI([])).appeal(knowledge.id, reason: "이의", actor: Court.opus, now: Court.at(1))
        let ruling = try fx.target.store.enact(LawDraft(
            actor: Court.opus, title: "항소심 결정", type: "ruling", batch: "appellate",
            cites: [LawCite(id: appeal.id, rel: "hears")], body: "level: appellate\noutcome: uphold\n\n유지\n"),
            now: Court.at(2))
        // 일반 경로는 항소심 결정이 든 묶음을 되돌리지 못한다.
        guard case .restoreRefused? = Self.refusal({
            try LawEnactService.restore(batch: "appellate", actor: Court.opus, target: fx.target, now: Court.at(3))
        }) else { Issue.record("일반 원상회복이 항소심 결정을 폐지함"); return }
        #expect(LawLedgerView(records: fx.records).isInForce(ruling.id))
        // court 경로(결정의 조치)는 한다.
        let restored = try LawEnactService.restore(
            batch: "appellate", actor: Court.opus, target: fx.target, path: .court, now: Court.at(4))
        #expect(restored.map(\.record.repeals) == [ruling.id])
        #expect(!LawLedgerView(records: fx.records).isInForce(ruling.id))

        // 지식 기록만 든 묶음은 지금처럼 일반 경로로 되돌린다.
        let first = try Court.enact(fx, title: "첫 판", batch: "k1", at: 5)
        let amended = try LawEnactService.enact(LawDraft(
            actor: Court.opus, title: "둘째 판", batch: "k2", amends: first.id, body: "새 본문"),
            target: fx.target, now: Court.at(6))
        let created = try Court.enact(fx, title: "새 기록", batch: "k2", at: 7)
        let back = try LawEnactService.restore(batch: "k2", actor: Court.opus, target: fx.target, now: Court.at(8))
        #expect(back.count == 2)
        let view = LawLedgerView(records: fx.records)
        #expect(!view.isInForce(amended.id))
        #expect(!view.isInForce(created.id))
        #expect(back.contains { $0.record.amends == amended.id && $0.record.title == "첫 판" })
    }

    // MARK: - 승격 유형

    @Test func promoteAcceptsOnlyKnowledgeRecordsAndEvidence() throws {
        let fx = try Enact.fixture()
        defer { fx.cleanup() }
        let person = fx.target("agent-law-person-a")
        let base = try LawEnactService.enact(Enact.draft("대상"), target: person)
        let finding = try LawEnactService.enact(LawDraft(
            actor: Enact.agent, title: "사실인정", type: "finding", cites: [LawCite(id: base.id, rel: "finds")],
            body: "subject: project\ncertainty: confirmed\ndomain: dev-workflow\nreason: r\n"), target: person, path: .finding)
        let checkpoint = try LawEnactService.checkpoint(actor: Enact.agent, target: person)
        let law = fx.target("agent-law")
        let lawBefore = law.store.scan().count
        for refused in [finding, checkpoint] {
            do {
                _ = try LawPromotionService.promote(
                    sourceID: refused.id, source: person, targetWorld: "agent-law", actor: Enact.agent)
                Issue.record("처리 기록 \(refused.record.type ?? "?") 이 승격됨")
            } catch let LawPromotionError.typeNotPromotable(type) {
                #expect(type == refused.record.type)
            }
        }
        #expect(law.store.scan().count == lawBefore)
        let article = try LawEnactService.enact(LawDraft(
            actor: Enact.agent, title: "조문", type: "article", body: "조문 본문"), target: person)
        for allowed in [base, article] {
            let result = try LawPromotionService.promote(
                sourceID: allowed.id, source: person, targetWorld: "agent-law", actor: Enact.agent)
            #expect(!result.deduplicated)
        }
        #expect(LawPromotionService.promotableTypes == [.record, .article, .judgment, .evidence])
    }
}
