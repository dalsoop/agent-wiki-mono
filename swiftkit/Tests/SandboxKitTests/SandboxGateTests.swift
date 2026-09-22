import Foundation
@testable import SandboxKit
import XCTest

final class SandboxGateTests: XCTestCase {
    var tempHome: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("gate-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome, FileManager.default.fileExists(atPath: tempHome.path) {
            try? FileManager.default.removeItem(at: tempHome)
        }
        try super.tearDownWithError()
    }

    func testSandboxGate_AllowsInsideRoom() throws {
        let env = [
            "SANDBOX_ROOM_ID": "room-acme-123",
            "SWIFT_APP_STATE_ROOT": "/tmp/room-acme-123"
        ]
        let allowed = try SandboxGate.check(
            operationName: "발송",
            environment: env,
            strict: true
        )
        XCTAssertTrue(allowed)
    }

    func testSandboxGate_BlocksBareMetalWhenStrict() {
        let bareEnv: [String: String] = [:]
        XCTAssertThrowsError(
            try SandboxGate.check(
                operationName: "결제",
                environment: bareEnv,
                strict: true
            )
        ) { error in
            guard case SandboxGate.GateError.roomSandboxRequired = error else {
                XCTFail("Expected roomSandboxRequired error but got \(error)")
                return
            }
        }
    }

    func testSandboxGate_AutoWrapExecutesInsideSandbox() throws {
        let result = try SandboxGate.autoWrapOrRun(
            tenant: "acme",
            operationName: "자동 래핑 테스트",
            environment: [:]
        ) { ctx in
            (status: "SUCCESS", roomID: ctx.roomID)
        }

        XCTAssertEqual(result.status, "SUCCESS")
        XCTAssertTrue(result.roomID.hasPrefix("room-acme-"))
    }
}
