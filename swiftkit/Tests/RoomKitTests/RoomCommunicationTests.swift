import Testing
import Foundation
@testable import RoomKit

@Suite("Room Communication & AI Safety Protocols Tests")
struct RoomCommunicationTests {

    @Test("RoomActor identity and serialization")
    func testRoomActor() {
        let user = RoomActor.user(name: "jeonghan")
        #expect(user.isUser)
        #expect(!user.isAgent)
        #expect(user.description == "user:jeonghan")

        let agent = RoomActor.agent(name: "codex", sessionID: "sess-999")
        #expect(!agent.isUser)
        #expect(agent.isAgent)
        let expectedAgentDesc = ["agent", "codex", "sess-999"].joined(separator: ":")
        #expect(agent.description == expectedAgentDesc)
    }

    @Test("RoomLeaseLock concurrency and human intervention")
    func testRoomLeaseLock() {
        var lock = RoomLeaseLock(
            roomID: "room-101",
            owner: .agent(name: "antigravity", sessionID: "sess-1"),
            leaseDurationSeconds: 10.0
        )

        #expect(lock.status == .active)
        #expect(lock.isValid)

        // 인간 직접 개입 시 일시 정지 전이
        lock.pauseByHuman()
        #expect(lock.status == .pausedByHuman)
        #expect(!lock.isValid) // 에이전트 작업은 일시 차단됨

        // 인간 작업 완료 후 에이전트 재개
        lock.resumeByHuman(additionalSeconds: 20.0)
        #expect(lock.status == .active)
        #expect(lock.isValid)

        // 작업 완료 및 락 반납
        lock.release()
        #expect(lock.status == .released)
        #expect(!lock.isValid)
    }

    @Test("AgentDebateProposal multi-agent consensus ratio")
    func testAgentDebateProposal() {
        var debate = AgentDebateProposal(
            roomID: "room-102-review",
            round: 1,
            proposal: "Cell 12개를 한 번에 치환하자",
            agrees: ["agent:codex@macbook"],
            disagrees: ["agent:claude@macbook"]
        )

        #expect(debate.consensusRatio == 0.5)
        #expect(!debate.isResolved())

        // 합의 도달 시뮬레이션
        debate.agrees.append("agent:gemini@macbook")
        debate.agrees.append("agent:antigravity@macbook")
        debate.disagrees.removeAll()

        #expect(debate.consensusRatio == 1.0)
        #expect(debate.isResolved())
    }

    @Test("HandoffDigest context transfer")
    func testHandoffDigest() {
        let digest = HandoffDigest(
            taskID: "task-001",
            fromAgent: "agent:planner@macbook",
            toAgent: "agent:worker@macbook",
            completedMilestones: ["설계 완료", "DB 스키마 격리"],
            pendingMilestones: ["API 엔드포인트 연동", "스모크 테스트"],
            sharedContextSummary: "Room 101 SQLite DB 생성 완료. 마이그레이션 v2 적용 필요."
        )

        #expect(digest.completedMilestones.count == 2)
        #expect(digest.pendingMilestones.count == 2)
        #expect(digest.fromAgent == "agent:planner@macbook")
        #expect(digest.toAgent == "agent:worker@macbook")
    }
}
