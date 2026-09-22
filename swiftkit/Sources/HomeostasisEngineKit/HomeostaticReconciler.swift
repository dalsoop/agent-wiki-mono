import Foundation

/// 항상성 수렴 엔진 규약 (Homeostatic Reconcilable Protocol)
///
/// 목표 상태(Desired)와 현재 상태(Actual)를 지속적으로 대조하여
/// 불변식(Invariants)을 사수하고 오차(Delta)를 0으로 멱등 수렴시키는 제어 인터페이스입니다.
public protocol HomeostaticReconcilable: Sendable {
    associatedtype DesiredState: Sendable & Equatable
    associatedtype ActualState: Sendable & Equatable
    associatedtype Action: Sendable
    associatedtype InvariantError: Error & Sendable

    /// 불변식 검증 (불법 상태 표현 및 전이 차단)
    func validateInvariants(actual: ActualState) -> Result<Void, InvariantError>

    /// 목표 상태와 현재 상태 간의 차이(Delta) 및 교정 액션 도출
    func diff(desired: DesiredState, actual: ActualState) -> [Action]

    /// 멱등적(Idempotent) 교정 액션 실행
    func apply(action: Action, to actual: ActualState) async throws -> ActualState
}

/// 항상성 수렴 제어 루프 (Homeostatic Convergence Loop)
///
/// 오차가 완전히 해소될 때까지 Reconciler를 반복 구동하며,
/// 플래핑(무한 진동) 방지 및 불변식 위반 감지 시 즉시 안전 수렴을 수행합니다.
public actor HomeostaticConvergenceLoop<R: HomeostaticReconcilable> {
    private let reconciler: R
    private let maxIterations: Int
    private let dampingNanoseconds: UInt64

    /// 수렴 최종 판정
    public enum ConvergenceVerdict: Sendable, Equatable {
        case converged(finalState: R.ActualState, iterations: Int)
        case oscillationDetected(lastState: R.ActualState, reason: String)
        case invariantBroken(reason: String)

        public static func == (lhs: ConvergenceVerdict, rhs: ConvergenceVerdict) -> Bool {
            switch (lhs, rhs) {
            case (.converged(let lState, let lIter), .converged(let rState, let rIter)):
                return lState == rState && lIter == rIter
            case (.oscillationDetected(let lState, let lReason), .oscillationDetected(let rState, let rReason)):
                return lState == rState && lReason == rReason
            case (.invariantBroken(let lReason), .invariantBroken(let rReason)):
                return lReason == rReason
            default:
                return false
            }
        }
    }

    public init(reconciler: R, maxIterations: Int = 5, dampingNanoseconds: UInt64 = 1_000_000) {
        self.reconciler = reconciler
        self.maxIterations = maxIterations
        self.dampingNanoseconds = dampingNanoseconds
    }

    /// 주어진 목표 상태(Desired)를 향해 현재 상태(Actual)를 수렴 실행
    public func reconcile(desired: R.DesiredState, initial: R.ActualState) async -> ConvergenceVerdict {
        var current = initial
        var iterations = 0

        while iterations < maxIterations {
            // 1. 불변식 사전 검증
            if case .failure(let err) = reconciler.validateInvariants(actual: current) {
                return .invariantBroken(reason: String(describing: err))
            }

            // 2. 오차 계산
            let actions = reconciler.diff(desired: desired, actual: current)
            if actions.isEmpty {
                return .converged(finalState: current, iterations: iterations)
            }

            // 3. 교정 액션 멱등 실행
            for action in actions {
                do {
                    current = try await reconciler.apply(action: action, to: current)
                } catch {
                    return .oscillationDetected(lastState: current, reason: "Actuator failure: \(error)")
                }
            }

            iterations += 1

            if dampingNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: dampingNanoseconds)
            }
        }

        // 최대 반복 횟수 초과 (플래핑 / 무한 진동 차단)
        return .oscillationDetected(lastState: current, reason: "Max iterations (\(maxIterations)) exceeded without convergence")
    }
}

/// 자가 치유 안전 평형 지원 규약 (Homeostatic Self-Healing Protocol)
///
/// 진동, 불변식 위반, 액추에이터 실패 등 외란 발생 시
/// 시스템을 즉시 안전 모드(Safe Equilibrium)로 수렴시키기 위한 인터페이스입니다.
public protocol HomeostaticSelfHealing: Sendable {
    /// 시스템 보호를 위한 안전 기준선 평형 상태 반환
    func toSafeEquilibrium() -> Self
}

extension HomeostaticConvergenceLoop where R.ActualState: HomeostaticSelfHealing {
    /// 자가 치유가 보장된 탄력적 수렴 실행
    public func reconcileWithSelfHealing(
        desired: R.DesiredState,
        initial: R.ActualState
    ) async -> (verdict: ConvergenceVerdict, safeState: R.ActualState) {
        let verdict = await reconcile(desired: desired, initial: initial)
        switch verdict {
        case .converged(let finalState, _):
            return (verdict, finalState)
        case .oscillationDetected(let lastState, _):
            return (verdict, lastState.toSafeEquilibrium())
        case .invariantBroken:
            return (verdict, initial.toSafeEquilibrium())
        }
    }
}

