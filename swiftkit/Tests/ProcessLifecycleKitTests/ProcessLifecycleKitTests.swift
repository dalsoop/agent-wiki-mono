import Foundation
import Testing
@testable import ProcessLifecycleKit

@Suite("ProcessLifecycleKit Tests", .serialized)
struct ProcessLifecycleKitTests {

    @Test func signalTrapHandlerRegistration() {
        let trap = ProcessSignalTrap.shared
        trap.resetForTesting()
        defer { trap.resetForTesting() }

        #expect(trap.registeredCount == 0)

        trap.onSignal(name: "seat-leave") { _ in }
        trap.onSignal(name: "statemirror-clean") { _ in }

        #expect(trap.registeredCount == 2)
    }

    @Test func signalTrapHandlerExecution() {
        let trap = ProcessSignalTrap.shared
        trap.resetForTesting()
        defer { trap.resetForTesting() }

        final class FlagBox: @unchecked Sendable {
            var value = false
            var receivedSignal: Int32 = 0
        }
        let box = FlagBox()

        trap.onSignal(name: "test-cleanup") { sig in
            box.value = true
            box.receivedSignal = sig
        }

        // 시그널 핸들러 로직 직접 검증 (exit 방지를 위해 shouldExit: false)
        #expect(!box.value)
        trap.handleSignal(15, exitCode: 0, shouldExit: false)
        #expect(box.value)
        #expect(box.receivedSignal == 15)
    }

    @Test func exitCoordinatorExecution() {
        ProcessExitCoordinator.resetForTesting()
        defer { ProcessExitCoordinator.resetForTesting() }

        final class CounterBox: @unchecked Sendable {
            var count = 0
        }
        let box = CounterBox()

        ProcessExitCoordinator.registerExitHandler {
            box.count += 1
        }
        ProcessExitCoordinator.registerExitHandler {
            box.count += 2
        }

        ProcessExitCoordinator.runHandlers()
        #expect(box.count == 3)
    }
}
