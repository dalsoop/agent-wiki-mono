import Foundation
import GameRealtimeRuntimeKit

/// 지연 실행 주입 지점.
///
/// 실제 앱은 타이머를, 테스트는 수동 스케줄러를 넣는다. 대기 시간 자체는
/// `GameIdleSaveDebouncer` 가 주입된 시계로 계산하므로 여기서는 "언제 깨울지" 만 다룬다.
@MainActor
public protocol GameIdleSaveScheduler: AnyObject {
    var hasPendingWakeUp: Bool { get }
    /// `delay` 뒤에 `action` 을 실행한다. 이전 예약은 취소된다.
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void)
    /// 예약을 실행하지 않고 버린다.
    func cancel()
}

/// 실제 시간을 기다리는 스케줄러.
@MainActor
public final class DebouncingGameIdleSaveScheduler: GameIdleSaveScheduler {
    public private(set) var hasPendingWakeUp = false

    private var task: Task<Void, Never>?

    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        hasPendingWakeUp = true
        let waited = delay < .zero ? .zero : delay
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: waited)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            hasPendingWakeUp = false
            task = nil
            action()
        }
    }

    public func cancel() {
        task?.cancel()
        task = nil
        hasPendingWakeUp = false
    }

    deinit {
        task?.cancel()
    }
}

/// 테스트용 스케줄러. `fire()` 를 부를 때까지 아무것도 하지 않는다.
@MainActor
public final class ManualGameIdleSaveScheduler: GameIdleSaveScheduler {
    public private(set) var hasPendingWakeUp = false
    /// 마지막으로 요청된 대기 시간.
    public private(set) var lastRequestedDelay: Duration?
    public private(set) var scheduleCount = 0
    public private(set) var cancelCount = 0

    private var pendingAction: (@MainActor () -> Void)?

    public init() {}

    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        scheduleCount += 1
        lastRequestedDelay = delay
        pendingAction = action
        hasPendingWakeUp = true
    }

    public func cancel() {
        cancelCount += 1
        pendingAction = nil
        hasPendingWakeUp = false
    }

    /// 예약된 깨우기를 지금 실행한다.
    @discardableResult
    public func fire() -> Bool {
        guard let action = pendingAction else { return false }
        pendingAction = nil
        hasPendingWakeUp = false
        action()
        return true
    }
}

/// 디바운스 저장 조율기: 코어(`GameIdleSaveDebouncer`) + 시계 + 스케줄러.
///
/// - 시간 소스는 `GameRealtimeClock` 주입(테스트는 `ManualGameIdleClock`). `Date()` 를 부르지 않는다.
/// - `requestSave()` 는 연속 호출을 병합한다.
/// - `requestImmediateSave()` / `flush()` 는 게임 월 경계·앱 종료처럼 기다릴 수 없는 시점용.
@MainActor
public final class GameIdleAutoSave {
    private var debouncer: GameIdleSaveDebouncer
    private let clock: any GameRealtimeClock
    private let scheduler: any GameIdleSaveScheduler
    private let save: @MainActor (GameIdleSaveTrigger) -> Void

    public init(
        debouncer: GameIdleSaveDebouncer = .standardV1,
        clock: any GameRealtimeClock = ContinuousGameIdleClock(),
        scheduler: any GameIdleSaveScheduler = DebouncingGameIdleSaveScheduler(),
        save: @escaping @MainActor (GameIdleSaveTrigger) -> Void
    ) {
        self.debouncer = debouncer
        self.clock = clock
        self.scheduler = scheduler
        self.save = save
    }

    public var hasPendingSave: Bool { debouncer.hasPendingSave }
    public var pendingRequestCount: Int { debouncer.pendingRequestCount }
    public var remaining: Duration? { debouncer.remaining(at: clock.now()) }
    /// 이번 저장으로 몇 번 저장 콜백이 불렸는지(테스트·진단용).
    public private(set) var saveCount = 0

    /// 저장을 예약한다. debounce 규칙에 따라 연속 요청은 하나로 합쳐진다.
    public func requestSave() {
        let now = clock.now()
        debouncer.request(at: now)
        rearm(now: now)
    }

    /// 다음 깨우기에서 바로 저장되도록 예약한다.
    public func requestImmediateSave() {
        let now = clock.now()
        debouncer.requestImmediate(at: now)
        rearm(now: now)
    }

    /// 대기 중인 저장을 지금 실행한다. 대기가 없으면 아무 일도 하지 않는다.
    @discardableResult
    public func flush() -> GameIdleSaveTrigger? {
        scheduler.cancel()
        guard let trigger = debouncer.flush(at: clock.now()) else { return nil }
        fire(trigger)
        return trigger
    }

    /// 마감이 지났으면 저장한다. 틱 루프에서 부르는 폴링 경로.
    @discardableResult
    public func poll() -> GameIdleSaveTrigger? {
        guard let trigger = debouncer.poll(at: clock.now()) else { return nil }
        scheduler.cancel()
        fire(trigger)
        return trigger
    }

    /// 대기 중인 저장을 실행하지 않고 버린다.
    public func cancel() {
        scheduler.cancel()
        debouncer.cancel()
    }

    private func rearm(now: ContinuousClock.Instant) {
        guard let remaining = debouncer.remaining(at: now) else { return }
        scheduler.schedule(after: remaining) { [weak self] in
            self?.wakeUp()
        }
    }

    private func wakeUp() {
        let now = clock.now()
        if let trigger = debouncer.poll(at: now) {
            fire(trigger)
            return
        }
        // 마감이 뒤로 밀렸다(그 사이 새 요청이 들어왔다) — 남은 시간만큼 다시 잰다.
        rearm(now: now)
    }

    private func fire(_ trigger: GameIdleSaveTrigger) {
        saveCount += 1
        save(trigger)
    }
}
