import Foundation
#if canImport(os)
import os

private let logger = Logger(subsystem: "ConcurrencyKit", category: "AsyncTimeSequences")
#endif

/// 시간 기반 AsyncSequence 연산자(Debounce, Throttle)를 순수 Swift Concurrency로 제공합니다.
///
/// 외부 의존성 없이 `AsyncStream`, `Actor` 격리, `ContinuousClock`, `Task.sleep(for:)`을 활용하여
/// 완벽한 Swift 6 동시성 안정성을 보장합니다.
extension AsyncSequence where Element: Sendable, Self: Sendable {
    /// 업스트림 시퀀스에서 방출되는 요소를 지정된 시간(`duration`) 동안 디바운스합니다.
    ///
    /// 지정된 유휴 시간 동안 후속 요소가 방출되지 않으면 가장 마지막 요소를 다운스트림으로 방출합니다.
    ///
    /// - Parameters:
    ///   - duration: 연속된 이벤트 간 대기해야 하는 최소 지속 시간.
    ///   - clock: 대기 측정에 사용할 `ContinuousClock` 인스턴스 (기본값: `ContinuousClock()`).
    /// - Returns: 디바운스된 요소를 방출하는 `AsyncStream<Element>`.
    public func debounce(
        for duration: Duration,
        clock: ContinuousClock = ContinuousClock()
    ) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let actor = DebounceActor(
                duration: duration,
                clock: clock,
                continuation: continuation
            )

            let processingTask = Task {
                do {
                    for try await element in self {
                        await actor.emit(element)
                    }
                    await actor.finish()
                } catch {
                    #if canImport(os)
                    logger.debug("Debounce upstream cancelled or ended: \(error.localizedDescription)")
                    #endif
                    await actor.cancel()
                }
            }

            continuation.onTermination = { @Sendable _ in
                processingTask.cancel()
                Task {
                    await actor.cancel()
                }
            }
        }
    }

    /// 업스트림 시퀀스에서 방출되는 요소의 방출 빈도를 지정된 시간(`duration`) 간격으로 제한합니다.
    ///
    /// 첫 번째 요소는 즉시 방출되며(leading edge), 지정된 지속 시간 동안 윈도우가 열립니다.
    /// - `latest == true`: 윈도우 열림 동안 도착한 이벤트 중 가장 최신 요소를 윈도우 종료 시점에 방출합니다.
    /// - `latest == false`: 윈도우 열림 동안 도착한 모든 후속 이벤트를 무시(drop)합니다.
    ///
    /// - Parameters:
    ///   - duration: 스로틀링 윈도우 지속 시간.
    ///   - latest: 윈도우 동안 마지막으로 수신된 요소를 윈도우 만료 시 방출할지 여부 (기본값: `true`).
    ///   - clock: 윈도우 시간 측정에 사용할 `ContinuousClock` 인스턴스 (기본값: `ContinuousClock()`).
    /// - Returns: 스로틀링된 요소를 방출하는 `AsyncStream<Element>`.
    public func throttle(
        for duration: Duration,
        latest: Bool = true,
        clock: ContinuousClock = ContinuousClock()
    ) -> AsyncStream<Element> {
        AsyncStream { continuation in
            let actor = ThrottleActor(
                duration: duration,
                latest: latest,
                clock: clock,
                continuation: continuation
            )

            let processingTask = Task {
                do {
                    for try await element in self {
                        await actor.emit(element)
                    }
                    await actor.finish()
                } catch {
                    #if canImport(os)
                    logger.debug("Throttle upstream cancelled or ended: \(error.localizedDescription)")
                    #endif
                    await actor.cancel()
                }
            }

            continuation.onTermination = { @Sendable _ in
                processingTask.cancel()
                Task {
                    await actor.cancel()
                }
            }
        }
    }
}

// MARK: - Actor State Coordinators

/// 디바운스 타이머 및 방출 상태를 안전하게 조정하는 Actor.
private actor DebounceActor<Element: Sendable> {
    private let duration: Duration
    private let clock: ContinuousClock
    private let continuation: AsyncStream<Element>.Continuation

    private var timerTask: Task<Void, Never>?
    private var pendingValue: Element?
    private var isUpstreamFinished = false

    init(
        duration: Duration,
        clock: ContinuousClock,
        continuation: AsyncStream<Element>.Continuation
    ) {
        self.duration = duration
        self.clock = clock
        self.continuation = continuation
    }

    func emit(_ value: Element) {
        pendingValue = value
        timerTask?.cancel()
        timerTask = Task { [weak self, clock, duration] in
            do {
                try await Task.sleep(for: duration, tolerance: nil, clock: clock) // lint:allow-sleep
                await self?.timerFired()
            } catch {
                #if canImport(os)
                logger.debug("Debounce timer cancelled: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func timerFired() {
        guard !Task.isCancelled else { return }
        if let value = pendingValue {
            continuation.yield(value)
            pendingValue = nil
        }
        timerTask = nil
        if isUpstreamFinished {
            continuation.finish()
        }
    }

    func finish() {
        isUpstreamFinished = true
        if timerTask == nil {
            continuation.finish()
        }
    }

    func cancel() {
        timerTask?.cancel()
        timerTask = nil
        pendingValue = nil
        continuation.finish()
    }
}

/// 스로틀 윈도우 및 후행 방출 상태를 안전하게 조정하는 Actor.
private actor ThrottleActor<Element: Sendable> {
    private let duration: Duration
    private let latest: Bool
    private let clock: ContinuousClock
    private let continuation: AsyncStream<Element>.Continuation

    private var windowTask: Task<Void, Never>?
    private var trailingValue: Element?
    private var isUpstreamFinished = false

    init(
        duration: Duration,
        latest: Bool,
        clock: ContinuousClock,
        continuation: AsyncStream<Element>.Continuation
    ) {
        self.duration = duration
        self.latest = latest
        self.clock = clock
        self.continuation = continuation
    }

    func emit(_ value: Element) {
        if windowTask == nil {
            // 비활성 윈도우: 최초 요소를 선행(leading) 방출하고 윈도우 개설
            continuation.yield(value)
            startWindow()
        } else {
            // 활성 윈도우: latest가 true인 경우에만 최신 후속 요소를 저장
            if latest {
                trailingValue = value
            }
        }
    }

    private func startWindow() {
        windowTask = Task { [weak self, clock, duration] in
            do {
                try await Task.sleep(for: duration, tolerance: nil, clock: clock) // lint:allow-sleep
                await self?.windowElapsed()
            } catch {
                #if canImport(os)
                logger.debug("Throttle window cancelled: \(error.localizedDescription)")
                #endif
            }
        }
    }

    private func windowElapsed() {
        guard !Task.isCancelled else { return }
        windowTask = nil

        guard latest, let value = trailingValue else {
            if isUpstreamFinished {
                continuation.finish()
            }
            return
        }

        trailingValue = nil
        continuation.yield(value)
        guard !isUpstreamFinished else {
            continuation.finish()
            return
        }
        startWindow()
    }

    func finish() {
        isUpstreamFinished = true
        if windowTask == nil {
            continuation.finish()
        } else if !latest || trailingValue == nil {
            windowTask?.cancel()
            windowTask = nil
            continuation.finish()
        }
    }

    func cancel() {
        windowTask?.cancel()
        windowTask = nil
        trailingValue = nil
        continuation.finish()
    }
}
