import XCTest
@testable import PrivilegedHelperKit

final class PrivilegedHelperLifecycleTests: XCTestCase {
    func testPingOKNeverReplaces() {
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(
                pingOK: true,
                status: .notFound,
                occupied: true,
                waitAlreadyTried: true
            ),
            .register
        )
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(pingOK: true, status: .notRegistered),
            .register
        )
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(pingOK: true, status: .enabled),
            .done
        )
    }

    func testEnabledWaitsBeforeReplace() {
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(
                pingOK: false,
                status: .enabled,
                occupied: true
            ),
            .waitAndPing
        )
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(
                pingOK: false,
                status: .enabled,
                occupied: true,
                waitAlreadyTried: true
            ),
            .replaceStale
        )
    }

    func testZombieNotFoundIsReplace() {
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(pingOK: false, status: .notFound),
            .missingBundle
        )
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(
                pingOK: false,
                status: .notFound,
                occupied: true
            ),
            .replaceStale
        )
    }

    func testNotRegisteredOccupiedIsReplace() {
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(pingOK: false, status: .notRegistered),
            .register
        )
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(
                pingOK: false,
                status: .notRegistered,
                occupied: true
            ),
            .replaceStale
        )
    }

    func testRequiresApproval() {
        XCTAssertEqual(
            PrivilegedHelperLifecycle.nextStep(pingOK: false, status: .requiresApproval),
            .approveThenRegister
        )
    }
}

final class MockPrivilegedHelperDaemon: PrivilegedHelperControlling, @unchecked Sendable {
    var status: PrivilegedHelperStatus
    var registerCalls = 0
    var unregisterCalls = 0
    var registerError: Error?
    /// launchd 잔재: unregister 가 상태를 바꾸지 못함.
    var unregisterNoops = false

    init(status: PrivilegedHelperStatus) {
        self.status = status
    }

    func register() throws {
        registerCalls += 1
        if let registerError { throw registerError }
        status = .enabled
    }

    func unregister() async throws {
        unregisterCalls += 1
        if unregisterNoops { return }
        status = .notRegistered
    }
}

struct DummyRegisterError: Error {}

final class PrivilegedHelperReplacerTests: XCTestCase {
    func testReplaceUnloadsThenRegisters() async throws {
        let daemon = MockPrivilegedHelperDaemon(status: .enabled)
        let sut = PrivilegedHelperReplacer(unloadWaitNanoseconds: 1, unloadAttempts: 1)
        try await sut.replace(daemon)
        XCTAssertEqual(daemon.unregisterCalls, 1)
        XCTAssertEqual(daemon.registerCalls, 1)
        XCTAssertEqual(daemon.status, .enabled)
    }

    func testUnloadOnlyUnregisters() async throws {
        let daemon = MockPrivilegedHelperDaemon(status: .enabled)
        let sut = PrivilegedHelperReplacer(unloadWaitNanoseconds: 1, unloadAttempts: 1)
        try await sut.unload(daemon)
        XCTAssertEqual(daemon.unregisterCalls, 1)
        XCTAssertEqual(daemon.registerCalls, 0)
        XCTAssertEqual(daemon.status, .notRegistered)
    }

    func testReplaceThrowsWhenStillEnabled() async {
        let daemon = MockPrivilegedHelperDaemon(status: .enabled)
        daemon.unregisterNoops = true
        daemon.registerError = DummyRegisterError()
        let sut = PrivilegedHelperReplacer(unloadWaitNanoseconds: 1, unloadAttempts: 1)
        do {
            try await sut.replace(daemon)
            XCTFail("expected stillEnabledAfterReplace")
        } catch let error as PrivilegedHelperError {
            XCTAssertEqual(error, .stillEnabledAfterReplace)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(daemon.unregisterCalls, 1)
        XCTAssertEqual(daemon.registerCalls, 1)
    }
}
