import Foundation
import Testing
@testable import RoomKit

// D4 (2026-09-07) — heartbeat·상의형 방·stall 재계획 이벤트의 상태 투영.
// 원칙: 새 이벤트는 생존·진행 증거만 기록하고 phase 를 건드리지 않는다.

@Suite("RoomStatusProjection — D4 이벤트")
struct RoomStatusProjectionD4Tests {
    let ts = "2026-09-07T09:00:00.000Z"

    @Test("heartbeat — lastHeartbeatAt·attempt 기록, phase 불변")
    func heartbeatUpdatesSurvivalEvidenceOnly() {
        let events = [
            RoomEvent.created(by: "system", at: ts),
            RoomEvent.assembled(by: "system", at: ts),
            RoomEvent.occupied(agent: "agent:claude@mac", sessionID: "s1", at: ts),
            RoomEvent.heartbeat(sessionID: "s1", attempt: 1, by: "daemon", at: ts),
        ]
        let status = RoomStatusProjection.reduce(events: events)
        #expect(status.phase == .occupied)
        #expect(status.heartbeatAttempt == 1)
        #expect(status.lastHeartbeatAt != nil)
    }

    @Test("상의 라운드 — round 기록, concluded outcome 기록")
    func deliberationRoundAndOutcomeProjected() {
        let events = [
            RoomEvent.created(by: "system", at: ts),
            RoomEvent.deliberationRoundStarted(round: 1, participants: ["a", "b"], at: ts),
            RoomEvent.deliberationRoundEnded(round: 1, outputHash: "h1", agreeCount: 1, disagreeCount: 1, at: ts),
            RoomEvent.deliberationRoundStarted(round: 2, participants: ["a", "b"], at: ts),
            RoomEvent.deliberationRoundEnded(round: 2, outputHash: "h1", agreeCount: 2, disagreeCount: 0, at: ts),
            RoomEvent.deliberationConcluded(outcome: "staleOutput", rounds: 2, outputHash: "h1", at: ts),
        ]
        let status = RoomStatusProjection.reduce(events: events)
        #expect(status.deliberationRound == 2)
        #expect(status.deliberationOutcome == "staleOutput")
    }

    @Test("replanRaised — 누적 카운트, phase 불변")
    func replanCountAccumulates() {
        let events = [
            RoomEvent.created(by: "system", at: ts),
            RoomEvent.occupied(agent: "agent:claude@mac", sessionID: "s1", at: ts),
            RoomEvent.replanRaised(blockedCount: 4, fingerprint: "f1", suggestions: ["a"], at: ts),
            RoomEvent.replanRaised(blockedCount: 6, fingerprint: "f1", suggestions: ["b"], at: ts),
        ]
        let status = RoomStatusProjection.reduce(events: events)
        #expect(status.replanCount == 2)
        #expect(status.phase == .occupied)
    }

    @Test("구 저장본 하위호환 — 새 필드 없는 JSON 도 디코딩된다")
    func legacyJSONDecodesWithoutNewFields() throws {
        let legacy = """
        {"phase":"occupied"}
        """
        let status = try JSONDecoder().decode(RoomStatus.self, from: Data(legacy.utf8))
        #expect(status.phase == .occupied)
        #expect(status.replanCount == nil)
        #expect(status.lastHeartbeatAt == nil)
    }
}
