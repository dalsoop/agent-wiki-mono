import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

// 승격된 증거의 증언 시험. 소환 시험의 임시 원장·가짜 R2·주입 세션 원천만 쓴다.
// 근거: docs/business-rules.md "화자"(2026-10-04 사용자 결정 "개인에서 확인한 증거를 승격")·"관계",
// docs/contracts.md "승격", docs/security.md "agent-law" 격리 표.

/// 무엇이든 정해진 화자로 확인하는 확인자 — 세션과 어긋난 증거·위조 증거를 원장에 심을 때만 쓴다.
private struct RubberStampTestimony: LawTestimonyVerifying {
    let speaker: LawSpeaker
    func speaker(for request: LawTestimonyRequest) throws -> LawSpeaker? { speaker }
}

@Suite struct AgentLawPromotedTestimonyTests {
    typealias Base = AgentLawSummonTests
    static let person = "agent-law-person-a"
    static let shared = "agent-law"

    static func context(_ target: LawLedgerTarget) -> LawEnactContext {
        LawEnactService.context(index: LawEnactService.scope(of: target), testimony: target.defaultTestimony)
    }

    static func sharedClaim(citing id: String) -> LawDraft {
        LawDraft(
            actor: Base.agent, speaker: "user", title: "공유 규칙: 배포 순서",
            cites: [LawCite(id: id, rel: LawRelation.testifies.rawValue)], body: "배포 순서는 사용자가 정한다")
    }

    // MARK: - 정상 흐름

    @Test func promotedEvidenceGivesSharedRecordUserTestimony() throws {
        let fx = try Base.fixture()
        defer { fx.cleanup() }
        let person = fx.target(Self.person)
        let law = fx.target(Self.shared)
        let evidence = try LawSummonService.record(
            index: 0, query: LawSummonQuery(session: "s-a"), target: person, actor: Base.agent)
        #expect(evidence.record.record.speaker == "user")

        // 승격 전: 공유 원장은 개인 세션을 대조할 수 없고, 개인 증거를 인용할 수도 없다.
        #expect(throws: LawEnactServiceError.self) {
            try LawEnactService.enact(Self.sharedClaim(citing: evidence.record.id), target: law)
        }

        let result = try LawPromotionService.promote(
            sourceID: evidence.record.id, source: person, targetWorld: Self.shared, actor: Base.agent)
        #expect(!result.deduplicated)
        let promoted = try #require(law.store.scan().first { $0.id == result.promotedObjectId })
        #expect(promoted.record.type == "evidence")
        #expect(promoted.record.speaker == "user")
        #expect(promoted.record.tags.contains("promoted"))
        #expect(promoted.record.exhibits == [evidence.exhibit])
        #expect(promoted.record.body == evidence.record.record.body)
        // 증거물은 대상 원장 exhibits/ 로 복사된다.
        #expect(try law.store.exhibit(sha256: evidence.exhibit) == person.store.exhibit(sha256: evidence.exhibit))
        // 대상 쪽 표지(대상 영수증)와 원본 영수증.
        let targetReceipt = try #require(law.store.scan().first { $0.id == result.targetReceiptObjectId })
        #expect(targetReceipt.record.cites == [LawCite(id: promoted.id, rel: "receipts")])
        #expect(person.store.scan().contains { $0.id == result.sourceReceiptObjectId })

        #expect(LawPromotionWitness(index: LawEnactService.scope(of: law)).status(of: promoted.id) == .genuine)

        // 공유 원장 기록이 승격된 증거를 testifies 로 인용하면 speaker: user 가 인정된다.
        let claim = try LawEnactService.enact(Self.sharedClaim(citing: promoted.id), target: law)
        #expect(claim.record.speaker == "user")

        // 감사: 승격된 증거는 위반이 아니다(양쪽 원장).
        let lawReport = law.store.audit(context: Self.context(law))
        #expect(lawReport.passed, "\(lawReport.violations)")
        let personReport = person.store.audit(context: Self.context(person))
        #expect(personReport.passed, "\(personReport.violations)")

        // 다시 승격하면 기존 영수증을 쓴다.
        let again = try LawPromotionService.promote(
            sourceID: evidence.record.id, source: person, targetWorld: Self.shared, actor: Base.agent)
        #expect(again.deduplicated)
        #expect(again.promotedObjectId == promoted.id)
    }

    // MARK: - 원본 증언 불일치

    @Test func promotionRefusesEvidenceWhoseTestimonyNoLongerMatches() throws {
        let fx = try Base.fixture()
        defer { fx.cleanup() }
        let person = fx.target(Self.person)
        let law = fx.target(Self.shared)
        // assistant 발화를 user 라고 적은 증거를 (확인을 건너뛰어) 원장에 심는다.
        let quote = Data("네, 정했습니다".utf8)
        let sha = try person.store.putExhibit(quote)
        let lie = try person.store.enact(
            LawDraft(
                actor: Base.agent, speaker: "user", title: "거짓 증언", type: "evidence", exhibits: [sha],
                body: "session: s-a\nruntime: claude-code\n\n네, 정했습니다"),
            context: LawEnactContext(testimony: RubberStampTestimony(speaker: .user)))
        #expect(lie.record.speaker == "user")

        do {
            _ = try LawPromotionService.promote(
                sourceID: lie.id, source: person, targetWorld: Self.shared, actor: Base.agent)
            Issue.record("증언이 맞지 않는 증거가 승격됨")
        } catch LawPromotionError.testimonyRefused(let id) {
            #expect(id == lie.id)
        }
        // 거부되면 대상 원장에도 원본 원장에도 아무것도 쓰지 않는다(증거물 복사 포함).
        #expect(law.store.scan().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: law.store.exhibitURL(sha256: sha).path))
        #expect(!person.store.scan().contains { $0.record.type == "promotion-receipt" })

        // 세션을 찾을 수 없는 증거도 거부된다.
        let ghostSha = try person.store.putExhibit(Data("없는 대화".utf8))
        let ghost = try person.store.enact(
            LawDraft(
                actor: Base.agent, speaker: "user", title: "유령 증언", type: "evidence", exhibits: [ghostSha],
                body: "session: s-none\n\n없는 대화"),
            context: LawEnactContext(testimony: RubberStampTestimony(speaker: .user)))
        #expect(throws: LawPromotionError.self) {
            try LawPromotionService.promote(
                sourceID: ghost.id, source: person, targetWorld: Self.shared, actor: Base.agent)
        }
    }

    // MARK: - 위조

    @Test func forgedPromotionClaimIsRefusedForEnactCitationAndAudit() throws {
        let fx = try Base.fixture()
        defer { fx.cleanup() }
        let person = fx.target(Self.person)
        let law = fx.target(Self.shared)
        let quote = Data("배포 순서를 정해줘".utf8)
        let sha = try law.store.putExhibit(quote)
        let forgedDraft = LawDraft(
            actor: Base.agent, speaker: "user", title: "증언: claude-code/s-a #0", type: "evidence",
            tags: ["promoted"], exhibits: [sha], body: "session: s-a\nruntime: claude-code\n\n배포 순서를 정해줘")

        // 1) 공포 경로: 공유 원장에서 "승격본"이라고만 주장하는 증거는 세션 대조에 걸린다.
        do {
            _ = try LawEnactService.enact(forgedDraft, target: law)
            Issue.record("승격본 주장만으로 공유 원장에 증거가 공포됨")
        } catch LawEnactServiceError.enact(let error) {
            #expect(error == .testimonyMismatch)
        }

        // 2) 확인을 건너뛰어 심은 위조 증거 + 원본을 지어낸 대상 영수증.
        let forged = try law.store.enact(
            forgedDraft, context: LawEnactContext(testimony: RubberStampTestimony(speaker: .user)))
        let genuineSource = try LawSummonService.record(
            index: 0, query: LawSummonQuery(session: "s-a"), target: person, actor: Base.agent)
        let fakeReceipt = PromotionReceipt(PromotionReceipt.Draft(
            sourceKind: "world", sourceWorldName: Self.person, sourceObjectId: genuineSource.record.id,
            sourceWorldRoot: person.root.standardizedFileURL.path, targetWorld: Self.shared,
            targetWorldRoot: law.root.standardizedFileURL.path, targetObjectId: forged.id,
            promotedAt: Date(), promotedBy: Base.agent.author))
        try LawEnactService.enact(
            LawDraft(
                actor: Base.agent, title: "프로모션 영수증: 위조", type: "promotion-receipt",
                cites: [LawCite(id: forged.id, rel: "receipts")], body: try fakeReceipt.json()),
            target: law, path: .promote)

        let witness = LawPromotionWitness(index: LawEnactService.scope(of: law))
        guard case .unproven = witness.status(of: forged.id) else {
            Issue.record("위조 승격본이 확인됨")
            return
        }
        // 인용: 위조 승격본은 speaker: user 증언이 되지 못한다.
        do {
            _ = try LawEnactService.enact(Self.sharedClaim(citing: forged.id), target: law)
            Issue.record("위조 승격본을 인용한 speaker: user 가 공포됨")
        } catch LawEnactServiceError.enact(let error) {
            #expect(error == .speakerUserRequiresTestimony)
        }
        // 감사: 위반으로 잡는다.
        let report = law.store.audit(context: Self.context(law))
        #expect(report.violations.contains { $0.id == forged.id && $0.problem.hasPrefix("승격본 미확인") })

        // 3) 설정이 없는 문맥(같은 원장만)에서는 승격본 주장을 확인할 수 없다.
        #expect(LawPromotionWitness(records: law.store.scan()).status(of: forged.id) != .genuine)
    }

    // MARK: - 테넌트 격리

    @Test func siblingTenantEvidenceStaysIsolated() throws {
        let fx = try Base.fixture()
        defer { fx.cleanup() }
        let person = fx.target(Self.person)
        let tenantB = fx.target("agent-law-tenant-b")
        let law = fx.target(Self.shared)
        let sibling = try LawSummonService.record(
            index: 0, query: LawSummonQuery(session: "s-gujo"), target: tenantB, actor: Base.agent)
        #expect(sibling.record.record.speaker == "user")

        // 개인 원장은 형제 테넌트 증거를 인용할 수 없다.
        let claim = LawDraft(
            actor: Base.agent, speaker: "user", title: "개인 기록",
            cites: [LawCite(id: sibling.record.id, rel: LawRelation.testifies.rawValue)], body: "본문")
        do {
            _ = try LawEnactService.enact(claim, target: person)
            Issue.record("형제 테넌트 증거가 인용됨")
        } catch LawEnactServiceError.enact(let error) {
            #expect(error == .unresolvedReference(sibling.record.id))
        }
        // 형제 테넌트로는 승격하지 않는다.
        #expect(throws: LawPromotionError.self) {
            try LawPromotionService.promote(
                sourceID: sibling.record.id, source: tenantB, targetWorld: Self.person, actor: Base.agent)
        }
        // 개인 원장에서 승격해도 형제 테넌트의 다른 구절은 공유로 가지 않는다.
        let mine = try LawSummonService.record(
            index: 0, query: LawSummonQuery(session: "s-a"), target: person, actor: Base.agent)
        _ = try LawPromotionService.promote(
            sourceID: mine.record.id, source: person, targetWorld: Self.shared, actor: Base.agent)
        #expect(!law.store.scan().contains { $0.record.body == sibling.record.record.body })
        #expect(!FileManager.default.fileExists(atPath: law.store.exhibitURL(sha256: sibling.exhibit).path))

        // 공유 원장에 "형제 테넌트 증거의 승격본"이라고 영수증만 지어내도 원본 원장이 대상의 하위가 아니면 거부.
        let copySha = try law.store.putExhibit(try tenantB.store.exhibit(sha256: sibling.exhibit))
        let copy = try law.store.enact(
            LawDraft(
                actor: Base.agent, speaker: "user", title: sibling.record.record.title, type: "evidence",
                tags: ["promoted"], exhibits: [copySha], body: sibling.record.record.body),
            context: LawEnactContext(testimony: RubberStampTestimony(speaker: .user)))
        let fake = PromotionReceipt(PromotionReceipt.Draft(
            sourceKind: "world", sourceWorldName: Self.person, sourceObjectId: sibling.record.id,
            sourceWorldRoot: tenantB.root.standardizedFileURL.path, targetWorld: Self.shared,
            targetWorldRoot: law.root.standardizedFileURL.path, targetObjectId: copy.id,
            promotedAt: Date(), promotedBy: Base.agent.author))
        try LawEnactService.enact(
            LawDraft(
                actor: Base.agent, title: "프로모션 영수증: 위조", type: "promotion-receipt",
                cites: [LawCite(id: copy.id, rel: "receipts")], body: try fake.json()),
            target: law, path: .promote)
        #expect(LawPromotionWitness(index: LawEnactService.scope(of: law)).status(of: copy.id) != .genuine)
        #expect(throws: LawEnactServiceError.self) {
            try LawEnactService.enact(Self.sharedClaim(citing: copy.id), target: law)
        }
    }
}
