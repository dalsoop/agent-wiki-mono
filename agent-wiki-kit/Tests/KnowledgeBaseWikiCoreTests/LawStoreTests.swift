import CitationLedgerKit
import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// ledger 3 공포·감사 시험 — 근거: docs/business-rules.md "agent-law(ledger 3)", 결정 0007.
/// 실제 원장이 아니라 임시 디렉터리 루트만 쓴다.
@Suite struct LawStoreTests {

    // MARK: - 준비

    private func makeStore() -> LawStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("law-\(UUID())", isDirectory: true)
        return LawStore(root: root)
    }

    private static let base = Date(timeIntervalSince1970: 1_790_000_000)
    private func at(_ seconds: Double) -> Date { Self.base.addingTimeInterval(seconds) }

    private let agent = LawActor(
        author: "agent:claude@macbook", kind: .agent, device: "macbook",
        runtime: "claude-code", runtimeVersion: "2.1.0", model: "claude-opus-5-5", effort: "high")
    private let human = LawActor(author: "user:yun", kind: .human, device: "macbook")
    private let app = LawActor(author: "app:agent-wiki", kind: .app, device: "macbook",
                               app: "agent-wiki", appVersion: "1.0.0")

    private func draft(
        _ actor: LawActor? = nil, type: String = "record", title: String = "제목", body: String = "본문",
        speaker: String? = nil, origin: String? = nil, batch: String? = nil, cites: [LawCite] = [],
        exhibits: [String] = [], amends: String? = nil, amendsAlso: [String] = [],
        repeals: String? = nil, cost: LawCost? = nil
    ) -> LawDraft {
        LawDraft(actor: actor ?? agent, speaker: speaker, title: title, type: type, origin: origin,
                 batch: batch, cites: cites, exhibits: exhibits, amends: amends, amendsAlso: amendsAlso,
                 repeals: repeals, body: body, cost: cost)
    }

    /// 가짜 증언 확인자 — 인용 구절이 발화의 연속 부분 문자열이면 그 화자.
    struct FakeTestimony: LawTestimonyVerifying {
        let utterances: [(text: String, speaker: LawSpeaker)]
        func speaker(for request: LawTestimonyRequest) throws -> LawSpeaker? {
            guard let quote = request.quotes.first?.text, !quote.isEmpty else { return nil }
            return utterances.first(where: { $0.text.contains(quote) })?.speaker
        }
    }

    /// 가짜 참조 해석기 — 전신 객체 하나를 안다.
    struct FakePredecessor: LawReferenceResolving {
        let id: String
        func resolve(_ ref: String) -> LawResolvedReference? {
            ref == id ? LawResolvedReference(id: id, type: "concept", origin: nil, speaker: nil, scope: .predecessor) : nil
        }
    }

    private func putExhibit(_ store: LawStore, _ text: String) throws -> String {
        let sha = LawHash.sha256Hex(text)
        let url = store.exhibitURL(sha256: sha)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        return sha
    }

    private func userEvidence(_ store: LawStore, quote: String, now: Date) throws -> LawStoredRecord {
        let sha = try putExhibit(store, quote)
        let context = LawEnactContext(testimony: FakeTestimony(utterances: [("앞 \(quote) 뒤", .user)]))
        return try store.enact(
            draft(type: "evidence", body: "session: s-1\nutterance-at: 2026-10-04T00:00:00Z\n\n인용",
                  speaker: "user", exhibits: [sha]),
            now: now, context: context)
    }

    // MARK: - 정체성·왕복

    @Test func enactThenAuditRoundTrip() throws {
        let store = makeStore()
        let stored = try store.enact(draft(cost: LawCost(tokensIn: 5, session: "s")), now: at(0))
        #expect(LawHash.isContentID(stored.id))
        #expect(stored.id == CitationLedger.sha256Hex(stored.record.canonicalCore()))
        let comps = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: at(0))
        let expectedPath = store.root.appendingPathComponent(
            String(format: "objects/%04d/%02d/%@.md", comps.year!, comps.month!, stored.id))
        let text = try String(contentsOf: expectedPath, encoding: .utf8)
        #expect(text == stored.record.serialize())
        #expect(store.scan().map(\.id) == [stored.id])
        let report = store.audit()
        #expect(report.violations.isEmpty)
        #expect(report.pendingJudgment == [stored.id])
    }

    @Test func auditDetectsCoreAndBodyTamper() throws {
        let store = makeStore()
        let a = try store.enact(draft(title: "A"), now: at(0))
        let b = try store.enact(draft(title: "B"), now: at(1))
        let urlA = store.objectURL(id: a.id, promulgated: a.record.promulgated)
        let urlB = store.objectURL(id: b.id, promulgated: b.record.promulgated)
        let textA = try String(contentsOf: urlA, encoding: .utf8)
        try textA.replacingOccurrences(of: "model: claude-opus-5-5", with: "model: other")
            .write(to: urlA, atomically: true, encoding: .utf8)
        let textB = try String(contentsOf: urlB, encoding: .utf8)
        try (textB + "x").write(to: urlB, atomically: true, encoding: .utf8)
        let problems = store.audit().violations
        #expect(problems.contains { $0.id == a.id && $0.problem.contains("코어 변조") })
        #expect(problems.contains { $0.id == b.id && $0.problem.contains("본문 변조") })
    }

    @Test func modelChangesIDAndCostDoesNot() throws {
        let one = try makeStore().enact(draft(cost: nil), now: at(0))
        let two = try makeStore().enact(draft(cost: LawCost(tokensIn: 99, objectsRead: 4, session: "z")), now: at(0))
        #expect(one.id == two.id)
        var other = agent
        other.model = "claude-sonnet-5"
        let three = try makeStore().enact(draft(other), now: at(0))
        #expect(three.id != one.id)
    }

    @Test func idempotentAndDifferentBytesFail() throws {
        let store = makeStore()
        let first = try store.enact(draft(), now: at(0))
        let again = try store.enact(draft(), now: at(0))
        #expect(first.id == again.id)
        #expect(throws: LawEnactError.duplicateID(first.id)) {
            try store.enact(draft(cost: LawCost(tokensIn: 1)), now: at(0))
        }
    }

    // MARK: - 작성자와 모델 기록

    @Test func agentModelRules() throws {
        let store = makeStore()
        var noModel = agent
        noModel.model = nil
        #expect(throws: LawEnactError.modelUnknown) { try store.enact(draft(noModel), now: at(0)) }
        var noRuntime = agent
        noRuntime.runtime = nil
        #expect(throws: LawEnactError.runtimeUnknown) { try store.enact(draft(noRuntime), now: at(0)) }
        var noEffort = agent
        noEffort.effort = nil
        let stored = try store.enact(draft(noEffort), now: at(1))
        #expect(stored.record.effort == "unknown")
        #expect(stored.record.speaker == "agent")
    }

    @Test func appAndHumanRules() throws {
        let store = makeStore()
        var noVersion = app
        noVersion.appVersion = nil
        #expect(throws: LawEnactError.appIdentityMissing) { try store.enact(draft(noVersion), now: at(0)) }
        let mechanical = try store.enact(draft(app), now: at(1))
        #expect(mechanical.record.model == nil)
        #expect(mechanical.record.speaker == nil)
        var humanWithModel = human
        humanWithModel.model = "x"
        #expect(throws: LawEnactError.humanModelFields) { try store.enact(draft(humanWithModel), now: at(2)) }
        let byHuman = try store.enact(draft(human), now: at(3))
        #expect(byHuman.record.speaker == "user")
    }

    // MARK: - 화자와 증언

    @Test func evidenceDefaultsToExternal() throws {
        let store = makeStore()
        let evidence = try store.enact(draft(type: "evidence", body: "외부 문서 요약"), now: at(0))
        #expect(evidence.record.speaker == "external")
    }

    @Test func testimonyMatchMismatchAndMissing() throws {
        let store = makeStore()
        let matched = try userEvidence(store, quote: "그렇게 해", now: at(0))
        #expect(matched.record.speaker == "user")

        let sha = try putExhibit(store, "말한 적 없는 구절")
        let body = "session: s-1\n\n인용"
        let mismatch = LawEnactContext(testimony: FakeTestimony(utterances: [("전혀 다른 발화", .user)]))
        #expect(throws: LawEnactError.testimonyMismatch) {
            try store.enact(self.draft(type: "evidence", body: body, speaker: "user", exhibits: [sha]),
                            now: self.at(1), context: mismatch)
        }
        #expect(throws: LawEnactError.testimonyUnavailable) {
            try store.enact(self.draft(type: "evidence", body: body, speaker: "user", exhibits: [sha]),
                            now: self.at(2))
        }
    }

    @Test func speakerUserNeedsTestimony() throws {
        let store = makeStore()
        #expect(throws: LawEnactError.speakerUserRequiresTestimony) {
            try store.enact(self.draft(speaker: "user"), now: self.at(0))
        }
        let external = try store.enact(draft(type: "evidence", body: "외부"), now: at(1))
        #expect(throws: LawEnactError.speakerUserRequiresTestimony) {
            try store.enact(self.draft(speaker: "user", cites: [LawCite(id: external.id, rel: "testifies")]),
                            now: self.at(2))
        }
        let evidence = try userEvidence(store, quote: "이렇게 하자", now: at(3))
        let record = try store.enact(
            draft(speaker: "user", cites: [LawCite(id: evidence.id, rel: "testifies")]), now: at(4))
        #expect(record.record.speaker == "user")
    }

    // MARK: - 관계·출처

    @Test func relationRulesRefused() throws {
        let store = makeStore()
        let target = try store.enact(draft(), now: at(0))
        #expect(throws: LawEnactError.relationNotAllowed("rolls-back")) {
            try store.enact(self.draft(cites: [LawCite(id: target.id, rel: "rolls-back")]), now: self.at(1))
        }
        #expect(throws: LawEnactError.relationSourceRefused(rel: "finds", type: "record")) {
            try store.enact(self.draft(cites: [LawCite(id: target.id, rel: "finds")]), now: self.at(2))
        }
        let evidence = try store.enact(draft(type: "evidence", body: "외부"), now: at(3))
        #expect(throws: LawEnactError.relationTargetRefused(rel: "finds", target: evidence.id)) {
            try store.enact(self.draft(type: "finding", body: Self.findingBody("person"),
                                       cites: [LawCite(id: evidence.id, rel: "finds")]), now: self.at(4))
        }
        #expect(throws: LawEnactError.unresolvedReference(String(repeating: "0", count: 64))) {
            try store.enact(self.draft(cites: [LawCite(id: String(repeating: "0", count: 64))]), now: self.at(5))
        }
    }

    @Test func dreamRecordsCannotBeEvidence() throws {
        let store = makeStore()
        let dreamApp = LawActor(author: "app:agent-wiki", kind: .app, device: "macbook", runtime: "claude-code",
                                model: "claude-opus-5-5", app: "agent-wiki", appVersion: "1.0.0")
        let dreamRecord = try store.enact(draft(dreamApp, origin: "dream"), now: at(0))
        let dreamEvidence = try store.enact(draft(dreamApp, type: "evidence", body: "정리", origin: "dream"), now: at(1))
        #expect(throws: LawEnactError.dreamCitationRefused(dreamEvidence.id)) {
            try store.enact(self.draft(cites: [LawCite(id: dreamEvidence.id, rel: "testifies")]), now: self.at(2))
        }
        #expect(throws: LawEnactError.dreamCitationRefused(dreamRecord.id)) {
            try store.enact(self.draft(type: "finding", body: Self.findingBody("project"),
                                       cites: [LawCite(id: dreamRecord.id, rel: "finds")]), now: self.at(3))
        }
        // 일반 참조는 된다.
        _ = try store.enact(draft(cites: [LawCite(id: dreamRecord.id)]), now: at(4))
    }

    @Test func migrationRequiresMigratedFrom() throws {
        let store = makeStore()
        let oldID = String(repeating: "b", count: 64)
        let context = LawEnactContext(resolver: FakePredecessor(id: oldID))
        #expect(throws: LawEnactError.migrationRequiresMigratedFrom) {
            try store.enact(self.draft(origin: "migration"), now: self.at(0), context: context)
        }
        let migrated = try store.enact(
            draft(origin: "migration", cites: [LawCite(id: oldID, rel: "migrated-from")]), now: at(1), context: context)
        // 같은 원장 기록은 전신 객체가 아니다.
        #expect(throws: LawEnactError.relationTargetRefused(rel: "migrated-from", target: migrated.id)) {
            try store.enact(self.draft(origin: "migration", cites: [LawCite(id: migrated.id, rel: "migrated-from")]),
                            now: self.at(2), context: context)
        }
        // 기본 해석기는 같은 원장만 본다.
        #expect(throws: LawEnactError.unresolvedReference(oldID)) {
            try store.enact(self.draft(origin: "migration", cites: [LawCite(id: oldID, rel: "migrated-from")]),
                            now: self.at(3))
        }
    }

    @Test func emptyBodyRefusedExceptRepeal() throws {
        let store = makeStore()
        #expect(throws: LawEnactError.emptyBody) { try store.enact(self.draft(body: "  \n"), now: self.at(0)) }
        let target = try store.enact(draft(), now: at(1))
        let repeal = try store.enact(draft(title: "폐지", body: "", repeals: target.id), now: at(2))
        #expect(repeal.record.repeals == target.id)
    }

    // MARK: - 개정·폐지·원상회복·현행

    @Test func amendRepealAndInForce() throws {
        let store = makeStore()
        let v1 = try store.enact(draft(title: "v1"), now: at(0))
        let v2 = try store.enact(draft(title: "v2", amends: v1.id), now: at(1))
        let other = try store.enact(draft(title: "other"), now: at(2))
        let repeal = try store.enact(draft(title: "폐지", body: "", repeals: other.id), now: at(3))
        let view = LawLedgerView(records: store.scan())
        #expect(Set(view.inForce.map(\.id)) == [v2.id])
        #expect(view.history(of: v2.id).map(\.id) == [v2.id, v1.id])
        #expect(!view.isInForce(repeal.id))
    }

    @Test func restoreRevertsBatch() throws {
        let store = makeStore()
        let v1 = try store.enact(draft(title: "v1", body: "옛 본문"), now: at(0))
        let v2 = try store.enact(draft(title: "v2", body: "새 본문", batch: "batch-1", amends: v1.id), now: at(1))
        let fresh = try store.enact(draft(title: "new", batch: "batch-1"), now: at(2))
        let restored = try store.restore(batch: "batch-1", actor: agent, now: at(3))
        #expect(restored.count == 2)
        let view = LawLedgerView(records: store.scan())
        let current = view.inForce
        #expect(current.count == 1)
        #expect(current.first?.record.body == "옛 본문")
        #expect(current.first?.record.amends == v2.id)
        #expect(!view.isInForce(fresh.id))
        #expect(throws: LawEnactError.batchNotFound("none")) {
            try store.restore(batch: "none", actor: self.agent, now: self.at(4))
        }
        // 파일은 지우지 않는다.
        #expect(store.scan().count == 5)
    }

    // MARK: - 사실인정과 4종류

    static func findingBody(_ subject: String, reason: String = "근거") -> String {
        "subject: \(subject)\ncertainty: confirmed\ndomain: dev-workflow\nreason: \(reason)\n\n설명"
    }

    @Test func currentFindingAndMemoryKinds() throws {
        let store = makeStore()
        func finding(_ target: String, _ subject: String, _ t: Double, amends: String? = nil) throws -> LawStoredRecord {
            try store.enact(draft(type: "finding", body: Self.findingBody(subject, reason: "r\(t)"),
                                  cites: [LawCite(id: target, rel: "finds")], amends: amends), now: at(t))
        }
        let person = try store.enact(draft(title: "사람"), now: at(0))
        let first = try finding(person.id, "project", 1)
        let second = try finding(person.id, "person", 2)
        let projectRec = try store.enact(draft(title: "진행"), now: at(3))
        let pf = try finding(projectRec.id, "external", 4)
        _ = try finding(projectRec.id, "project", 5, amends: pf.id)
        let reference = try store.enact(draft(title: "위치"), now: at(6))
        _ = try finding(reference.id, "external", 7)
        let evidence = try userEvidence(store, quote: "그거 하지 마", now: at(8))
        let feedback = try store.enact(
            draft(title: "지적", speaker: "user", cites: [LawCite(id: evidence.id, rel: "testifies")]), now: at(9))
        _ = try finding(feedback.id, "agent-self", 10)
        let selfAgent = try store.enact(draft(title: "에이전트 자신"), now: at(11))
        _ = try finding(selfAgent.id, "agent-self", 12)
        let article = try store.enact(draft(type: "article", title: "조문"), now: at(13))
        _ = try finding(article.id, "person", 14)

        let view = LawLedgerView(records: store.scan())
        #expect(view.currentFinding(for: person.id)?.id == second.id)
        #expect(view.currentFinding(for: person.id)?.id != first.id)
        #expect(view.memoryKind(of: person.id) == .person)
        #expect(view.memoryKind(of: projectRec.id) == .project)
        #expect(view.memoryKind(of: reference.id) == .reference)
        #expect(view.memoryKind(of: feedback.id) == .feedback)
        #expect(view.memoryKind(of: selfAgent.id) == .unclassified)
        #expect(view.memoryKind(of: article.id) == nil)
    }

    // MARK: - 감사

    @Test func auditPendingRedactedAndMissingExhibits() throws {
        let store = makeStore()
        let judged = try store.enact(draft(title: "판단됨"), now: at(0))
        _ = try store.enact(draft(type: "finding", body: Self.findingBody("person"),
                                  cites: [LawCite(id: judged.id, rel: "finds")]), now: at(1))
        let pending = try store.enact(draft(title: "대기"), now: at(2))
        let present = try putExhibit(store, "있는 증거물")
        let redactedSHA = LawHash.sha256Hex("가린 증거물")
        let missingSHA = LawHash.sha256Hex("사라진 증거물")
        _ = try store.enact(draft(type: "evidence", body: "외부", exhibits: [present]), now: at(3))
        let redactedEvidence = try store.enact(draft(type: "evidence", body: "외부 2", exhibits: [redactedSHA]), now: at(4))
        _ = try store.enact(draft(type: "redaction",
                                  body: "target: law/exhibits/\(redactedSHA.prefix(2))/\(redactedSHA)\nreason: 비밀\n",
                                  cites: [LawCite(id: redactedEvidence.id)]), now: at(5))
        let lost = try store.enact(draft(type: "evidence", body: "외부 3", exhibits: [missingSHA]), now: at(6))

        let report = store.audit()
        #expect(report.pendingJudgment == [pending.id])
        #expect(report.redactedExhibits == [LawRedactedExhibit(recordID: redactedEvidence.id, sha256: redactedSHA)])
        #expect(report.violations.map(\.id) == [lost.id])
        #expect(report.violations.first?.problem.contains("증거물 누락") == true)
    }

    @Test func auditReportsDivergentInForce() throws {
        let store = makeStore()
        let base = try store.enact(draft(title: "base"), now: at(0))
        let left = try store.enact(draft(title: "left", amends: base.id), now: at(1))
        let right = try store.enact(draft(title: "right", amends: base.id), now: at(2))
        let report = store.audit()
        #expect(report.divergent == [LawDivergence(amended: base.id, heads: [left.id, right.id].sorted())])
        _ = try store.enact(draft(title: "merge", amends: left.id, amendsAlso: [right.id]), now: at(3))
        #expect(store.audit().divergent.isEmpty)
    }

    @Test func auditReportsMissingReferenceAndRelationViolation() throws {
        let store = makeStore()
        let target = try store.enact(draft(), now: at(0))
        // 공포 경로를 거치지 않은 기록(형식만 맞음)을 직접 넣어 감사의 독립 판정을 본다.
        let ghost = String(repeating: "c", count: 64)
        var bad = LawRecord(promulgated: at(1), author: "agent:x@y",
                            authorship: LawAuthorship(authorKind: "agent", device: "y", runtime: "codex",
                                                      model: "m", effort: "unknown", speaker: "agent"),
                            type: "record",
                            relations: LawRelations(cites: [LawCite(id: target.id, rel: "finds"), LawCite(id: ghost)]),
                            body: "x")
        bad = bad.nfcNormalized()
        let url = store.objectURL(id: bad.contentID(), promulgated: bad.promulgated)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bad.serialize().write(to: url, atomically: true, encoding: .utf8)
        let problems = store.audit().violations.filter { $0.id == bad.contentID() }.map(\.problem)
        #expect(problems.contains { $0.contains("없는 기록 참조") })
        #expect(problems.contains { $0.contains("관계 규칙") })
    }
}
