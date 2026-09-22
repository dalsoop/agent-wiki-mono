import Foundation

/// 항상성 상태 영속 스토리지 규약 (Homeostatic State Storage Protocol)
///
/// StateMirror, FastDiskIOKit, SQLite 등 다양한 백엔드를 추상화하여
/// 앱 재기동 시 마지막 평형 상태 복원 및 수렴 결과 저장을 담당합니다.
public protocol HomeostaticStateStorage: Sendable {
    associatedtype State: Sendable & Codable

    /// 디스크 원장에서 마지막 안정 상태 로드
    func load() async throws -> State?

    /// 수렴된 평형 상태를 디스크 원장에 원자적 영속화
    func save(_ state: State) async throws
}

/// 재부팅 복원력을 갖춘 영속 항상성 하네스 (Homeostatic Persistent Harness)
///
/// 1. 부팅 시 디스크 원장 로드 (Zero Data Loss)
/// 2. 부팅 즉시 1회성 Reconcile-on-Launch 구동 (꺼져 있던 동안의 외란/드리프트 자동 치유)
/// 3. 런타임 외란 센서 감시 및 평형 도달 시 디스크 자동 영속화
public actor HomeostaticPersistentHarness<R: HomeostaticReconcilable, Storage: HomeostaticStateStorage>
where R.ActualState == Storage.State, R.ActualState: HomeostaticSelfHealing {

    public typealias Verdict = HomeostaticConvergenceLoop<R>.ConvergenceVerdict

    private let loop: HomeostaticConvergenceLoop<R>
    private let sensor: any HomeostaticDisturbanceSensor
    private let storage: Storage
    private var desiredState: R.DesiredState
    private var actualState: R.ActualState
    private var isRunning: Bool = false
    private var monitorTask: Task<Void, Never>?
    public private(set) var lastError: (any Error)?

    public var currentActual: R.ActualState { actualState }
    public var currentDesired: R.DesiredState { desiredState }

    public init(
        loop: HomeostaticConvergenceLoop<R>,
        sensor: any HomeostaticDisturbanceSensor,
        storage: Storage,
        fallbackInitial: R.ActualState,
        initialDesired: R.DesiredState
    ) {
        self.loop = loop
        self.sensor = sensor
        self.storage = storage
        self.actualState = fallbackInitial
        self.desiredState = initialDesired
    }

    /// 부팅 온보딩 및 외란 리스너 기동 (Reconcile-on-Launch 포함)
    @discardableResult
    public func start() async -> Verdict {
        guard !isRunning else {
            return .converged(finalState: actualState, iterations: 0)
        }
        isRunning = true

        // 1. 디스크 원장에서 마지막 안정 상태 로드 (없으면 fallbackInitial 유지)
        do {
            if let saved = try await storage.load() {
                self.actualState = saved
            }
        } catch {
            self.lastError = error
            // 로드 실패 시 fallbackInitial 유지
        }

        // 2. 부팅 즉시 Reconcile-on-Launch 구동 (공백기 외란 복구)
        let (verdict, safeState) = await loop.reconcileWithSelfHealing(
            desired: desiredState,
            initial: actualState
        )
        self.actualState = safeState

        // 3. 복원된 평형 상태를 디스크에 동기화
        do {
            try await storage.save(safeState)
        } catch {
            self.lastError = error
            // 저장 실패 시 메모리 평형 유지
        }

        // 4. 백그라운드 외란 센서 스트림 구독
        monitorTask = Task { [weak self, sensor] in
            for await event in sensor.disturbanceStream() {
                guard let self, await self.isRunning else { break }
                _ = await self.handleDisturbance(event)
            }
        }

        return verdict
    }

    /// 외란 발생 시 수렴 및 디스크 영속화
    @discardableResult
    public func handleDisturbance(_ event: DisturbanceEvent) async -> Verdict {
        let (verdict, safeState) = await loop.reconcileWithSelfHealing(
            desired: desiredState,
            initial: actualState
        )
        self.actualState = safeState

        // 수렴 완료 시 즉각 원자적 디스크 저장
        do {
            try await storage.save(safeState)
        } catch {
            self.lastError = error
            // 저장 실패 시 메모리 평형 유지
        }

        return verdict
    }

    /// 목표 상태 갱신 및 즉시 수렴
    @discardableResult
    public func updateDesired(_ newDesired: R.DesiredState) async -> Verdict {
        self.desiredState = newDesired
        return await handleDisturbance(.custom(name: "desired_spec_updated"))
    }

    /// 하네스 정지 및 리소스 정리
    public func stop() {
        isRunning = false
        monitorTask?.cancel()
        monitorTask = nil
    }
}
