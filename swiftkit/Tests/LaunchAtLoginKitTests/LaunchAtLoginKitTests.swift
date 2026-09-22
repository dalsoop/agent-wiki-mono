import XCTest
@testable import LaunchAtLoginKit

final class LaunchAtLoginKitTests: XCTestCase {
    /// 실제 SMAppService 를 건드리지 않는 목 — 등록 상태/호출 횟수만 추적.
    final class MockRegistrar: LoginItemRegistering, @unchecked Sendable {
        var registered: Bool
        var registerCalls = 0
        var unregisterCalls = 0
        var registerError: Error?
        init(registered: Bool = false) { self.registered = registered }
        var isRegistered: Bool { registered }
        func register() throws {
            registerCalls += 1
            if let registerError { throw registerError }
            registered = true
        }
        func unregister() throws {
            unregisterCalls += 1
            registered = false
        }
    }

    struct DummyError: Error {}

    func testEnableRegisters() {
        let mock = MockRegistrar()
        let sut = LaunchAtLogin(registrar: mock)
        XCTAssertFalse(sut.isEnabled)
        XCTAssertTrue(sut.setEnabled(true))
        XCTAssertTrue(sut.isEnabled)
        XCTAssertEqual(mock.registerCalls, 1)
    }

    func testDisableUnregisters() {
        let mock = MockRegistrar(registered: true)
        let sut = LaunchAtLogin(registrar: mock)
        XCTAssertFalse(sut.setEnabled(false))
        XCTAssertFalse(sut.isEnabled)
        XCTAssertEqual(mock.unregisterCalls, 1)
    }

    func testEnableIsIdempotent() {
        let mock = MockRegistrar(registered: true)
        let sut = LaunchAtLogin(registrar: mock)
        _ = sut.setEnabled(true) // 이미 등록 → register 재호출 안 함
        XCTAssertEqual(mock.registerCalls, 0)
    }

    func testToggleFlips() {
        let mock = MockRegistrar()
        let sut = LaunchAtLogin(registrar: mock)
        XCTAssertTrue(sut.toggle())  // off → on
        XCTAssertFalse(sut.toggle()) // on → off
    }

    func testRegisterFailureKeepsStateOff() {
        let mock = MockRegistrar()
        mock.registerError = DummyError()
        let sut = LaunchAtLogin(registrar: mock)
        XCTAssertFalse(sut.setEnabled(true)) // 실패 → 여전히 미등록
        XCTAssertFalse(sut.isEnabled)
    }
}
