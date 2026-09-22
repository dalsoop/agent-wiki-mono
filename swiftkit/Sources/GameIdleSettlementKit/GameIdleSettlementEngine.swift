import Foundation

/// 정산 1회의 결과 요약. 게임별 보상 내역은 `Payload` 로 받는다.
///
/// gaya 처럼 `Int` 하나여도 되고(`GameIdleSettlementReport<Int>`), isekai 처럼 자원 델타
/// 구조체여도 된다. 척추는 시간 계산만 책임지고 보상 계산에는 관여하지 않는다.
public struct GameIdleSettlementReport<Payload>: Sendable where Payload: Sendable {
    public let elapsed: GameIdleElapsed
    /// 게임이 `credit` 에서 만든 보상 내역.
    public let payload: Payload
    /// 정산을 실행한 시각.
    public let occurredAt: Date
    /// 정산 후 다음 기준선.
    public let baselineAfterSettlement: Date
    /// 정산 후 단조 누적 플레이 초.
    public let monotonicPlayedSeconds: Int

    public init(
        elapsed: GameIdleElapsed,
        payload: Payload,
        occurredAt: Date,
        baselineAfterSettlement: Date,
        monotonicPlayedSeconds: Int
    ) {
        self.elapsed = elapsed
        self.payload = payload
        self.occurredAt = occurredAt
        self.baselineAfterSettlement = baselineAfterSettlement
        self.monotonicPlayedSeconds = monotonicPlayedSeconds
    }

    /// 반영된 것이 없으면 복귀 화면을 띄우지 않는다.
    public var isEmpty: Bool { elapsed.isEmpty }
    public var settledSeconds: Int { elapsed.settledSeconds }
    /// "n일 n시간 동안 …" 표시를 위한 분해.
    public var duration: GameIdleDuration { elapsed.duration }
}

extension GameIdleSettlementReport: Equatable where Payload: Equatable {}
extension GameIdleSettlementReport: Hashable where Payload: Hashable {}
extension GameIdleSettlementReport: Codable where Payload: Codable {}

/// 원장 + 정책을 묶어 정산 1회를 실행하는 엔진.
public struct GameIdleSettlementEngine<Payload>: Sendable where Payload: Sendable {
    public let policy: GameIdleElapsedPolicy

    public init(policy: GameIdleElapsedPolicy = .standardV1) {
        self.policy = policy
    }

    /// 경과를 계산해 `credit` 에 넘기고, 성공했을 때만 원장을 전진시킨다.
    ///
    /// `credit` 은 정산해야 할 초를 받아 게임 상태를 갱신하고 보상 내역을 돌려준다.
    /// 0초여도 호출되므로(요약 페이로드가 항상 있어야 한다) 게임 쪽에서 0 을 no-op 로 다뤄야 한다.
    /// `credit` 이 던지면 원장은 **손대지 않는다** — 보상 없이 시간만 소비되는 사고를 막는다.
    @discardableResult
    public func settle(
        ledger: inout GameIdleSettlementLedger,
        now: Date,
        credit: (Int) throws -> Payload
    ) rethrows -> GameIdleSettlementReport<Payload> {
        let preview = ledger.preview(now: now, policy: policy)
        let payload = try credit(preview.settledSeconds)
        let outcome = ledger.consume(now: now, policy: policy)
        return GameIdleSettlementReport(
            elapsed: outcome,
            payload: payload,
            occurredAt: now,
            baselineAfterSettlement: ledger.lastSettledAt,
            monotonicPlayedSeconds: ledger.monotonicPlayedSeconds
        )
    }

    /// 주입된 벽시계로 정산한다. 프로덕션 경로는 항상 이 쪽을 쓴다(`Date()` 직접 호출 금지).
    @discardableResult
    public func settle(
        ledger: inout GameIdleSettlementLedger,
        clock: some GameIdleWallClock,
        credit: (Int) throws -> Payload
    ) rethrows -> GameIdleSettlementReport<Payload> {
        try settle(ledger: &ledger, now: clock.now(), credit: credit)
    }
}
