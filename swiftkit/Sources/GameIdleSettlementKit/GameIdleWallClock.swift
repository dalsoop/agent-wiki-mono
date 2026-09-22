import Foundation

/// 벽시계(사용자가 인지하는 실제 날짜/시각) 주입 지점.
///
/// 오프라인 경과는 프로세스 재시작을 가로지르므로 `ContinuousClock` 처럼 부팅 기준
/// 단조 시계로는 잴 수 없다. 저장에 남길 수 있는 `Date` 가 필요하다. 반대로 debounce
/// 저장처럼 한 세션 안에서만 재는 시간은 기존 척추의 `GameRealtimeClock`
/// (`GameRealtimeRuntimeKit`) 을 그대로 쓴다 — 여기서 새로 만들지 않는다.
///
/// 프로덕션 코드에서 `Date()` 를 직접 부르지 말고 이 프로토콜을 주입받는다.
public protocol GameIdleWallClock: Sendable {
    func now() -> Date
}

/// 시스템 벽시계.
public struct SystemGameIdleWallClock: GameIdleWallClock {
    public init() {}

    public func now() -> Date { Date() }
}

/// 테스트용 벽시계. 시계 역행까지 재현할 수 있도록 뒤로 감기를 허용한다.
public final class ManualGameIdleWallClock: GameIdleWallClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    public init(now: Date) {
        instant = now
    }

    public func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return instant
    }

    /// 임의 방향으로 시각을 옮긴다. 음수면 시계 역행 시나리오.
    public func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        instant = instant.addingTimeInterval(interval)
    }

    public func set(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        instant = date
    }
}
