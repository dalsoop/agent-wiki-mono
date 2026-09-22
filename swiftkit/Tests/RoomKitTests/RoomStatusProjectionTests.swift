import XCTest
@testable import RoomKit

final class RoomStatusProjectionTests: XCTestCase {
    func testExecSessionSequenceDoesNotPrematurelyExitRoom() {
        var events: [RoomEvent] = [
            RoomEvent(seq: 1, kind: RoomEventKind.created),
            RoomEvent(seq: 2, kind: RoomEventKind.assembled),
            RoomEvent(seq: 3, kind: RoomEventKind.sessionStarted, payload: [
                "sessionID": .string("pty-1"), "pid": .int(100), "tool": .string("claude"),
            ]),
            RoomEvent(seq: 4, kind: RoomEventKind.occupied, payload: [
                "agent": .string("agent:claude@macbook"), "sessionID": .string("pty-1"),
            ]),
            RoomEvent(seq: 5, kind: RoomEventKind.sessionStarted, payload: [
                "sessionID": .string("exec-abc"), "pid": .int(0), "tool": .string("exec"),
            ]),
            RoomEvent(seq: 6, kind: RoomEventKind.sessionExited, payload: [
                "code": .int(0), "sessionID": .string("exec-abc"),
            ]),
        ]

        let statusAfterExec = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(statusAfterExec.phase, .occupied, "exec session exit must not prematurely exit room")
        XCTAssertEqual(statusAfterExec.sessionID, "pty-1", "exec sessionStarted must not overwrite PTY sessionID")
        XCTAssertEqual(statusAfterExec.occupant, "agent:claude@macbook")

        // 메인 PTY 세션이 종료되었을 때 비로소 exited 상태가 됨
        events.append(RoomEvent(seq: 7, kind: RoomEventKind.sessionExited, payload: [
            "code": .int(0), "sessionID": .string("pty-1"),
        ]))
        let statusAfterMain = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(statusAfterMain.phase, .exited)
        XCTAssertEqual(statusAfterMain.exitCode, 0)
    }

    func testSessionStartedDoesNotRegressFromOccupied() {
        let events: [RoomEvent] = [
            RoomEvent(seq: 1, kind: RoomEventKind.created),
            RoomEvent(seq: 2, kind: RoomEventKind.assembled),
            RoomEvent(seq: 3, kind: RoomEventKind.sessionStarted, payload: [
                "sessionID": .string("pty-1"), "pid": .int(100), "tool": .string("claude"),
            ]),
            RoomEvent(seq: 4, kind: RoomEventKind.occupied, payload: [
                "agent": .string("agent:claude@macbook"), "sessionID": .string("pty-1"),
            ]),
            RoomEvent(seq: 5, kind: RoomEventKind.sessionStarted, payload: [
                "sessionID": .string("exec-xyz"), "pid": .int(0), "tool": .string("exec"),
            ]),
        ]

        let status = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(status.phase, .occupied, "sessionStarted must not regress from occupied")
        XCTAssertEqual(status.sessionID, "pty-1")
    }

    func testVacateThenNewSessionStartedTransitionsToOpen() {
        let events: [RoomEvent] = [
            RoomEvent(seq: 1, kind: RoomEventKind.created),
            RoomEvent(seq: 2, kind: RoomEventKind.occupied, payload: [
                "agent": .string("a"), "sessionID": .string("s1"),
            ]),
            RoomEvent(seq: 3, kind: RoomEventKind.vacated, payload: ["reason": .string("done")]),
            RoomEvent(seq: 4, kind: RoomEventKind.sessionStarted, payload: [
                "sessionID": .string("s2"), "pid": .int(200), "tool": .string("claude"),
            ]),
        ]

        let status = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(status.phase, .open)
        XCTAssertEqual(status.sessionID, "s2")
        XCTAssertNil(status.occupant)
    }
}

private extension RoomEvent {
    init(seq: Int = 0, kind: String, payload: [String: JSONValue] = [:]) {
        self.init(seq: seq, at: RoomEvent.currentTimestamp(), kind: kind, payload: payload)
    }
}

/// 종결(exited·closed) 뒤의 vacated 는 방을 다시 열지 않는다 (2026-09-06 실측: close 가 데몬 closed 뒤 cli vacated 를 남김).
final class RoomStatusProjectionVacatedAfterClosedTests: XCTestCase {
    func testVacatedAfterClosedStaysClosed() {
        let events = [
            RoomEvent.created(),
            RoomEvent.sessionStarted(sessionID: "s1", pid: 1, tool: "terminal"),
            RoomEvent.occupied(agent: "agent:agy@macbook", sessionID: "s1"),
            RoomEvent.sessionExited(code: 0, sessionID: "s1"),
            RoomEvent.closed(sessionID: "s1"),
            RoomEvent.vacated(reason: "closed by cli", by: "cli"),
        ]
        let status = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(status.phase, .closed)
        XCTAssertNil(status.occupant)
    }

    func testVacatedWhileOccupiedReopens() {
        let events = [
            RoomEvent.created(),
            RoomEvent.occupied(agent: "agent:agy@macbook", sessionID: "s1"),
            RoomEvent.vacated(reason: "handoff", by: "cli"),
        ]
        XCTAssertEqual(RoomStatusProjection.reduce(events: events).phase, .open)
    }
}

// MARK: - 재생 테스트 (§7 — 이벤트 로그만으로 GUI 상태·tick 판정을 재구성)

final class RoomStatusProjectionReplayTests: XCTestCase {
    /// 정상 경로: spawn → occupied → verdictRan pass → approved → closed
    func testHappyPathReplay() {
        let events: [RoomEvent] = [
            RoomEvent(seq: 1, kind: RoomEventKind.created, by: "system"),
            RoomEvent(seq: 2, kind: RoomEventKind.assembled, by: "system"),
            RoomEvent(seq: 3, kind: RoomEventKind.sessionStarted, by: "daemon", payload: [
                "sessionID": .string("pty-1"), "pid": .int(100), "tool": .string("claude"),
            ]),
            RoomEvent(seq: 4, kind: RoomEventKind.occupied, by: "system", payload: [
                "agent": .string("agent:claude@macbook"), "sessionID": .string("pty-1"),
            ]),
            RoomEvent(seq: 5, kind: RoomEventKind.verdictRan, by: "tick", payload: [
                "exit": .int(0), "summary": .string("pass"),
            ]),
            RoomEvent(seq: 6, kind: RoomEventKind.approved, by: "tick"),
            RoomEvent(seq: 7, kind: RoomEventKind.sessionExited, by: "daemon", payload: [
                "code": .int(0), "sessionID": .string("pty-1"),
            ]),
            RoomEvent(seq: 8, kind: RoomEventKind.closed, by: "daemon"),
        ]

        let status = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(status.phase, .closed)
        XCTAssertEqual(status.exitCode, 0)
        XCTAssertEqual(status.occupant, "agent:claude@macbook")
    }

    /// 실패 경로: verdictRan fail → blocked → escalated
    func testFailBlockedEscalatedReplay() {
        let events: [RoomEvent] = [
            RoomEvent(seq: 1, kind: RoomEventKind.created, by: "system"),
            RoomEvent(seq: 2, kind: RoomEventKind.assembled, by: "system"),
            RoomEvent(seq: 3, kind: RoomEventKind.occupied, by: "system", payload: [
                "agent": .string("agent:agy@macbook"), "sessionID": .string("s1"),
            ]),
            RoomEvent(seq: 4, kind: RoomEventKind.verdictRan, by: "tick", payload: [
                "exit": .int(1), "summary": .string("test failed"),
            ]),
            RoomEvent(seq: 5, kind: RoomEventKind.blocked, by: "tick", payload: [
                "blockedCount": .int(1), "reason": .string("verify exit 1"),
            ]),
            RoomEvent(seq: 6, kind: RoomEventKind.occupied, by: "system", payload: [
                "agent": .string("agent:agy@macbook"), "sessionID": .string("s2"),
            ]),
            RoomEvent(seq: 7, kind: RoomEventKind.verdictRan, by: "tick", payload: [
                "exit": .int(1), "summary": .string("still failing"),
            ]),
            RoomEvent(seq: 8, kind: RoomEventKind.blocked, by: "tick", payload: [
                "blockedCount": .int(2), "reason": .string("verify exit 1"),
            ]),
            RoomEvent(seq: 9, kind: RoomEventKind.occupied, by: "system", payload: [
                "agent": .string("agent:agy@macbook"), "sessionID": .string("s3"),
            ]),
            RoomEvent(seq: 10, kind: RoomEventKind.verdictRan, by: "tick", payload: [
                "exit": .int(1), "summary": .string("still failing"),
            ]),
            RoomEvent(seq: 11, kind: RoomEventKind.escalated, by: "tick", payload: [
                "blockedCount": .int(3),
            ]),
        ]

        let status = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(status.phase, .escalated)
    }

    /// 사람 게이트: gated → approved → occupied → closed
    func testGatedThenApprovedReplay() {
        let events: [RoomEvent] = [
            RoomEvent(seq: 1, kind: RoomEventKind.created, by: "system"),
            RoomEvent(seq: 2, kind: RoomEventKind.assembled, by: "system"),
            RoomEvent(seq: 3, kind: RoomEventKind.gated, by: "tick", payload: [
                "reason": .string("humanGate"),
            ]),
            RoomEvent(seq: 4, kind: RoomEventKind.approved, by: "human"),
            RoomEvent(seq: 5, kind: RoomEventKind.occupied, by: "system", payload: [
                "agent": .string("agent:claude@macbook"), "sessionID": .string("s1"),
            ]),
            RoomEvent(seq: 6, kind: RoomEventKind.verdictRan, by: "daemon", payload: [
                "exit": .int(0), "summary": .string("ok"),
            ]),
            RoomEvent(seq: 7, kind: RoomEventKind.closed, by: "daemon"),
        ]

        let status = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(status.phase, .closed)
    }

    /// rejected 방은 rejected phase 에 남는다
    func testRejectedStaysRejected() {
        let events: [RoomEvent] = [
            RoomEvent(seq: 1, kind: RoomEventKind.created, by: "system"),
            RoomEvent(seq: 2, kind: RoomEventKind.rejected, by: "human", payload: [
                "reason": .string("범위 초과"),
            ]),
        ]

        let status = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(status.phase, .rejected)
    }

    /// 이벤트 순서가 뒤섞여도 seq 기준 정렬 뒤 재구성된다
    func testOutOfOrderEventsStillProjectCorrectly() {
        let events: [RoomEvent] = [
            RoomEvent(seq: 5, kind: RoomEventKind.closed, by: "daemon"),
            RoomEvent(seq: 1, kind: RoomEventKind.created, by: "system"),
            RoomEvent(seq: 3, kind: RoomEventKind.occupied, by: "system", payload: [
                "agent": .string("a"), "sessionID": .string("s"),
            ]),
            RoomEvent(seq: 2, kind: RoomEventKind.assembled, by: "system"),
            RoomEvent(seq: 4, kind: RoomEventKind.approved, by: "tick"),
        ]

        let status = RoomStatusProjection.reduce(events: events)
        XCTAssertEqual(status.phase, .closed)
    }
}

private extension RoomEvent {
    init(seq: Int, kind: String, by: String, payload: [String: JSONValue] = [:]) {
        self.init(seq: seq, at: RoomEvent.currentTimestamp(), kind: kind, by: by, payload: payload)
    }
}
