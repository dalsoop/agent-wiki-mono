import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

/// 원상회복의 전부 아니면 전무·원래 화자 유지 시험.
/// - 사람 작성자가 드리밍 묶음(에이전트·앱 작성 기록 포함)을 되돌리면 성공하고, 되살린 이전 판은 원래 화자를 가지며,
///   자동 드리밍이 정지한다.
/// - 묶음 중 하나라도 공포 검증기에 걸리면 아무것도 쓰지 않는다(파일 목록 불변).
/// - 일반 공포는 여전히 사람 작성자에게 다른 화자를 줄 수 없다(원상회복 표지는 `LawStore.restore` 만 만든다).
/// 근거: docs/business-rules.md "공포·개정·폐지·원상회복"·"드리밍"(안전장치). 실제 AI·R2·세션은 쓰지 않는다.
@Suite struct AgentLawRestoreAtomicityTests {
    typealias Dream = AgentLawDreamTests
    typealias FakeAI = AgentLawCourtTests.FakeAI
    typealias Repeal = AgentLawRepealTargetTests

    static func files(_ target: LawLedgerTarget) throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: target.root.path).sorted()
    }

    @Test func humanRestoresDreamBatchKeepingOriginalSpeakersAndPausesDreaming() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let dream = try AgentLawDreamRestoreTests.dreamBatch(fx)
        #expect(dream.old.record.speaker == "agent")
        let batchAuthors = Set(Dream.records(fx.person).filter { $0.record.batch == dream.batch }.map(\.record.authorKind))
        #expect(batchAuthors.contains("app"))

        fx.clock.advance(60)
        let restored = try LawEnactService.restore(batch: dream.batch, actor: Dream.human, target: fx.person, now: fx.now)
        #expect(restored.count == dream.applied.count)
        #expect(restored.allSatisfy { $0.record.authorKind == "human" })
        // 되살린 이전 판은 원래 화자(에이전트)를 그대로 가진다.
        let back = try #require(restored.first { $0.record.title == "옛 기록" })
        #expect(back.record.body == "옛 본문")
        #expect(back.record.speaker == dream.old.record.speaker)
        // 폐지 기록은 사람 자신의 행위라 user 다.
        #expect(restored.filter { $0.record.repeals != nil }.allSatisfy { $0.record.speaker == "user" })
        let view = LawLedgerView(records: Dream.records(fx.person))
        for id in dream.applied { #expect(!view.isInForce(id)) }

        let pause = fx.service(FakeAI([])).pause()
        #expect(Set(pause.unacknowledgedRestores) == Set(restored.map(\.id)))
        #expect(fx.service(FakeAI([])).status().paused)
    }

    @Test func validatorRefusalOnOneRecordWritesNothing() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        // 묶음: 새 기록 하나(먼저) + 사람이 쓴 user 화자 기록의 개정(나중). 에이전트가 되돌리면 두 번째 기록의 이전 판
        // (speaker: user, 증언 인용 없음)이 공포 검증기에서 거부된다(`speakerUserRequiresTestimony`) — 경로 판정은 통과한다.
        let userRecord = try Dream.enact(fx, fx.person, title: "사용자 기록", body: "사용자 말", actor: Dream.human)
        #expect(userRecord.record.speaker == "user")
        fx.clock.advance(1)
        let fresh = try Dream.enact(fx, fx.person, title: "새 기록", body: "새 본문", batch: "b-1")
        fx.clock.advance(1)
        let amended = try LawEnactService.enact(LawDraft(
            actor: Dream.agent, title: "사용자 기록", batch: "b-1", amends: userRecord.id, body: "고친 말"),
            target: fx.person, now: fx.now)
        let before = try Self.files(fx.person)

        fx.clock.advance(60)
        let error = Repeal.refusal {
            try LawEnactService.restore(batch: "b-1", actor: Dream.agent, target: fx.person, now: fx.now)
        }
        guard case .restoreRefused(let reasons)? = error else {
            Issue.record("검증기에 걸리는 기록이 든 묶음이 되돌려짐: \(String(describing: error))")
            return
        }
        #expect(reasons.count == 1)
        #expect(reasons.first?.hasPrefix(String(amended.id.prefix(8))) == true)
        #expect(try Self.files(fx.person) == before)
        let view = LawLedgerView(records: Dream.records(fx.person))
        #expect(view.isInForce(fresh.id) && view.isInForce(amended.id))
    }

    @Test func generalEnactStillFixesHumanSpeaker() throws {
        let fx = try Dream.fixture()
        defer { fx.cleanup() }
        let base = try Dream.enact(fx, fx.person, title: "에이전트 기록", body: "본문")
        // 공포 서비스·저장소 직접 공포 모두 사람 작성자에게 다른 화자를 주지 못한다(개정 모양이어도).
        #expect(Repeal.refusal {
            try LawEnactService.enact(LawDraft(
                actor: Dream.human, speaker: "agent", title: "에이전트 기록", amends: base.id, body: "본문"),
                target: fx.person, now: fx.now)
        } == .humanSpeakerFixed("agent"))
        #expect(throws: LawEnactError.humanSpeakerFixed("agent")) {
            try fx.person.store.enact(LawDraft(
                actor: Dream.human, speaker: "agent", title: "x", amends: base.id, body: "본문"), now: fx.now)
        }
    }
}
