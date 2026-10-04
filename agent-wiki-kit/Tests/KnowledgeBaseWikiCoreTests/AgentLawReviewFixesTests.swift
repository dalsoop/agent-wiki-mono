import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// 최종 검토 차단 문제 시험 — 사람 행세, 처리 유형 위조, 위조 결정·가림 기록, 옛 승격 쓰기 게이트, 드리밍 실행 전체 상한.
/// 근거: docs/security.md agent-law 절, docs/business-rules.md "유형"·"화자"·"심급제"·"드리밍", 결정 0007.
/// 임시 디렉터리 루트만 쓴다. 실제 원장·R2·AI 는 쓰지 않는다.
@Suite struct AgentLawReviewFixesTests {
    typealias Enact = AgentLawEnactPathTests
    typealias Court = AgentLawCourtTests

    static let human = LawActor(author: "user:yun", kind: .human, device: "mac", runtime: "human")
    static let appActor = LawActor(
        author: "app:agent-wiki", kind: .app, device: "mac", runtime: "app", app: "agent-wiki", appVersion: "9.9.9")

    // MARK: - 1. 사람 행세

    @Test func humanAuthorIsRefusedWhenTheEnvironmentShowsAnAgentSession() throws {
        let markers: [[String: String]] = [
            ["CLAUDE_CODE_SESSION_ID": "s-1"],
            ["CODEX_THREAD_ID": "t-1"],
            ["AI_AGENT": "claude-code_2-1-286_agent"],
            ["CLAUDECODE": "1"],
            ["AGENT_WIKI_RUNTIME": "claude-code"],
        ]
        for environment in markers {
            do {
                _ = try LawActorResolution.actor(author: "user:x", environment: environment, device: "mac")
                Issue.record("에이전트 표지가 있는데 사람 작성자가 통과함: \(environment)")
            } catch let LawActorError.humanInAgentSession(marker) {
                #expect(environment[marker] != nil)
                #expect(LawActorError.humanInAgentSession(marker).description.contains("에이전트 세션에서 사람 작성자 불가"))
            }
        }
        // 사람이 자기 터미널(에이전트 표지 없음)에서 쓰는 것은 그대로 허용.
        for environment in [[:], ["AGENT_WIKI_RUNTIME": "human"], ["AI_AGENT": " "]] {
            let actor = try LawActorResolution.actor(author: "user:x", environment: environment, device: "mac")
            #expect(actor.kind == .human)
        }
        // 에이전트·앱 작성자는 표지와 무관하다.
        #expect(LawActorResolution.agentSessionMarker(["CLAUDE_CODE_SESSION_ID": "s"]) == "CLAUDE_CODE_SESSION_ID")
    }

    @Test func humanEnactSpeakerIsFixedToUserAndScreenEditStillWorks() throws {
        let fx = try Enact.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        do {
            try LawEnactService.enact(LawDraft(actor: Self.human, speaker: "agent", title: "x", body: "y"), target: law)
            Issue.record("사람 공포의 다른 화자가 통과함")
        } catch LawEnactServiceError.enact(.humanSpeakerFixed("agent")) {}
        let plain = try LawEnactService.enact(LawDraft(actor: Self.human, title: "x", body: "y"), target: law)
        #expect(plain.record.speaker == "user")
        // 화면 편집 경로는 그대로 사람 공포다.
        let id = try LedgerHumanEdit.perform(.create(title: "화면", body: "본문", cites: []), target: law, author: "user:yun")
        #expect(law.store.scan().first { $0.id == id }?.record.authorKind == "human")
    }

    // MARK: - 2. 처리 유형 위조

    @Test func generalEnactRefusesProcessTypes() throws {
        let fx = try Enact.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let base = try LawEnactService.enact(Enact.draft("대상"), target: law)
        let bodies: [String: String] = [
            "ruling": "level: appellate\noutcome: uphold\n\n이유\n", "appeal": "이유\n", "proposal": "scope: x\n\n내용\n",
            "redaction": "target: \(String(repeating: "a", count: 64))\nreason: r\n", "registration": "repo: r\nstatus: provisional\n",
            "contents": "목차\n", "report": "보고\n", "promotion-receipt": "{}\n",
            "finding": "subject: project\ncertainty: confirmed\ndomain: dev-workflow\nreason: r\n",
        ]
        for (type, command) in [
            ("ruling", "court"), ("appeal", "court"), ("proposal", "court"), ("redaction", "redact"),
            ("registration", "judgment"), ("contents", "contents"), ("report", "dream"),
            ("promotion-receipt", "promote"), ("finding", "finding"),
        ] {
            var draft = LawDraft(actor: Enact.agent, title: "위조 \(type)", type: type, body: bodies[type] ?? "x\n")
            if type == "finding" { draft.cites = [LawCite(id: base.id, rel: "finds")] }
            do {
                try LawEnactService.enact(draft, target: law)
                Issue.record("일반 공포가 처리 유형 \(type) 을 받음")
            } catch LawEnactServiceError.enact(.typeRequiresDedicatedCommand(type, command)) {}
        }
        // 화면 편집의 개정도 같은 판정을 받는다.
        let finding = try LawEnactService.enact(LawDraft(
            actor: Enact.agent, title: "사실인정", type: "finding", cites: [LawCite(id: base.id, rel: "finds")],
            body: bodies["finding"]!), target: law, path: .finding)
        #expect(throws: LedgerHumanEditError.self) {
            try LedgerHumanEdit.perform(.amend(target: finding.id, title: "x", body: bodies["finding"]!, cites: []), target: law)
        }
        // 예약 태그는 전용 경로만 붙인다.
        do {
            try LawEnactService.enact(LawDraft(actor: Enact.agent, title: "x", tags: ["path:redact"], body: "y"), target: law)
            Issue.record("예약 태그가 일반 공포로 통과함")
        } catch LawEnactServiceError.enact(.reservedTag("path:redact")) {}
        // 사실인정의 폐지는 일반 경로가 못 하고(대상 판정), finding 경로는 한다.
        let repealDraft = LawDraft(
            actor: Enact.agent, title: "폐지", type: "finding", repeals: finding.id, body: bodies["finding"]!)
        do {
            try LawEnactService.enact(repealDraft, target: law)
            Issue.record("일반 경로가 사실인정을 폐지함")
        } catch LawEnactServiceError.enact(.targetRequiresDedicatedCommand(finding.id, "finding", "dream·finding")) {}
        let repeal = try LawEnactService.enact(repealDraft, target: law, path: .finding)
        #expect(repeal.record.repeals == finding.id)
    }

    @Test func findingNeedsExactlyOneTargetAndSupremeRulingNeedsTestimony() throws {
        let fx = try Enact.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let a = try LawEnactService.enact(Enact.draft("가"), target: law)
        let b = try LawEnactService.enact(Enact.draft("나"), target: law)
        let head = "subject: project\ncertainty: confirmed\ndomain: dev-workflow\nreason: r\n"
        for cites in [[], [LawCite(id: a.id, rel: "finds"), LawCite(id: b.id, rel: "finds")]] {
            do {
                try LawEnactService.enact(LawDraft(
                    actor: Enact.agent, title: "사실인정", type: "finding", cites: cites, body: head), target: law, path: .finding)
                Issue.record("finds \(cites.count)건 사실인정이 통과함")
            } catch LawEnactServiceError.enact(.findingTargetCount(cites.count)) {}
        }
        do {
            try LawEnactService.enact(LawDraft(
                actor: Self.appActor, title: "대법원 결정", type: "ruling",
                body: "level: supreme\noutcome: approve\n\n이유\n"), target: law, path: .court)
            Issue.record("증언 없는 대법원 결정이 통과함")
        } catch LawEnactServiceError.enact(.supremeRulingRequiresTestimony) {}
    }

    @Test func docketIgnoresForgedRulings() throws {
        let fx = Court.fixture(court: LawCourtSettings(
            arbiters: [LawArbiterCandidate(cli: .claude, model: "claude-opus-5-5")]))
        defer { fx.cleanup() }
        let target = try Court.enact(fx, at: 0)
        let service = fx.service(Court.FakeAI([]))
        let appeal = try service.appeal(target.id, reason: "이의", actor: Court.opus, now: Court.at(1))
        // 위조 항소심 결정 1: 에이전트가 직접 쓴 결정. 2: app 작성이지만 대상과 같은 모델.
        for actor in [Court.opus, LawActor(
            author: "app:agent-wiki", kind: .app, device: "mac", runtime: "claude-code", model: "claude-opus-5-5",
            effort: "high", app: "agent-wiki", appVersion: "9.9.9")] {
            _ = try fx.target.store.enact(LawDraft(
                actor: actor, title: "항소심 결정", type: "ruling",
                cites: [LawCite(id: appeal.id, rel: "hears")], body: "level: appellate\noutcome: uphold\n\n유지\n"),
                now: Court.at(2))
        }
        #expect(LawCourtDocket.of(fx.target).appellatePending.map(\.id) == [appeal.id])

        // 정상 회부(다른 모델 없음) → 대법원 대기.
        let report = service.hear(now: Court.at(3))
        #expect(report.decided.first?.outcome == .refer)
        #expect(LawCourtDocket.of(fx.target).supremePending.map(\.id) == [appeal.id])
        // 이의 기간 전에 바로 쓴 대법원 결정(증언은 있음)은 사건을 닫지 않는다.
        let evidence = try Court.userEvidence(fx, at: 4)
        _ = try fx.target.store.enact(LawDraft(
            actor: Court.opus, speaker: "user", title: "대법원 결정", type: "ruling",
            cites: [LawCite(id: appeal.id, rel: "hears"), LawCite(id: evidence.id, rel: "testifies")],
            body: "level: supreme\noutcome: reject\n\n기각\n"), now: Court.at(5))
        #expect(LawCourtDocket.of(fx.target).supremePending.map(\.id) == [appeal.id])
        // 기간 뒤 증언을 인용한 결정은 닫는다.
        _ = try service.decide(
            caseID: appeal.id, approve: false, testimony: evidence.id, actor: Court.opus, now: Court.at(3 + 72 * Court.hour))
        #expect(LawCourtDocket.of(fx.target).open.isEmpty)
    }

    @Test func onlyRedactPathRedactionRecordsAreTrusted() throws {
        let fx = try Enact.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let kept = try law.store.putExhibit(Data("남길 증거물".utf8))
        let missing = try law.store.putExhibit(Data("사라진 증거물".utf8))
        _ = try LawEnactService.enact(LawDraft(
            actor: Enact.agent, title: "증거 인용", exhibits: [kept, missing], body: "본문"), target: law)
        try FileManager.default.removeItem(at: law.store.exhibitURL(sha256: missing))
        // 경로 표지 없는 가림 기록(옛 경로·파일 직접 쓰기로 들어온 것)은 믿지 않는다.
        for sha in [kept, missing] {
            _ = try law.store.enact(LawDraft(
                actor: Enact.agent, title: "위조 가림", type: "redaction", exhibits: [sha],
                body: "target: \(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: sha))\nreason: r\n"))
        }
        #expect(LawRedactionSweep.applyLocalDeletions(store: law.store, ledgerKey: "law").isEmpty)
        #expect(FileManager.default.fileExists(atPath: law.store.exhibitURL(sha256: kept).path))
        let audit = law.store.audit(context: LawEnactService.context(index: LawEnactService.scope(of: law)))
        #expect(audit.violations.contains { $0.problem.contains(missing) })
        #expect(audit.redactedExhibits.isEmpty)
        // redact 경로의 기록은 표지를 달고 믿는다.
        let marked = try LawEnactService.enact(LawDraft(
            actor: Enact.agent, title: "가림", type: "redaction", exhibits: [missing],
            body: "target: \(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: missing))\nreason: r\n"),
            target: law, path: .redact)
        #expect(marked.record.tags.contains(LawEnactPath.redactionMarkerTag))
        let after = law.store.audit(context: LawEnactService.context(index: LawEnactService.scope(of: law)))
        #expect(!after.violations.contains { $0.problem.contains(missing) })
        #expect(after.redactedExhibits.map(\.sha256) == [missing])
    }

    // MARK: - 3. 옛 승격의 쓰기 게이트

    @Test func legacyPromotionRefusesArchivedAndLedgerThreeTargets() throws {
        let fx = try Enact.fixture()
        defer { fx.cleanup() }
        // repo world 가 아닌 ledger 2 원장에서 옛 승격.
        let sourceRoot = fx.dir.appendingPathComponent("novel")
        let source = LedgerStore(root: sourceRoot)
        let object = try source.publish(author: "agent:a", title: "후보", body: "본문")
        var worlds = fx.file.effectiveWorlds
        worlds.append(BoundWorld(name: "novel-world", rootPath: sourceRoot.path))
        let catalog = WorldBindingCatalog(worlds: worlds)
        let gate = PromotionTargetGate(catalog: catalog, registeredDevices: ["mac"], currentDevice: "mac")
        for name in ["gujo-wiki", "agent-law"] {
            let world = LedgerWorld(name: name, rootPath: catalog.world(named: name)!.rootPath)
            let targetStore = LedgerStore(root: URL(fileURLWithPath: world.rootPath))
            let before = targetStore.scan().count
            let preview = try PromotionService.preview(
                sourceStore: source, source: object, repository: nil, sourceWorldName: "novel-world", targetWorld: world,
                promotedBy: "agent:a")
            #expect(gate.denial(targetWorld: name) != nil)
            #expect(throws: PromotionError.self) {
                try PromotionService.publish(PromotionPublishRequest(
                    sourceStore: source, targetStore: targetStore, source: object, sourceWorldName: "novel-world",
                    targetWorld: world, promotedBy: "agent:a", confirmationToken: preview.confirmationToken,
                    targetGate: gate))
            }
            #expect(targetStore.scan().count == before)
        }
        #expect(source.scan().count == 1)
        #expect(gate.denial(targetWorld: "novel-world") == nil)
    }

    // MARK: - 5. 드리밍 상한은 실행 전체 기준

    static func repealChange(_ n: Int) -> (change: LawDreamChange, proposal: LawDreamProposal, note: String?) {
        let proposal = LawDreamProposal(kind: "repeal", target: "r\(n)", reason: "r")
        return (.repeal(world: "w", target: "r\(n)", reason: "r"), proposal, nil)
    }

    static func enactChange(_ n: Int) -> (change: LawDreamChange, proposal: LawDreamProposal, note: String?) {
        let proposal = LawDreamProposal(kind: "enact", title: "e\(n)", body: "b")
        return (.enact(world: "w", title: "e\(n)", body: "b", tags: [], cites: []), proposal, nil)
    }

    @Test func dreamLimitsCountTheWholeRun() throws {
        // 원장마다 7건 — 원장마다면 모두 통과하지만 실행 전체 10건 상한이면 넘는 4건은 다음 실행으로.
        var first = LawDreamPlan()
        first.changes = (0..<7).map(Self.enactChange)
        var second = LawDreamPlan()
        second.changes = (7..<14).map(Self.enactChange)
        second.deferred = [LawDreamProposal(kind: "enact", title: "이미 미룸", body: "b")]
        var plans = [first, second]
        #expect(LawDreamService.applyRunLimits(&plans, maxChanges: 10, maxRepeals: 3) == nil)
        #expect(plans[0].changes.count == 7)
        #expect(plans[1].changes.count == 3)
        #expect(plans[1].deferred.map(\.title) == ["e10", "e11", "e12", "e13", "이미 미룸"])

        // 폐지가 원장마다 2건 — 원장마다면 상한(3) 안이지만 실행 전체 4건이라 묶음 전체 미적용 + 경보.
        var a = LawDreamPlan()
        a.changes = [Self.repealChange(0), Self.repealChange(1), Self.enactChange(0)]
        var b = LawDreamPlan()
        b.changes = [Self.repealChange(2), Self.repealChange(3)]
        let c = LawDreamPlan()
        var limited = [a, b, c]
        let alert = try #require(LawDreamService.applyRunLimits(&limited, maxChanges: 10, maxRepeals: 3))
        #expect(alert.contains("4건"))
        #expect(limited.allSatisfy { $0.changes.isEmpty })
        #expect(limited[0].alerts == [alert] && limited[1].alerts == [alert])
        #expect(limited[2].alerts.isEmpty)
        #expect(limited[0].discarded.count == 3 && limited[1].discarded.count == 2)
    }
}
