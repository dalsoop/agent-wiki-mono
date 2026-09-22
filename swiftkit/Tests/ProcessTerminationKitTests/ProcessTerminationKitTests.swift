import XCTest
import Darwin
@testable import ProcessTerminationKit

final class ProcessTerminationKitTests: XCTestCase {
    func testPermissionCheckCurrentProcess() {
        let myPID = getpid()
        let cap = TerminationPermission.check(pid: myPID)
        XCTAssertEqual(cap, .standard)
    }

    func testPermissionCheckInvalidProcess() {
        let invalidPID: pid_t = 999999
        let cap = TerminationPermission.check(pid: invalidPID)
        XCTAssertEqual(cap, .notFound)
    }

    func testIsAliveCurrentProcess() {
        let myPID = getpid()
        XCTAssertTrue(ProcessTerminator.isAlive(pid: myPID))
    }

    func testIsAliveInvalidProcess() {
        let invalidPID: pid_t = 999999
        XCTAssertFalse(ProcessTerminator.isAlive(pid: invalidPID))
    }

    func testChildProcessTerminationEscalation() async throws {
        // 백그라운드 테스트용 자식 sleep 프로세스 기동
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sleep")
        process.arguments = ["10"]
        try process.run()

        let childPID = process.processIdentifier
        XCTAssertTrue(ProcessTerminator.isAlive(pid: childPID))

        // 종료 엔진 실행
        let result = await ProcessTerminator.terminate(pid: childPID, timeout: 0.5)
        XCTAssertTrue(result == .killed || result == .graceful || result == .alreadyExited)

        // 실제로 죽었는지 확인
        XCTAssertFalse(ProcessTerminator.isAlive(pid: childPID))
    }
}
