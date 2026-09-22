import Testing
import Foundation
@testable import HomeostasisEngineKit

@Suite("HomeostaticPersistentHarnessTests")
struct HomeostaticPersistentHarnessTests {

    struct MockDesired: Sendable, Equatable {
        var targetCount: Int
    }

    struct MockActual: Sendable, Equatable, Codable, HomeostaticSelfHealing {
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

    actor MockStorage: HomeostaticStateStorage {
        typealias State = MockActual
        private var memoryStore: MockActual?

        init(initialStored: MockActual? = nil) {
            self.memoryStore = initialStored
        }

        func load() async throws -> MockActual? {
            return memoryStore
        }

        func save(_ state: MockActual) async throws {
            self.memoryStore = state
        }

        func currentSaved() -> MockActual? {
            return memoryStore
        }
    }

    @Test("재기동 시 이전 평형 상태 복원 검증 (Zero Data Loss)")
    func testRestoresStateFromStorageOnStart() async {
        let storage = MockStorage(initialStored: MockActual(currentCount: 42))
        let reconciler = MockReconciler()
        let loop = HomeostaticConvergenceLoop(reconciler: reconciler, maxIterations: 5, dampingNanoseconds: 0)
        let sensor = PassthroughDisturbanceSensor()

        let harness = HomeostaticPersistentHarness(
            loop: loop,
            sensor: sensor,
            storage: storage,
            fallbackInitial: MockActual(currentCount: 0),
            initialDesired: MockDesired(targetCount: 42)
        )

        let verdict = await harness.start()
        #expect(verdict == .converged(finalState: MockActual(currentCount: 42), iterations: 0))
        #expect(await harness.currentActual.currentCount == 42)
    }

    @Test("부팅 직후 공백기 드리프트 자동 치유 검증 (Reconcile-on-Launch)")
    func testReconcilesDriftOnStart() async {
        // 꺼져 있는 동안 저장소는 10이었으나 목표는 15로 설정됨
        let storage = MockStorage(initialStored: MockActual(currentCount: 10))
        let reconciler = MockReconciler()
        let loop = HomeostaticConvergenceLoop(reconciler: reconciler, maxIterations: 10, dampingNanoseconds: 0)
        let sensor = PassthroughDisturbanceSensor()

        let harness = HomeostaticPersistentHarness(
            loop: loop,
            sensor: sensor,
            storage: storage,
            fallbackInitial: MockActual(currentCount: 0),
            initialDesired: MockDesired(targetCount: 15)
        )

        let verdict = await harness.start()
        #expect(verdict == .converged(finalState: MockActual(currentCount: 15), iterations: 5))
        #expect(await harness.currentActual.currentCount == 15)
        #expect(await storage.currentSaved()?.currentCount == 15)
    }

    @Test("목표 갱신 시 자동 수렴 및 디스크 영속화 검증")
    func testUpdatesDesiredAndPersists() async {
        let storage = MockStorage(initialStored: MockActual(currentCount: 5))
        let reconciler = MockReconciler()
        let loop = HomeostaticConvergenceLoop(reconciler: reconciler, maxIterations: 10, dampingNanoseconds: 0)
        let sensor = PassthroughDisturbanceSensor()

        let harness = HomeostaticPersistentHarness(
            loop: loop,
            sensor: sensor,
            storage: storage,
            fallbackInitial: MockActual(currentCount: 0),
            initialDesired: MockDesired(targetCount: 5)
        )

        await harness.start()
        #expect(await harness.currentActual.currentCount == 5)

        // 새로운 목표 주입
        let verdict = await harness.updateDesired(MockDesired(targetCount: 8))
        #expect(verdict == .converged(finalState: MockActual(currentCount: 8), iterations: 3))
        #expect(await harness.currentActual.currentCount == 8)
        #expect(await storage.currentSaved()?.currentCount == 8)

        await harness.stop()
    }
}
