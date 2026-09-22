import Foundation

public struct RoomEvent: Codable, Sendable, Equatable {
    public var seq: Int
    public var at: String
    public var kind: String
    public var originActor: String
    public var payload: [String: JSONValue]

    public var actor: String {
        get { originActor }
        set { originActor = newValue }
    }

    enum CodingKeys: String, CodingKey {
        case seq
        case at
        case kind
        case originActor = "actor"
        case payload
    }

    public init(
        seq: Int = 0,
        at: String = Self.currentTimestamp(),
        kind: String,
        by: String = "daemon",
        payload: [String: JSONValue] = [:]
    ) {
        self.seq = seq
        self.at = at
        self.kind = kind
        self.originActor = by
        self.payload = payload
    }

    public static func currentTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    public var parsedDate: Date? {
        let formatterWithMillis = ISO8601DateFormatter()
        formatterWithMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatterWithMillis.date(from: at) {
            return d
        }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: at)
    }
}

public enum RoomEventKind {
    public static let created = "created"
    public static let assembled = "assembled"
    public static let sessionStarted = "sessionStarted"
    public static let occupied = "occupied"
    public static let verdictRan = "verdictRan"
    public static let handoffNoted = "handoffNoted"
    public static let budgetSampled = "budgetSampled"
    public static let sessionExited = "sessionExited"
    public static let vacated = "vacated"
    public static let closed = "closed"
    public static let approved = "approved"
    public static let rejected = "rejected"
    public static let gated = "gated"
    public static let escalated = "escalated"
    public static let blocked = "blocked"
    public static let branchLinked = "branchLinked"
    public static let mrLinked = "mrLinked"
    public static let mrMerged = "mrMerged"
    public static let bottleSwapped = "bottleSwapped"
    public static let humanCardRaised = "humanCardRaised"
    // MARK: D4 (2026-09-07) — heartbeat·상의형 방·stall 재계획
    public static let heartbeat = "heartbeat"
    public static let deliberationRoundStarted = "deliberationRoundStarted"
    public static let deliberationRoundEnded = "deliberationRoundEnded"
    public static let deliberationConcluded = "deliberationConcluded"
    public static let replanRaised = "replanRaised"
}

extension RoomEvent {
    public static func created(by: String = "system", at: String = currentTimestamp()) -> RoomEvent {
        RoomEvent(at: at, kind: RoomEventKind.created, by: by)
    }

    public static func assembled(by: String = "system", at: String = currentTimestamp()) -> RoomEvent {
        RoomEvent(at: at, kind: RoomEventKind.assembled, by: by)
    }

    public static func sessionStarted(
        sessionID: String,
        pid: Int,
        tool: String,
        by: String = "daemon",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.sessionStarted,
            by: by,
            payload: [
                "sessionID": .string(sessionID),
                "pid": .int(pid),
                "tool": .string(tool),
            ]
        )
    }

    public static func occupied(
        agent: String,
        sessionID: String,
        by: String = "system",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.occupied,
            by: by,
            payload: [
                "agent": .string(agent),
                "sessionID": .string(sessionID),
            ]
        )
    }

    public static func verdictRan(
        exit: Int,
        summary: String,
        by: String = "daemon",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.verdictRan,
            by: by,
            payload: [
                "exit": .int(exit),
                "summary": .string(summary),
            ]
        )
    }

    public static func handoffNoted(
        noteID: String,
        by: String = "agent",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.handoffNoted,
            by: by,
            payload: [
                "noteID": .string(noteID),
            ]
        )
    }

    public static func budgetSampled(
        used: Int,
        limit: Int?,
        estimated: Bool,
        by: String = "daemon",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        var payload: [String: JSONValue] = [
            "used": .int(used),
            "estimated": .bool(estimated),
        ]
        if let limit {
            payload["limit"] = .int(limit)
        }
        return RoomEvent(
            at: at,
            kind: RoomEventKind.budgetSampled,
            by: by,
            payload: payload
        )
    }

    public static func sessionExited(
        code: Int,
        sessionID: String? = nil,
        by: String = "daemon",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        var payload: [String: JSONValue] = [
            "code": .int(code),
        ]
        if let sessionID {
            payload["sessionID"] = .string(sessionID)
        }
        return RoomEvent(
            at: at,
            kind: RoomEventKind.sessionExited,
            by: by,
            payload: payload
        )
    }

    public static func vacated(
        reason: String,
        by: String = "system",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.vacated,
            by: by,
            payload: [
                "reason": .string(reason),
            ]
        )
    }

    public static func closed(
        sessionID: String? = nil,
        by: String = "daemon",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        var payload: [String: JSONValue] = [:]
        if let sessionID {
            payload["sessionID"] = .string(sessionID)
        }
        return RoomEvent(
            at: at,
            kind: RoomEventKind.closed,
            by: by,
            payload: payload
        )
    }

    // MARK: 판정·승인 이벤트 팩토리 (L5 원장 단일화)

    public static func approved(
        by actorID: String,
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.approved,
            by: actorID
        )
    }

    public static func rejected(
        by actorID: String,
        reason: String,
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.rejected,
            by: actorID,
            payload: [
                "reason": .string(reason),
            ]
        )
    }

    public static func gated(
        by actorID: String = "tick",
        reason: String = "",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.gated,
            by: actorID,
            payload: reason.isEmpty ? [:] : [
                "reason": .string(reason),
            ]
        )
    }

    public static func escalated(
        by actorID: String = "tick",
        blockedCount: Int,
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.escalated,
            by: actorID,
            payload: [
                "blockedCount": .int(blockedCount),
            ]
        )
    }

    public static func blocked(
        by actorID: String = "tick",
        blockedCount: Int,
        reason: String = "",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        var payload: [String: JSONValue] = [
            "blockedCount": .int(blockedCount),
        ]
        if !reason.isEmpty {
            payload["reason"] = .string(reason)
        }
        return RoomEvent(
            at: at,
            kind: RoomEventKind.blocked,
            by: actorID,
            payload: payload
        )
    }

    // MARK: 완료 신호·조정 이벤트 팩토리

    public static func branchLinked(
        branch: String,
        by actorID: String = "system",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.branchLinked,
            by: actorID,
            payload: [
                "branch": .string(branch),
            ]
        )
    }

    public static func mrLinked(
        iid: Int,
        by actorID: String = "tick",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.mrLinked,
            by: actorID,
            payload: [
                "iid": .int(iid),
            ]
        )
    }

    public static func mrMerged(
        iid: Int,
        by actorID: String = "tick",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.mrMerged,
            by: actorID,
            payload: [
                "iid": .int(iid),
            ]
        )
    }

    public static func bottleSwappedEvent(
        bottleIndex: Int,
        by actorID: String = "tick",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.bottleSwapped,
            by: actorID,
            payload: [
                "bottleIndex": .int(bottleIndex),
            ]
        )
    }

    public static func humanCardRaised(
        reason: String,
        by actorID: String = "reconciler",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.humanCardRaised,
            by: actorID,
            payload: [
                "reason": .string(reason),
            ]
        )
    }

    // MARK: D4 — 결속 갱신·상의형 방·stall 재계획 (2026-09-07)

    /// Kubernetes Lease renewTime 판정 — `at` 필드 자체가 renewTime 이다.
    /// attempt 는 입주 차수(occupied 마다 +1). 발신 정본은 `placement heartbeat` CLI.
    public static func heartbeat(
        sessionID: String,
        attempt: Int,
        by actorID: String = "daemon",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.heartbeat,
            by: actorID,
            payload: [
                "sessionID": .string(sessionID),
                "attempt": .int(attempt),
            ]
        )
    }

    public static func deliberationRoundStarted(
        round: Int,
        participants: [String],
        by actorID: String = "tick",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.deliberationRoundStarted,
            by: actorID,
            payload: [
                "round": .int(round),
                "participants": .array(participants.map(JSONValue.string)),
            ]
        )
    }

    /// 참가자별 산출 원문은 방 workdir 파일로, 원장에는 정규화 해시만 남긴다.
    public static func deliberationRoundEnded(
        round: Int,
        outputHash: String,
        agreeCount: Int,
        disagreeCount: Int,
        by actorID: String = "tick",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.deliberationRoundEnded,
            by: actorID,
            payload: [
                "round": .int(round),
                "outputHash": .string(outputHash),
                "agreeCount": .int(agreeCount),
                "disagreeCount": .int(disagreeCount),
            ]
        )
    }

    /// 명시적 완료 신호 — outcome: consensus | staleOutput | maxRounds | unresolved.
    /// unresolved 는 humanCard 경로로, 나머지는 verdict 통과 경로로 간다.
    public static func deliberationConcluded(
        outcome: String,
        rounds: Int,
        outputHash: String?,
        by actorID: String = "tick",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        var payload: [String: JSONValue] = [
            "outcome": .string(outcome),
            "rounds": .int(rounds),
        ]
        if let outputHash {
            payload["outputHash"] = .string(outputHash)
        }
        return RoomEvent(
            at: at,
            kind: RoomEventKind.deliberationConcluded,
            by: actorID,
            payload: payload
        )
    }

    /// stall 재계획 초안 제출 — 초안은 지휘실 승인(gate) 대기다. 자동 적용·자동 스폰 없음.
    public static func replanRaised(
        blockedCount: Int,
        fingerprint: String,
        suggestions: [String],
        by actorID: String = "tick",
        at: String = currentTimestamp()
    ) -> RoomEvent {
        RoomEvent(
            at: at,
            kind: RoomEventKind.replanRaised,
            by: actorID,
            payload: [
                "blockedCount": .int(blockedCount),
                "fingerprint": .string(fingerprint),
                "suggestions": .array(suggestions.map(JSONValue.string)),
            ]
        )
    }
}
