import Foundation
import GameRealtimeRuntimeKit

/// 연속 요청 병합 방식.
public enum GameIdleSaveCoalescing: UInt8, Codable, Hashable, Sendable {
    /// 요청할 때마다 마감을 다시 잡는다(조용해질 때까지 미룬다). isekai 5초 debounce.
    case restartOnRequest = 1
    /// 첫 요청의 마감을 유지한다(최대 대기 보장). gaya `saveSoon` 0.5초.
    case keepFirstDeadline = 2
}

public enum GameIdleSaveDebouncerError: Error, Equatable, Sendable {
    case negativeInterval(Duration)
}

/// 저장이 실제로 일어난 이유.
public struct GameIdleSaveTrigger: Hashable, Sendable {
    public enum Reason: UInt8, Codable, Hashable, Sendable {
        /// debounce 마감 도달.
        case deadline = 1
        /// 기다릴 수 없는 시점(게임 월 경계·앱 종료)의 강제 저장.
        case flush = 2
    }

    public let reason: Reason
    /// 이번 저장으로 병합된 요청 수.
    public let coalescedRequestCount: Int
    public let firedAt: ContinuousClock.Instant

    public init(
        reason: Reason,
        coalescedRequestCount: Int,
        firedAt: ContinuousClock.Instant
    ) {
        self.reason = reason
        self.coalescedRequestCount = max(0, coalescedRequestCount)
        self.firedAt = firedAt
    }
}

/// 디바운스 저장의 순수 코어. 시간은 항상 인자로 받는다 — 내부에서 시계를 읽지 않는다.
///
/// 값 타입이라 타이머 없이 결정적으로 테스트할 수 있고, 실제 타이머(`GameIdleAutoSave`)는
/// 이 코어를 감싸기만 한다.
public struct GameIdleSaveDebouncer: Hashable, Sendable {
    public let interval: Duration
    public let coalescing: GameIdleSaveCoalescing
    public private(set) var deadline: ContinuousClock.Instant?
    public private(set) var pendingRequestCount: Int

    public init(
        interval: Duration,
        coalescing: GameIdleSaveCoalescing = .restartOnRequest
    ) throws {
        guard interval >= .zero else {
            throw GameIdleSaveDebouncerError.negativeInterval(interval)
        }
        self.interval = interval
        self.coalescing = coalescing
        deadline = nil
        pendingRequestCount = 0
    }

    private init(
        validatedInterval interval: Duration,
        coalescing: GameIdleSaveCoalescing
    ) {
        self.interval = interval
        self.coalescing = coalescing
        deadline = nil
        pendingRequestCount = 0
    }

    /// gaya 값(0.5초, 첫 요청 마감 유지).
    public static let shortSessionV1 = GameIdleSaveDebouncer(
        validatedInterval: .milliseconds(500),
        coalescing: .keepFirstDeadline
    )

    /// isekai 값(5초, 요청마다 마감 재설정).
    public static let standardV1 = GameIdleSaveDebouncer(
        validatedInterval: .seconds(5),
        coalescing: .restartOnRequest
    )

    public var hasPendingSave: Bool { deadline != nil }

    /// 저장을 예약한다. 이미 예약이 있으면 `coalescing` 규칙대로 병합한다.
    public mutating func request(at now: ContinuousClock.Instant) {
        pendingRequestCount = GameIdleSeconds.addingSaturating(pendingRequestCount, 1)
        switch coalescing {
        case .restartOnRequest:
            deadline = now.advanced(by: interval)
        case .keepFirstDeadline:
            if deadline == nil { deadline = now.advanced(by: interval) }
        }
    }

    /// 대기 없이 즉시 만기되는 요청(다음 `poll` 에서 바로 저장).
    public mutating func requestImmediate(at now: ContinuousClock.Instant) {
        pendingRequestCount = GameIdleSeconds.addingSaturating(pendingRequestCount, 1)
        deadline = now
    }

    /// 마감까지 남은 시간. 예약이 없으면 nil, 이미 지났으면 `.zero`.
    public func remaining(at now: ContinuousClock.Instant) -> Duration? {
        guard let deadline else { return nil }
        let remaining = now.duration(to: deadline)
        return remaining < .zero ? .zero : remaining
    }

    public func isDue(at now: ContinuousClock.Instant) -> Bool {
        guard let deadline else { return false }
        return now >= deadline
    }

    /// 마감이 지났으면 대기를 비우고 저장 트리거를 돌려준다. 아니면 nil.
    public mutating func poll(at now: ContinuousClock.Instant) -> GameIdleSaveTrigger? {
        guard isDue(at: now) else { return nil }
        return take(at: now, reason: .deadline)
    }

    /// 마감과 무관하게 즉시 저장한다. 대기가 없으면 nil(저장할 것이 없다).
    public mutating func flush(at now: ContinuousClock.Instant) -> GameIdleSaveTrigger? {
        guard hasPendingSave else { return nil }
        return take(at: now, reason: .flush)
    }

    /// 대기 중인 저장을 실행하지 않고 버린다.
    public mutating func cancel() {
        deadline = nil
        pendingRequestCount = 0
    }

    private mutating func take(
        at now: ContinuousClock.Instant,
        reason: GameIdleSaveTrigger.Reason
    ) -> GameIdleSaveTrigger {
        let trigger = GameIdleSaveTrigger(
            reason: reason,
            coalescedRequestCount: pendingRequestCount,
            firedAt: now
        )
        deadline = nil
        pendingRequestCount = 0
        return trigger
    }
}

/// 세션 내부 시간용 시계 — 기존 척추의 `GameRealtimeClock` 을 그대로 쓴다.
public struct ContinuousGameIdleClock: GameRealtimeClock {
    public init() {}

    public func now() -> ContinuousClock.Instant { ContinuousClock.now }
}

/// 테스트용 참조형 단조 시계.
///
/// `ManualGameRealtimeClock` 은 구조체라 스케줄러에 주입하면 복사본이 전진해 테스트가
/// 관측할 수 없다. 프로토콜은 재사용하고 참조 의미만 추가한다.
public final class ManualGameIdleClock: GameRealtimeClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: ContinuousClock.Instant

    public init(now: ContinuousClock.Instant = ContinuousClock.now) {
        instant = now
    }

    public func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    /// 단조 시계이므로 전진만 허용한다.
    public func advance(by duration: Duration) {
        guard duration > .zero else { return }
        lock.lock()
        defer { lock.unlock() }
        instant = instant.advanced(by: duration)
    }
}
