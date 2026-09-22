import Foundation

/// 방치형 정산의 원장(元帳). 저장에 그대로 실어 다음 실행으로 넘긴다.
///
/// 계약 두 가지가 이 타입의 존재 이유다.
///
/// 1. **재정산 방지** — 정산에 소비한 구간만큼 `lastSettledAt` 을 앞으로 민다. 저장이
///    실패하거나 앱이 죽어도 다음 실행이 같은 구간을 다시 지급하지 않는다.
///    isekai 의 "정산 직후 `lastSavedAt` 갱신" 을 값 타입 계약으로 일반화한 것이다.
/// 2. **단조 누적 시간** — `monotonicPlayedSeconds` 는 시계를 뒤로 돌려도 절대 줄지 않는다.
///    도메인 상태에 끼워 넣지 않고 원장이 들고 있어 척추가 관리한다.
public struct GameIdleSettlementLedger: Codable, Hashable, Sendable {
    /// 다음 정산의 기준 시각.
    public private(set) var lastSettledAt: Date
    /// 시계 조작에 영향을 받지 않는 누적 플레이 초.
    public private(set) var monotonicPlayedSeconds: Int
    /// 정산을 시도한 횟수(빈 정산 포함). 진단·텔레메트리용.
    public private(set) var settlementCount: Int

    public init(
        lastSettledAt: Date,
        monotonicPlayedSeconds: Int = 0,
        settlementCount: Int = 0
    ) {
        self.lastSettledAt = GameIdleSeconds.isFinite(lastSettledAt)
            ? lastSettledAt
            : Date(timeIntervalSinceReferenceDate: 0)
        self.monotonicPlayedSeconds = max(0, monotonicPlayedSeconds)
        self.settlementCount = max(0, settlementCount)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lastSettledAt: try container.decode(Date.self, forKey: .lastSettledAt),
            monotonicPlayedSeconds: try container.decode(
                Int.self,
                forKey: .monotonicPlayedSeconds
            ),
            settlementCount: try container.decode(Int.self, forKey: .settlementCount)
        )
    }

    /// 원장을 바꾸지 않고 경과만 본다(복귀 화면 미리보기 등).
    public func preview(now: Date, policy: GameIdleElapsedPolicy) -> GameIdleElapsed {
        policy.elapsed(from: lastSettledAt, to: now)
    }

    /// 경과를 계산하고, 소비한 구간을 기준선에 반영한다.
    ///
    /// 같은 `now` 로 두 번 부르면 두 번째는 항상 빈 정산이 된다 — 이것이 이중 지급 방지의 핵심이다.
    @discardableResult
    public mutating func consume(
        now: Date,
        policy: GameIdleElapsedPolicy
    ) -> GameIdleElapsed {
        let outcome = preview(now: now, policy: policy)
        advanceBaseline(now: now, outcome: outcome, policy: policy)
        monotonicPlayedSeconds = GameIdleSeconds.addingSaturating(
            monotonicPlayedSeconds,
            outcome.settledSeconds
        )
        settlementCount = GameIdleSeconds.addingSaturating(settlementCount, 1)
        return outcome
    }

    /// 온라인(포그라운드) 진행분을 단조 누적에만 반영한다.
    public mutating func creditOnline(seconds: Int) {
        guard seconds > 0 else { return }
        monotonicPlayedSeconds = GameIdleSeconds.addingSaturating(
            monotonicPlayedSeconds,
            seconds
        )
    }

    /// 온라인 진행분을 누적하고 기준선을 현재로 당긴다(저장 시점에 부른다).
    public mutating func creditOnline(seconds: Int, now: Date) {
        creditOnline(seconds: seconds)
        advanceBaseline(to: now)
    }

    /// 기준선을 지정 시각으로 옮긴다.
    ///
    /// 저장 직후에 부른다. 시계가 뒤로 갔더라도 그대로 반영해, 다음 실행에서 거대한
    /// 가짜 경과가 생기지 않게 한다(isekai 와 같은 선택).
    public mutating func advanceBaseline(to now: Date) {
        guard GameIdleSeconds.isFinite(now) else { return }
        lastSettledAt = now
    }

    private mutating func advanceBaseline(
        now: Date,
        outcome: GameIdleElapsed,
        policy: GameIdleElapsedPolicy
    ) {
        guard GameIdleSeconds.isFinite(now) else { return }

        if outcome.clockWasInvalid || outcome.clockWentBackwards {
            // 시계가 망가졌거나 되돌아갔다 — 기준선을 현재로 리셋해 복구한다.
            lastSettledAt = now
            return
        }
        if outcome.wasBelowMinimum {
            if policy.belowMinimum == .discard { lastSettledAt = now }
            return
        }
        if outcome.wasCapped, policy.overflow == .discard {
            lastSettledAt = now
            return
        }
        // 소비한 초만큼만 민다. 1초 미만 잔여는 기준선에 남아 다음 정산에 합산된다.
        lastSettledAt = lastSettledAt.addingTimeInterval(Double(outcome.settledSeconds))
    }
}
