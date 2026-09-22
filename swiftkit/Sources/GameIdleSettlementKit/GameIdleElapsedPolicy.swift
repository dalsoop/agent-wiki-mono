import Foundation

/// 캡을 넘긴 초과분 처리 방식.
public enum GameIdleOverflowPolicy: UInt8, Codable, Hashable, Sendable {
    /// 캡까지만 지급하고 초과분은 버린다(기준선을 현재로 당긴다). isekai 7일 캡 동작.
    case discard = 1
    /// 캡까지만 지급하고 나머지는 기준선에 남겨 다음 정산으로 이월한다.
    case bank = 2
}

/// 최소 임계 미만 구간 처리 방식.
public enum GameIdleBelowMinimumPolicy: UInt8, Codable, Hashable, Sendable {
    /// 기준선을 그대로 둬서 다음 정산 때 합산한다(짧은 구간이 사라지지 않는다).
    case carryOver = 1
    /// 기준선을 현재로 당겨 짧은 구간을 버린다. gaya `elapsed > 60` 의 문자 그대로의 동작.
    case discard = 2
}

public enum GameIdleElapsedPolicyError: Error, Equatable, Sendable {
    case negativeMinimumSeconds(Int)
    case nonPositiveMaximumSeconds(Int)
    case minimumExceedsMaximum(minimum: Int, maximum: Int)
}

/// 오프라인 경과 시간 산출 정책.
///
/// 게임마다 다른 값(gaya: 최소 60초·캡 8시간, isekai: 최소 0·캡 7일)을 설정으로 받는다.
/// 계산 자체는 순수 함수라 시계·저장소 없이 단위 테스트할 수 있다.
public struct GameIdleElapsedPolicy: Codable, Hashable, Sendable {
    /// 이 값 미만의 경과는 정산하지 않는다(0 이면 임계 없음).
    public let minimumSeconds: Int
    /// 한 번에 정산할 수 있는 최대 초.
    public let maximumSeconds: Int
    public let overflow: GameIdleOverflowPolicy
    public let belowMinimum: GameIdleBelowMinimumPolicy

    public init(
        minimumSeconds: Int = 0,
        maximumSeconds: Int,
        overflow: GameIdleOverflowPolicy = .discard,
        belowMinimum: GameIdleBelowMinimumPolicy = .carryOver
    ) throws {
        guard minimumSeconds >= 0 else {
            throw GameIdleElapsedPolicyError.negativeMinimumSeconds(minimumSeconds)
        }
        guard maximumSeconds > 0 else {
            throw GameIdleElapsedPolicyError.nonPositiveMaximumSeconds(maximumSeconds)
        }
        guard minimumSeconds <= maximumSeconds else {
            throw GameIdleElapsedPolicyError.minimumExceedsMaximum(
                minimum: minimumSeconds,
                maximum: maximumSeconds
            )
        }
        self.minimumSeconds = minimumSeconds
        self.maximumSeconds = maximumSeconds
        self.overflow = overflow
        self.belowMinimum = belowMinimum
    }

    private init(
        validatedMinimumSeconds minimumSeconds: Int,
        maximumSeconds: Int,
        overflow: GameIdleOverflowPolicy,
        belowMinimum: GameIdleBelowMinimumPolicy
    ) {
        self.minimumSeconds = minimumSeconds
        self.maximumSeconds = maximumSeconds
        self.overflow = overflow
        self.belowMinimum = belowMinimum
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            minimumSeconds: container.decode(Int.self, forKey: .minimumSeconds),
            maximumSeconds: container.decode(Int.self, forKey: .maximumSeconds),
            overflow: container.decode(GameIdleOverflowPolicy.self, forKey: .overflow),
            belowMinimum: container.decode(
                GameIdleBelowMinimumPolicy.self,
                forKey: .belowMinimum
            )
        )
    }

    /// 최소 임계 없음 + 7일 캡. isekai 커널이 테스트로 굳힌 값.
    public static let standardV1 = GameIdleElapsedPolicy(
        validatedMinimumSeconds: 0,
        maximumSeconds: 7 * GameIdleDuration.secondsPerDay,
        overflow: .discard,
        belowMinimum: .carryOver
    )

    /// 최소 1분 + 8시간 캡. gaya `applyOfflineProgress` 의 값.
    public static let shortSessionV1 = GameIdleElapsedPolicy(
        validatedMinimumSeconds: GameIdleDuration.secondsPerMinute,
        maximumSeconds: 8 * GameIdleDuration.secondsPerHour,
        overflow: .discard,
        belowMinimum: .carryOver
    )

    /// 기준 시각과 현재 시각으로 경과를 산출한다.
    ///
    /// 무한대 `Date` 가 섞이면 뺄셈이 NaN 이 되므로 먼저 걸러낸다.
    public func elapsed(from lastSettledAt: Date, to now: Date) -> GameIdleElapsed {
        guard GameIdleSeconds.isFinite(lastSettledAt), GameIdleSeconds.isFinite(now) else {
            return .invalidClock
        }
        return elapsed(interval: now.timeIntervalSince(lastSettledAt))
    }

    /// 초 단위 구간으로 경과를 산출한다(NaN·무한대·음수 방어 포함).
    public func elapsed(interval: TimeInterval) -> GameIdleElapsed {
        guard interval.isFinite else { return .invalidClock }
        guard interval > 0 else {
            let wentBackwards = interval < 0
            return GameIdleElapsed(
                rawSeconds: 0,
                settledSeconds: 0,
                wasCapped: false,
                wasBelowMinimum: !wentBackwards && minimumSeconds > 0,
                clockWentBackwards: wentBackwards,
                clockWasInvalid: false
            )
        }

        let rawSeconds = GameIdleSeconds.saturating(interval)
        let wasBelowMinimum = rawSeconds < minimumSeconds
        let wasCapped = rawSeconds > maximumSeconds
        let settledSeconds = wasBelowMinimum ? 0 : min(rawSeconds, maximumSeconds)
        return GameIdleElapsed(
            rawSeconds: rawSeconds,
            settledSeconds: settledSeconds,
            wasCapped: wasCapped,
            wasBelowMinimum: wasBelowMinimum,
            clockWentBackwards: false,
            clockWasInvalid: false
        )
    }
}

/// 경과 산출 1회의 결과.
public struct GameIdleElapsed: Codable, Hashable, Sendable {
    /// 시계가 알려준 경과 초(캡·임계 적용 전, 포화 변환 후). 역행·비정상이면 0.
    public let rawSeconds: Int
    /// 실제로 시뮬레이션에 반영해야 할 초.
    public let settledSeconds: Int
    /// 캡에 걸려 잘렸는지.
    public let wasCapped: Bool
    /// 최소 임계에 미치지 못했는지.
    public let wasBelowMinimum: Bool
    /// 기준 시각보다 현재가 과거였는지(시계 되돌림).
    public let clockWentBackwards: Bool
    /// NaN·무한대 등 계산 불가한 시각이었는지.
    public let clockWasInvalid: Bool

    public init(
        rawSeconds: Int,
        settledSeconds: Int,
        wasCapped: Bool,
        wasBelowMinimum: Bool,
        clockWentBackwards: Bool,
        clockWasInvalid: Bool
    ) {
        self.rawSeconds = max(0, rawSeconds)
        self.settledSeconds = max(0, settledSeconds)
        self.wasCapped = wasCapped
        self.wasBelowMinimum = wasBelowMinimum
        self.clockWentBackwards = clockWentBackwards
        self.clockWasInvalid = clockWasInvalid
    }

    public static let none = GameIdleElapsed(
        rawSeconds: 0,
        settledSeconds: 0,
        wasCapped: false,
        wasBelowMinimum: false,
        clockWentBackwards: false,
        clockWasInvalid: false
    )

    public static let invalidClock = GameIdleElapsed(
        rawSeconds: 0,
        settledSeconds: 0,
        wasCapped: false,
        wasBelowMinimum: false,
        clockWentBackwards: false,
        clockWasInvalid: true
    )

    /// 반영할 것이 하나도 없으면 복귀 화면을 띄우지 않는다.
    public var isEmpty: Bool { settledSeconds == 0 }

    /// 이번에 반영되지 않은 초(캡 초과분 또는 임계 미만 구간).
    public var unsettledSeconds: Int { max(0, rawSeconds - settledSeconds) }

    /// "n일 n시간" 표시를 위한 분해.
    public var duration: GameIdleDuration { GameIdleDuration(totalSeconds: settledSeconds) }
}
