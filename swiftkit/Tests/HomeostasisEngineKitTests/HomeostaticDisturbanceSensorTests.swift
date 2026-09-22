import Testing
import Foundation
@testable import HomeostasisEngineKit

@Suite("HomeostaticDisturbanceSensorTests")
struct HomeostaticDisturbanceSensorTests {

    struct MockDesired: Sendable, Equatable {
        var targetCount: Int
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
        case failAction
    }

    enum MockInvariantError: Error, Sendable {
        case negativeCountForbidden
    }

    struct MockReconciler: HomeostaticReconcilable {
        var shouldFailActuator: Bool = false

        func validateInvariants(actual: MockActual) -> Result<Void, MockInvariantError> {
            if actual.currentCount < 0 {
                return .failure(.negativeCountForbidden)
            }
            return .success(())
        }

        func diff(desired: MockDesired, actual: MockActual) -> [MockAction] {
            if shouldFailActuator {
                return [.failAction]
            }
            if actual.currentCount < desired.targetCount {
                return [.increment]
            } else if actual.currentCount > desired.targetCount {
                return [.decrement]
            }
            return []
        }

        func apply(action: MockAction, to actual: MockActual) async throws -> MockActual {
            switch action {
            case .increment:
                var updated = actual
                updated.currentCount += 1
                return updated
            case .decrement:
                var updated = actual
                updated.currentCount -= 1
                return updated
            case .failAction:
                struct ActuatorError: Error {}
                throw ActuatorError()
            }
        }
    }

    @Test("센서 외란 이벤트 발행 시 Reconciler 자동 수렴 트리거 검증")
    func testSensorDisturbanceTriggersReconciliation() async {
        let sensor = PassthroughDisturbanceSensor()
        let reconciler = MockReconciler()
        let initial = MockActual(currentCount: 0)
        let desired = MockDesired(targetCount: 4)

        let harness = HomeostaticSensorHarness(
            sensor: sensor,
            reconciler: reconciler,
            initial: initial,
            desired: desired
        )

        await harness.start()

        // 외란 이벤트 (.fileDrift) 방출
        sensor.emit(.fileDrift(path: "/etc/hosts.d/custom.conf"))

        let arrived = await harness.waitForEventCount(1, timeoutNanoseconds: 2_000_000_000)
        #expect(arrived)

        let finalCount = await harness.currentState.currentCount
        #expect(finalCount == 4)

        let verdict = await harness.lastVerdict
        #expect(verdict == .converged(finalState: MockActual(currentCount: 4), iterations: 4))

        let lastEvent = await harness.lastEvent
        #expect(lastEvent == .fileDrift(path: "/etc/hosts.d/custom.conf"))

        let historyCount = await harness.history.count
        #expect(historyCount == 1)

        await harness.stop()
    }

    @Test("외란 어댑터가 상태 드리프트를 반영하고 수렴하는지 검증")
    func testDisturbanceAdapterWithNetworkState() async {
        let sensor = PassthroughDisturbanceSensor()
        let reconciler = MockReconciler()
        let initial = MockActual(currentCount: 5)
        let desired = MockDesired(targetCount: 2)

        let harness = HomeostaticSensorHarness(
            sensor: sensor,
            reconciler: reconciler,
            initial: initial,
            desired: desired,
            maxIterations: 10,
            disturbanceAdapter: { event, current in
                var updated = current
                if case .networkStateChanged(let isOnline) = event, !isOnline {
                    // 네트워크 오프라인 시 임의 오차 발생 (+3 추가)
                    updated.currentCount += 3
                }
                return updated
            }
        )

        await harness.start()

        // 오프라인 이벤트 발행 -> currentCount가 5 + 3 = 8로 튐 -> desired: 2로 수렴 (6 iterations decrement)
        sensor.emit(.networkStateChanged(isOnline: false))

        let arrived = await harness.waitForEventCount(1, timeoutNanoseconds: 2_000_000_000)
        #expect(arrived)

        let finalState = await harness.currentState
        #expect(finalState.currentCount == 2)

        let verdict = await harness.lastVerdict
        #expect(verdict == .converged(finalState: MockActual(currentCount: 2), iterations: 6))

        await harness.stop()
    }

    @Test("자가 치유(Self-Healing) 안전 모드 연동 검증: 불변식 위반 시 안전 평형 격하")
    func testSelfHealingOnInvariantBroken() async {
        let sensor = PassthroughDisturbanceSensor()
        let reconciler = MockReconciler()
        let initial = MockActual(currentCount: 2)
        let desired = MockDesired(targetCount: 5)

        let harness = HomeostaticSensorHarness(
            sensor: sensor,
            reconciler: reconciler,
            initial: initial,
            desired: desired,
            enableSelfHealing: true,
            disturbanceAdapter: { event, current in
                var updated = current
                if case .fileDrift = event {
                    // 불변식 위반 상태(음수)로 강제 변질
                    updated.currentCount = -10
                }
                return updated
            }
        )

        await harness.start()

        sensor.emit(.fileDrift(path: "/var/log/corrupt.dat"))

        let arrived = await harness.waitForEventCount(1, timeoutNanoseconds: 2_000_000_000)
        #expect(arrived)

        let verdict = await harness.lastVerdict
        if case .invariantBroken(let reason) = verdict {
            #expect(reason.contains("negativeCountForbidden"))
        } else {
            Issue.record("Expected .invariantBroken verdict")
        }

        // Self-Healing으로 안전 평형 (currentCount: 0, isQuarantined: true) 격하 검증
        let finalState = await harness.currentState
        #expect(finalState == MockActual(currentCount: 0, isQuarantined: true))

        await harness.stop()
    }

    @Test("자가 치유 안전 모드 연동 검증: 액추에이터 실패(진동) 시 안전 평형 격하")
    func testSelfHealingOnActuatorFailure() async {
        let sensor = PassthroughDisturbanceSensor()
        let reconciler = MockReconciler(shouldFailActuator: true)
        let initial = MockActual(currentCount: 3)
        let desired = MockDesired(targetCount: 5)

        let harness = HomeostaticSensorHarness(
            sensor: sensor,
            reconciler: reconciler,
            initial: initial,
            desired: desired,
            enableSelfHealing: true
        )

        await harness.start()

        sensor.emit(.heartbeatTick)

        let arrived = await harness.waitForEventCount(1, timeoutNanoseconds: 2_000_000_000)
        #expect(arrived)

        let verdict = await harness.lastVerdict
        if case .oscillationDetected(_, let reason) = verdict {
            #expect(reason.contains("Actuator failure"))
        } else {
            Issue.record("Expected .oscillationDetected verdict")
        }

        let finalState = await harness.currentState
        #expect(finalState == MockActual(currentCount: 0, isQuarantined: true))

        await harness.stop()
    }

    @Test("HeartbeatDisturbanceSensor 주기적 틱 방출 및 하네스 자동 수렴 검증")
    func testHeartbeatSensorPeriodicConvergence() async {
        let heartbeatSensor = HeartbeatDisturbanceSensor(intervalNanoseconds: 20_000_000) // 20ms
        let reconciler = MockReconciler()
        let initial = MockActual(currentCount: 0)
        let desired = MockDesired(targetCount: 3)

        let harness = HomeostaticSensorHarness(
            sensor: heartbeatSensor,
            reconciler: reconciler,
            initial: initial,
            desired: desired
        )

        await harness.start()
        heartbeatSensor.start()

        let arrived = await harness.waitForEventCount(2, timeoutNanoseconds: 2_000_000_000)
        #expect(arrived)

        let finalState = await harness.currentState
        #expect(finalState.currentCount == 3)

        heartbeatSensor.stop()
        await harness.stop()
    }

    @Test("수동 즉시 수렴 트리거 reconcileNow 검증")
    func testManualReconcileNow() async {
        let sensor = PassthroughDisturbanceSensor()
        let reconciler = MockReconciler()
        let initial = MockActual(currentCount: 1)
        let desired = MockDesired(targetCount: 3)

        let harness = HomeostaticSensorHarness(
            sensor: sensor,
            reconciler: reconciler,
            initial: initial,
            desired: desired
        )

        let verdict = await harness.reconcileNow()
        #expect(verdict == .converged(finalState: MockActual(currentCount: 3), iterations: 2))

        let currentState = await harness.currentState
        #expect(currentState.currentCount == 3)
    }

    @Test("자가 치유(Self-Healing) 런타임 활성화/비활성화 토글 검증")
    func testSelfHealingToggle() async {
        let sensor = PassthroughDisturbanceSensor()
        let reconciler = MockReconciler()
        let initial = MockActual(currentCount: 0)
        let desired = MockDesired(targetCount: 5)

        let harness = HomeostaticSensorHarness(
            sensor: sensor,
            reconciler: reconciler,
            initial: initial,
            desired: desired,
            enableSelfHealing: false,
            disturbanceAdapter: { _, current in
                var updated = current
                updated.currentCount = -10 // 불변식 위반 상태
                return updated
            }
        )

        // 1. Self-healing 비활성화 상태에서는 invariantBroken이어도 currentState가 격하되지 않음
        let verdict1 = await harness.handleDisturbance(.heartbeatTick)
        if case .invariantBroken = verdict1 {
            // expected
        } else {
            Issue.record("Expected .invariantBroken")
        }
        let state1 = await harness.currentState
        #expect(state1.currentCount == -10)
        #expect(!state1.isQuarantined)

        // 2. Self-healing 동적 활성화 후 이벤트 발생 시 안전 평형으로 격하
        await harness.setSelfHealingEnabled(true)
        let verdict2 = await harness.handleDisturbance(.heartbeatTick)
        if case .invariantBroken = verdict2 {
            // expected
        } else {
            Issue.record("Expected .invariantBroken")
        }
        let state2 = await harness.currentState
        #expect(state2.currentCount == 0)
        #expect(state2.isQuarantined)

        // 3. Self-healing 동적 비활성화 (actor 격리 해제 경로 검증)
        await harness.setSelfHealingEnabled(false)
        await harness.updateCurrentState(MockActual(currentCount: -5, isQuarantined: false))
        let verdict3 = await harness.handleDisturbance(.heartbeatTick)
        if case .invariantBroken = verdict3 {
            // expected
        } else {
            Issue.record("Expected .invariantBroken")
        }
        let state3 = await harness.currentState
        #expect(state3.currentCount == -10)
        #expect(!state3.isQuarantined)
    }

    @Test("커스텀 외란 이벤트 수신 및 상태/목표 동적 갱신 검증")
    func testCustomDisturbanceAndDynamicStateUpdate() async {
        let sensor = PassthroughDisturbanceSensor()
        let reconciler = MockReconciler()
        let initial = MockActual(currentCount: 1)
        let desired = MockDesired(targetCount: 3)

        let harness = HomeostaticSensorHarness(
            sensor: sensor,
            reconciler: reconciler,
            initial: initial,
            desired: desired,
            maxIterations: 15
        )

        await harness.start()

        // 커스텀 이벤트 방출
        sensor.emit(.custom(name: "quotaExceeded"))
        let arrived = await harness.waitForEventCount(1, timeoutNanoseconds: 2_000_000_000)
        #expect(arrived)

        let stateAfterEvent1 = await harness.currentState
        #expect(stateAfterEvent1.currentCount == 3)

        // 동적으로 목표 상태를 10으로 변경 후 외란 발생
        await harness.updateDesiredState(MockDesired(targetCount: 10))
        sensor.emit(.custom(name: "resourceScaledUp"))

        let arrived2 = await harness.waitForEventCount(2, timeoutNanoseconds: 2_000_000_000)
        #expect(arrived2)

        let stateAfterEvent2 = await harness.currentState
        #expect(stateAfterEvent2.currentCount == 10)

        await harness.stop()
    }
}

