import Foundation

/// 외란 이벤트 (Disturbance Event)
///
/// 시스템의 평형을 깨뜨릴 수 있는 외부 또는 내부 변화(외란)를 나타냅니다.
public enum DisturbanceEvent: Sendable, Equatable {
    /// 파일 변경 및 설정 드리프트
    case fileDrift(path: String)
    /// 네트워크 연결 상태 변화
    case networkStateChanged(isOnline: Bool)
    /// 주기적 항상성 점검 틱
    case heartbeatTick
    /// 도메인 특화 커스텀 외란
    case custom(name: String)
}

/// 외란 감지 센서 규약 (Homeostatic Disturbance Sensor Protocol)
///
/// 외부 환경의 변화 및 드리프트를 감지하여 비동기 이벤트 스트림으로 방출합니다.
public protocol HomeostaticDisturbanceSensor: Sendable {
    /// 외란 이벤트 비동기 스트림 반환
    func disturbanceStream() -> AsyncStream<DisturbanceEvent>
}

/// 브로드캐스트/패스스루 수동 외란 센서 (테스트 및 수동 이벤트 주입용)
public final class PassthroughDisturbanceSensor: HomeostaticDisturbanceSensor, Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuations: [UUID: AsyncStream<DisturbanceEvent>.Continuation] = [:]

    public init() {}

    public func disturbanceStream() -> AsyncStream<DisturbanceEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                self.lock.lock()
                self.continuations.removeValue(forKey: id)
                self.lock.unlock()
            }
        }
    }

    /// 외란 이벤트 브로드캐스트 방출
    public func emit(_ event: DisturbanceEvent) {
        lock.lock()
        let active = Array(continuations.values)
        lock.unlock()
        for cont in active {
            cont.yield(event)
        }
    }

    /// 스트림 종료
    public func finish() {
        lock.lock()
        let active = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        for cont in active {
            cont.finish()
        }
    }
}

/// 주기적 하트비트 외란 센서
public final class HeartbeatDisturbanceSensor: HomeostaticDisturbanceSensor, Sendable {
    private let intervalNanoseconds: UInt64
    private let passthrough = PassthroughDisturbanceSensor()
    private let lock = NSLock()
    nonisolated(unsafe) private var timerTask: Task<Void, Never>?

    public init(intervalNanoseconds: UInt64 = 1_000_000_000) {
        self.intervalNanoseconds = intervalNanoseconds
    }

    private static func logCancellation() {}

    public func start() {
        lock.lock()
        defer { lock.unlock() }
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: self.intervalNanoseconds) // lint:allow-sleep
                } catch is CancellationError {
                    Self.logCancellation()
                    return
                } catch {
                    Self.logCancellation()
                    return
                }
                if Task.isCancelled { break }
                self.passthrough.emit(.heartbeatTick)
            }
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        timerTask?.cancel()
        timerTask = nil
    }

    public func disturbanceStream() -> AsyncStream<DisturbanceEvent> {
        passthrough.disturbanceStream()
    }
}

/// 항상성 센서 하네스 (Homeostatic Sensor Harness)
///
/// 센서 스트림을 구독(Listen)하다가 외란 이벤트가 도착하면
/// 자동으로 `loop.reconcile(desired:initial:)`을 트리거하는 자율 구동 하네스입니다.
public actor HomeostaticSensorHarness<R: HomeostaticReconcilable> {
    public typealias Verdict = HomeostaticConvergenceLoop<R>.ConvergenceVerdict

    public struct ReconciliationRecord: Sendable, Equatable {
        public let event: DisturbanceEvent
        public let verdict: Verdict
        public let state: R.ActualState

        public init(event: DisturbanceEvent, verdict: Verdict, state: R.ActualState) {
            self.event = event
            self.verdict = verdict
            self.state = state
        }
    }

    public let loop: HomeostaticConvergenceLoop<R>
    public private(set) var currentState: R.ActualState
    public private(set) var desiredState: R.DesiredState
    public private(set) var lastVerdict: Verdict?
    public private(set) var lastEvent: DisturbanceEvent?
    public private(set) var handledEventCount: Int = 0
    public private(set) var isRunning: Bool = false
    public private(set) var history: [ReconciliationRecord] = []

    private let sensor: any HomeostaticDisturbanceSensor
    private var listeningTask: Task<Void, Never>?
    private var selfHealer: (@Sendable (Verdict, R.ActualState) -> R.ActualState)?

    /// 외란 이벤트 발생 시 현재 상태를 갱신/반영할 수 있는 어댑터 클로저
    public var disturbanceAdapter: (@Sendable (DisturbanceEvent, R.ActualState) -> R.ActualState)?

    /// 수렴 시도 후 호출되는 관측 클로저
    public var onReconciled: (@Sendable (DisturbanceEvent, Verdict, R.ActualState) async -> Void)?

    /// 기본 지정 생성자 (Designated Initializer)
    public init(
        sensor: any HomeostaticDisturbanceSensor,
        loop: HomeostaticConvergenceLoop<R>,
        initial: R.ActualState,
        desired: R.DesiredState,
        selfHealer: (@Sendable (Verdict, R.ActualState) -> R.ActualState)? = nil,
        disturbanceAdapter: (@Sendable (DisturbanceEvent, R.ActualState) -> R.ActualState)? = nil,
        onReconciled: (@Sendable (DisturbanceEvent, Verdict, R.ActualState) async -> Void)? = nil
    ) {
        self.sensor = sensor
        self.loop = loop
        self.currentState = initial
        self.desiredState = desired
        self.selfHealer = selfHealer
        self.disturbanceAdapter = disturbanceAdapter
        self.onReconciled = onReconciled
    }

    /// Reconciler 기반 편의 생성자
    public init(
        sensor: any HomeostaticDisturbanceSensor,
        reconciler: R,
        initial: R.ActualState,
        desired: R.DesiredState,
        maxIterations: Int = 5,
        dampingNanoseconds: UInt64 = 0,
        disturbanceAdapter: (@Sendable (DisturbanceEvent, R.ActualState) -> R.ActualState)? = nil,
        onReconciled: (@Sendable (DisturbanceEvent, Verdict, R.ActualState) async -> Void)? = nil
    ) {
        self.init(
            sensor: sensor,
            loop: HomeostaticConvergenceLoop(
                reconciler: reconciler,
                maxIterations: maxIterations,
                dampingNanoseconds: dampingNanoseconds
            ),
            initial: initial,
            desired: desired,
            selfHealer: nil,
            disturbanceAdapter: disturbanceAdapter,
            onReconciled: onReconciled
        )
    }

    /// 목표 상태 갱신
    public func updateDesiredState(_ state: R.DesiredState) {
        self.desiredState = state
    }

    /// 현재 상태 수동 갱신
    public func updateCurrentState(_ state: R.ActualState) {
        self.currentState = state
    }

    /// 센서 스트림 구독 시작 (자율 구동)
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        let stream = sensor.disturbanceStream()
        listeningTask = Task { [weak self] in
            for await event in stream {
                guard let self else { break }
                if Task.isCancelled { break }
                _ = await self.handleDisturbance(event)
            }
        }
    }

    /// 센서 스트림 구독 중단
    public func stop() {
        listeningTask?.cancel()
        listeningTask = nil
        isRunning = false
    }

    private func applyDisturbanceAdapter(_ event: DisturbanceEvent) {
        guard let disturbanceAdapter else { return }
        self.currentState = disturbanceAdapter(event, self.currentState)
    }

    private func applyVerdictResolution(_ verdict: Verdict) {
        if let selfHealer {
            self.currentState = selfHealer(verdict, self.currentState)
            return
        }
        if case .converged(let finalState, _) = verdict {
            self.currentState = finalState
        }
    }

    private func notifyReconciled(_ event: DisturbanceEvent, verdict: Verdict) async {
        guard let onReconciled else { return }
        await onReconciled(event, verdict, self.currentState)
    }

    /// 단일 외란 이벤트 수동 주입 및 수렴 트리거
    @discardableResult
    public func handleDisturbance(_ event: DisturbanceEvent) async -> Verdict {
        self.lastEvent = event
        applyDisturbanceAdapter(event)

        let verdict = await loop.reconcile(desired: desiredState, initial: currentState)
        self.lastVerdict = verdict
        self.handledEventCount += 1

        applyVerdictResolution(verdict)

        let record = ReconciliationRecord(event: event, verdict: verdict, state: self.currentState)
        self.history.append(record)

        await notifyReconciled(event, verdict: verdict)

        return verdict
    }

    /// 현재 상태와 목표 상태 간 즉시 수렴 실행
    @discardableResult
    public func reconcileNow() async -> Verdict {
        await handleDisturbance(.custom(name: "manual_reconcile_trigger"))
    }

    /// 비동기 이벤트 처리 완료 대기 (테스트 및 동기화용)
    public func waitForEventCount(_ targetCount: Int, timeoutNanoseconds: UInt64 = 2_000_000_000) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while handledEventCount < targetCount {
            if DispatchTime.now().uptimeNanoseconds - start >= timeoutNanoseconds {
                return false
            }
            do {
                try await Task.sleep(nanoseconds: 5_000_000) // lint:allow-sleep
            } catch {
                return false
            }
        }
        return true
    }

    /// 자가 치유 클로저 설정/해제 (Actor 격리 본체)
    public func setSelfHealer(_ healer: (@Sendable (Verdict, R.ActualState) -> R.ActualState)?) {
        self.selfHealer = healer
    }
}

// MARK: - Self-Healing Extension

extension HomeostaticSensorHarness where R.ActualState: HomeostaticSelfHealing {
    public init(
        sensor: any HomeostaticDisturbanceSensor,
        loop: HomeostaticConvergenceLoop<R>,
        initial: R.ActualState,
        desired: R.DesiredState,
        enableSelfHealing: Bool,
        disturbanceAdapter: (@Sendable (DisturbanceEvent, R.ActualState) -> R.ActualState)? = nil,
        onReconciled: (@Sendable (DisturbanceEvent, Verdict, R.ActualState) async -> Void)? = nil
    ) {
        let healer: (@Sendable (Verdict, R.ActualState) -> R.ActualState)?
        if enableSelfHealing {
            healer = { (verdict: Verdict, current: R.ActualState) -> R.ActualState in
                switch verdict {
                case .converged(let finalState, _):
                    return finalState
                case .oscillationDetected(let lastState, _):
                    return lastState.toSafeEquilibrium()
                case .invariantBroken:
                    return current.toSafeEquilibrium()
                }
            }
        } else {
            healer = nil
        }

        self.init(
            sensor: sensor,
            loop: loop,
            initial: initial,
            desired: desired,
            selfHealer: healer,
            disturbanceAdapter: disturbanceAdapter,
            onReconciled: onReconciled
        )
    }

    public init(
        sensor: any HomeostaticDisturbanceSensor,
        reconciler: R,
        initial: R.ActualState,
        desired: R.DesiredState,
        enableSelfHealing: Bool,
        maxIterations: Int = 5,
        disturbanceAdapter: (@Sendable (DisturbanceEvent, R.ActualState) -> R.ActualState)? = nil,
        onReconciled: (@Sendable (DisturbanceEvent, Verdict, R.ActualState) async -> Void)? = nil
    ) {
        self.init(
            sensor: sensor,
            loop: HomeostaticConvergenceLoop(
                reconciler: reconciler,
                maxIterations: maxIterations,
                dampingNanoseconds: 0
            ),
            initial: initial,
            desired: desired,
            enableSelfHealing: enableSelfHealing,
            disturbanceAdapter: disturbanceAdapter,
            onReconciled: onReconciled
        )
    }

    /// 자가 치유 안전 모드 활성화/비활성화 전환
    public func setSelfHealingEnabled(_ enabled: Bool) {
        if enabled {
            self.setSelfHealer { (verdict: Verdict, current: R.ActualState) -> R.ActualState in
                switch verdict {
                case .converged(let finalState, _):
                    return finalState
                case .oscillationDetected(let lastState, _):
                    return lastState.toSafeEquilibrium()
                case .invariantBroken:
                    return current.toSafeEquilibrium()
                }
            }
        } else {
            let noHealer: (@Sendable (Verdict, R.ActualState) -> R.ActualState)? = nil
            self.setSelfHealer(noHealer)
        }
    }
}
