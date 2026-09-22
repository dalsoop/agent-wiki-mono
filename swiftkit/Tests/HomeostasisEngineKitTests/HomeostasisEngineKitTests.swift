import Testing
@testable import HomeostasisEngineKit

@Suite("HomeostasisEngineKitTests")
struct HomeostasisEngineKitTests {

    @Test("정상 균형 상태 평가 검증")
    func testNormalEquilibrium() {
        let snapshot = HomeostasisEngineKit.TimeSeriesSnapshot(
            mean: 1.20,
            baseline: 1.20,
            complaintRate: 0.001,
            sampleCount: 1000
        )
        let decision = HomeostasisEngineKit.evaluateHomeostasis(snapshot: snapshot)
        #expect(decision.isHealthy)
        #expect(decision.action == .steady)
        #expect(decision.burnRate == 0.0)
    }

    @Test("+20% 이상 지연 시 1% 암세포 격리 하네스 작동 검증")
    func testAnomalyIsolationOnLatencySpike() {
        // 평소 1.2초 -> 1.5초 (+25% 튐)
        let snapshot = HomeostasisEngineKit.TimeSeriesSnapshot(
            mean: 1.50,
            baseline: 1.20,
            complaintRate: 0.01,
            sampleCount: 100
        )
        let decision = HomeostasisEngineKit.evaluateHomeostasis(
            snapshot: snapshot,
            sensitivity: 1.20,
            isolateTargetName: "NoProcessInLoopRule"
        )
        #expect(!decision.isHealthy)
        if case .isolateAnomaly(let target, _) = decision.action {
            #expect(target == "NoProcessInLoopRule")
        } else {
            Issue.record("Expected .isolateAnomaly")
        }
    }

    @Test("컴플레인 비율 3% 초과 시 하네스 작동 검증")
    func testComplaintThresholdBreaker() {
        let snapshot = HomeostasisEngineKit.TimeSeriesSnapshot(
            mean: 0.05,
            baseline: 0.05,
            complaintRate: 0.045, // 4.5%
            sampleCount: 50
        )
        let decision = HomeostasisEngineKit.evaluateHomeostasis(
            snapshot: snapshot,
            complaintThreshold: 0.03,
            isolateTargetName: "SlowRule"
        )
        #expect(!decision.isHealthy)
    }

    // MARK: - Declarative Reconciler Tests

    struct MockDesired: Sendable, Equatable {
        let targetCount: Int
    }

    struct MockActual: Sendable, Equatable, HomeostaticSelfHealing {
        var currentCount: Int
        var isQuarantined: Bool = false

        func toSafeEquilibrium() -> MockActual {
            MockActual(currentCount: 0, isQuarantined: true)
        }
    }

    enum MockAction: Sendable {
        case increment
        case decrement
    }

    enum MockInvariantError: Error, Sendable {
        case negativeCountForbidden
    }

    struct MockReconciler: HomeostaticReconcilable {
        func validateInvariants(actual: MockActual) -> Result<Void, MockInvariantError> {
            if actual.currentCount < 0 {
                return .failure(.negativeCountForbidden)
            }
            return .success(())
        }

        func diff(desired: MockDesired, actual: MockActual) -> [MockAction] {
            if actual.currentCount < desired.targetCount {
                return [.increment]
            } else if actual.currentCount > desired.targetCount {
                return [.decrement]
            }
            return []
        }

        func apply(action: MockAction, to actual: MockActual) async throws -> MockActual {
            var updated = actual
            switch action {
            case .increment:
                updated.currentCount += 1
            case .decrement:
                updated.currentCount -= 1
            }
            return updated
        }
    }

    @Test("목표 상태(Desired)와 현재 상태(Actual) 오차 수렴 검증")
    func testReconciliationConvergence() async {
        let reconciler = MockReconciler()
        let loop = HomeostaticConvergenceLoop(reconciler: reconciler, maxIterations: 10, dampingNanoseconds: 0)

        let initial = MockActual(currentCount: 0)
        let desired = MockDesired(targetCount: 3)

        let verdict = await loop.reconcile(desired: desired, initial: initial)
        #expect(verdict == .converged(finalState: MockActual(currentCount: 3), iterations: 3))
    }

    @Test("이미 평형(Equilibrium) 상태일 때 0회 반복 즉시 수렴 검증")
    func testReconciliationAlreadyEquilibrium() async {
        let reconciler = MockReconciler()
        let loop = HomeostaticConvergenceLoop(reconciler: reconciler, maxIterations: 5, dampingNanoseconds: 0)

        let initial = MockActual(currentCount: 5)
        let desired = MockDesired(targetCount: 5)

        let verdict = await loop.reconcile(desired: desired, initial: initial)
        #expect(verdict == .converged(finalState: MockActual(currentCount: 5), iterations: 0))
    }

    @Test("불변식(Invariant) 위반 시 즉시 중단 및 에러 반환 검증")
    func testReconciliationInvariantViolation() async {
        let reconciler = MockReconciler()
        let loop = HomeostaticConvergenceLoop(reconciler: reconciler, maxIterations: 5, dampingNanoseconds: 0)

        let illegalInitial = MockActual(currentCount: -1)
        let desired = MockDesired(targetCount: 5)

        let verdict = await loop.reconcile(desired: desired, initial: illegalInitial)
        if case .invariantBroken(let reason) = verdict {
            #expect(reason.contains("negativeCountForbidden"))
        } else {
            Issue.record("Expected .invariantBroken")
        }
    }

    @Test("진동 또는 불변식 위반 시 자가 치유(Self-Healing) 안전 모드 격하 검증")
    func testReconciliationWithSelfHealing() async {
        let reconciler = MockReconciler()
        let loop = HomeostaticConvergenceLoop(reconciler: reconciler, maxIterations: 5, dampingNanoseconds: 0)

        let illegalInitial = MockActual(currentCount: -5)
        let desired = MockDesired(targetCount: 10)

        let (verdict, safeState) = await loop.reconcileWithSelfHealing(desired: desired, initial: illegalInitial)
        #expect(verdict == .invariantBroken(reason: "negativeCountForbidden"))
        #expect(safeState == MockActual(currentCount: 0, isQuarantined: true))
    }
}


