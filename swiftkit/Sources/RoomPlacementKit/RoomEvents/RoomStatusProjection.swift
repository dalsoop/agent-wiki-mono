import Foundation

public enum RoomPhase: String, Codable, Sendable, Equatable, CaseIterable {
    case created
    case open
    case occupied
    case exited
    case closed
    case approved
    case rejected
    case gated
    case escalated
    case blocked
}

public struct RoomStatus: Codable, Sendable, Equatable {
    public var phase: RoomPhase
    public var lastActivity: Date?
    public var sessionID: String?
    public var exitCode: Int?
    public var occupant: String?
    /// D4 — 마지막 heartbeat(renewTime). 조정자가 unknown 프로브를 alive 로 보강할 때 쓴다.
    public var lastHeartbeatAt: Date?
    /// D4 — heartbeat payload 의 입주 차수.
    public var heartbeatAttempt: Int?
    /// D4 — 상의형 방의 현재 라운드(deliberationRoundStarted/Ended 기준).
    public var deliberationRound: Int?
    /// D4 — 상의형 방 종료 신호(deliberationConcluded 의 outcome).
    public var deliberationOutcome: String?
    /// D4 — stall 재계획 제출 횟수(replanRaised 누적). 1회 한정의 상태 증거.
    public var replanCount: Int?

    public init(
        phase: RoomPhase = .created,
        lastActivity: Date? = nil,
        sessionID: String? = nil,
        exitCode: Int? = nil,
        occupant: String? = nil,
        lastHeartbeatAt: Date? = nil,
        heartbeatAttempt: Int? = nil,
        deliberationRound: Int? = nil,
        deliberationOutcome: String? = nil,
        replanCount: Int? = nil
    ) {
        self.phase = phase
        self.lastActivity = lastActivity
        self.sessionID = sessionID
        self.exitCode = exitCode
        self.occupant = occupant
        self.lastHeartbeatAt = lastHeartbeatAt
        self.heartbeatAttempt = heartbeatAttempt
        self.deliberationRound = deliberationRound
        self.deliberationOutcome = deliberationOutcome
        self.replanCount = replanCount
    }

    public var rawValue: String { phase.rawValue }

    public static let created = RoomStatus(phase: .created)
    public static let open = RoomStatus(phase: .open)
    public static let occupied = RoomStatus(phase: .occupied)
    public static let exited = RoomStatus(phase: .exited)
    public static let closed = RoomStatus(phase: .closed)

    // 레거시 호환 정적 상수
    public static let done = RoomStatus(phase: .closed)
    public static let planned = RoomStatus(phase: .created)
    public static let waiting = RoomStatus(phase: .open)
    public static let gated = RoomStatus(phase: .gated)
    public static let blocked = RoomStatus(phase: .blocked)
    public static let escalated = RoomStatus(phase: .escalated)
    public static let approved = RoomStatus(phase: .approved)
    public static let rejected = RoomStatus(phase: .rejected)

    public static let allCases: [RoomStatus] = [
        .occupied, .waiting, .planned, .done, .created, .open, .exited, .closed, .gated, .blocked, .escalated, .approved, .rejected
    ]
}

/// 이벤트 스트림을 누적 재생하여 방의 현재 상태를 계산하는 순수 함수.
public enum RoomStatusProjection {
    public static func reduce(events: [RoomEvent], now: Date = Date()) -> RoomStatus {
        let sorted = events.sorted { $0.seq < $1.seq }
        var status = RoomStatus(phase: .created)
        for event in sorted {
            apply(event: event, to: &status)
        }
        return status
    }

    private static func apply(event: RoomEvent, to status: inout RoomStatus) {
        if let date = event.parsedDate {
            status.lastActivity = date
        }
        switch event.kind {
        case RoomEventKind.created:
            status.phase = .created
        case RoomEventKind.assembled:
            status.phase = .open
        case RoomEventKind.sessionStarted:
            applySessionStarted(event: event, status: &status)
        case RoomEventKind.occupied:
            applyOccupied(event: event, status: &status)
        case RoomEventKind.verdictRan:
            if let exit = event.payload["exit"]?.int { status.exitCode = exit }
        case RoomEventKind.handoffNoted, RoomEventKind.budgetSampled,
             RoomEventKind.branchLinked, RoomEventKind.mrLinked,
             RoomEventKind.bottleSwapped, RoomEventKind.humanCardRaised:
            break
        case RoomEventKind.heartbeat:
            // 생존 증거만 기록 — phase 는 건드리지 않는다 (원칙 1: 상태는 fold 결과).
            status.lastHeartbeatAt = event.parsedDate
            status.heartbeatAttempt = event.payload["attempt"]?.int
        case RoomEventKind.deliberationRoundStarted, RoomEventKind.deliberationRoundEnded:
            if let round = event.payload["round"]?.int { status.deliberationRound = round }
        case RoomEventKind.deliberationConcluded:
            status.deliberationOutcome = event.payload["outcome"]?.string
        case RoomEventKind.replanRaised:
            status.replanCount = (status.replanCount ?? 0) + 1
        case RoomEventKind.mrMerged:
            status.phase = .closed
        case RoomEventKind.sessionExited:
            if let sid = event.payload["sessionID"]?.string, sid.hasPrefix("exec-") {
                // 단발성 태스크 종료는 방 전체를 exited 로 전이시키지 않음
                break
            }
            status.phase = .exited
            if let code = event.payload["code"]?.int { status.exitCode = code }
        case RoomEventKind.vacated:
            applyVacated(status: &status)
        case RoomEventKind.closed:
            status.phase = .closed
        case RoomEventKind.approved, RoomEventKind.rejected,
             RoomEventKind.gated, RoomEventKind.escalated, RoomEventKind.blocked:
            applyJudgment(kind: event.kind, status: &status)
        default:
            break
        }
    }

    private static func applySessionStarted(event: RoomEvent, status: inout RoomStatus) {
        if status.phase == .created || status.phase == .open {
            status.phase = .open
            if let sid = event.payload["sessionID"]?.string { status.sessionID = sid }
        }
    }

    private static func applyOccupied(event: RoomEvent, status: inout RoomStatus) {
        status.phase = .occupied
        if let agent = event.payload["agent"]?.string { status.occupant = agent }
        if let sid = event.payload["sessionID"]?.string { status.sessionID = sid }
    }

    private static func applyVacated(status: inout RoomStatus) {
        // 종결(exited·closed) 뒤의 vacated 는 자리만 비운다 — 방을 다시 열지 않는다.
        // 실측(2026-09-06): close 가 데몬 closed 뒤에 cli vacated 를 남겨 투영이 open 으로 되돌아갔다.
        if status.phase != .exited && status.phase != .closed {
            status.phase = .open
        }
        status.occupant = nil
    }

    private static func applyJudgment(kind: String, status: inout RoomStatus) {
        switch kind {
        case RoomEventKind.approved: status.phase = .approved
        case RoomEventKind.rejected: status.phase = .rejected
        case RoomEventKind.gated: status.phase = .gated
        case RoomEventKind.escalated: status.phase = .escalated
        case RoomEventKind.blocked: status.phase = .blocked
        default: break
        }
    }
}
