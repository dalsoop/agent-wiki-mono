import XCTest
import Foundation
@testable import SingleInstanceKit

final class SingleInstanceReadVerbTests: XCTestCase {

    private var tempDirectory: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("single-instance-read-verbs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        SingleInstanceCLI.releaseAll()
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    // MARK: - Read Verbs Bypass Guard Tests

    func testReadVerbsBypassGuardWhenLockIsHeld() throws {
        let name = "agent-worker-orchestrator"
        let scope = SingleInstanceCLI.Scope.host(directory: tempDirectory)

        // 다른 프로세스 또는 선행 인스턴스가 이미 락을 점유한 상황 연출
        guard let heldToken = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            XCTFail("선행 락 획득 실패")
            return
        }
        XCTAssertTrue(heldToken.isHeld)

        // 1. jobs 명령 바이패스 검증
        var exitCalled = false
        var stderrMessages: [String] = []
        let tokenJobs = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: [name, "jobs"],
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { _ in exitCalled = true }
        )
        XCTAssertNil(tokenJobs, "조회 동사는 락을 잡지 않고 nil을 반환해야 함")
        XCTAssertFalse(exitCalled, "조회 동사 실행 시 프로세스가 종료되면 안 됨")
        XCTAssertTrue(stderrMessages.isEmpty, "조회 동사 실행 시 거절 메시지가 출력되면 안 됨")

        // 2. list 명령 바이패스 검증
        let tokenList = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: [name, "list"],
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { _ in exitCalled = true }
        )
        XCTAssertNil(tokenList)
        XCTAssertFalse(exitCalled)

        // 3. report x 명령 바이패스 검증
        let tokenReport = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: [name, "report", "x"],
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { _ in exitCalled = true }
        )
        XCTAssertNil(tokenReport)
        XCTAssertFalse(exitCalled)

        // 4. 함대 공통 조회 동사 전수 바이패스 검증
        let readVerbs = [
            "list", "show", "get", "search", "find", "query", "view",
            "inspect", "report", "tail", "log", "logs", "history",
            "diff", "ledger", "jobs", "levels", "matrix", "spec"
        ]
        for verb in readVerbs {
            var verbExitCalled = false
            var verbStderr: [String] = []
            let token = SingleInstanceCLI.guardStandard(
                name: name,
                scope: scope,
                arguments: [name, verb],
                stderrWriter: { verbStderr.append($0) },
                exitHandler: { _ in verbExitCalled = true }
            )
            XCTAssertNil(token, "동사 '\(verb)'는 가드를 바이패스(nil)해야 함")
            XCTAssertFalse(verbExitCalled, "동사 '\(verb)' 호출 시 exitHandler가 호출되면 안 됨")
            XCTAssertTrue(verbStderr.isEmpty, "동사 '\(verb)' 호출 시 에러 메시지가 출력되면 안 됨")
        }

        // 5. autoGuard 바이패스 검증
        let autoToken = SingleInstanceCLI.autoGuard(
            scope: scope,
            arguments: ["/usr/local/bin/\(name)", "jobs", "--json"],
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { _ in exitCalled = true }
        )
        XCTAssertNil(autoToken)
        XCTAssertFalse(exitCalled)

        heldToken.release()
    }

    // MARK: - State Changing Verbs Rejection & Exit Code 75 Tests

    func testRunQueuedRejectedWithExit75WhenLockIsHeld() throws {
        let name = "agent-worker-orchestrator"
        let scope = SingleInstanceCLI.Scope.host(directory: tempDirectory)

        guard let heldToken = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            XCTFail("선행 락 획득 실패")
            return
        }
        XCTAssertTrue(heldToken.isHeld)

        // guardStandard로 run-queued 실행 시 거절 및 exit 75 확인
        var exitCode: Int32?
        var stderrMessages: [String] = []
        let result = SingleInstanceCLI.guardStandard(
            name: name,
            scope: scope,
            arguments: [name, "run-queued"],
            stderrWriter: { stderrMessages.append($0) },
            exitHandler: { exitCode = $0 }
        )

        XCTAssertNil(result, "거절 시 가드 토큰은 nil이어야 함")
        XCTAssertEqual(exitCode, 75, "중복 실행 거절 시 종료 코드는 75(EX_TEMPFAIL)여야 함")
        XCTAssertEqual(stderrMessages.count, 1)
        guard let message = stderrMessages.first else {
            XCTFail("거절 메시지가 출력되지 않음")
            return
        }
        XCTAssertTrue(
            message.contains("(exit 75 — 같은 범위에서 다른 인스턴스가 실행 중)"),
            "거절 메시지 끝에 지정된 안내 문구가 포함되어야 함. 실제 메시지: \(message)"
        )

        // autoGuard로 run-queued 실행 시에도 동일하게 거절 및 exit 75 확인
        var autoExitCode: Int32?
        var autoStderrMessages: [String] = []
        let autoResult = SingleInstanceCLI.autoGuard(
            scope: scope,
            arguments: ["/opt/bin/\(name)", "run-queued"],
            stderrWriter: { autoStderrMessages.append($0) },
            exitHandler: { autoExitCode = $0 }
        )

        XCTAssertNil(autoResult)
        XCTAssertEqual(autoExitCode, 75)
        XCTAssertEqual(autoStderrMessages.count, 1)
        XCTAssertTrue(
            autoStderrMessages.first?.contains("(exit 75 — 같은 범위에서 다른 인스턴스가 실행 중)") == true
        )

        // 상태 변경 동사들(run, dispatch, apply, ship, add, remove, set) 역시 거절 확인
        let stateVerbs = ["run", "dispatch", "apply", "ship", "add", "remove", "set"]
        for verb in stateVerbs {
            var stateExitCode: Int32?
            let stateToken = SingleInstanceCLI.guardStandard(
                name: name,
                scope: scope,
                arguments: [name, verb],
                stderrWriter: { _ in },
                exitHandler: { stateExitCode = $0 }
            )
            XCTAssertNil(stateToken)
            XCTAssertEqual(stateExitCode, 75, "상태 변경 동사 '\(verb)'는 중복 실행 시 75로 거절되어야 함")
        }

        heldToken.release()
    }

    // MARK: - State Changing Verbs With Help Flag Bypasses Tests

    func testStateChangingCommandsWithHelpFlagBypass() throws {
        let name = "agent-worker-orchestrator"
        let scope = SingleInstanceCLI.Scope.host(directory: tempDirectory)

        guard let heldToken = SingleInstanceCLI.acquire(name: name, scope: scope) else {
            XCTFail("선행 락 획득 실패")
            return
        }

        let helpArgsList: [[String]] = [
            [name, "run-queued", "--help"],
            [name, "run-queued", "-h"],
            [name, "dispatch", "--help"],
            [name, "apply", "-h"],
            [name, "--help", "ship"]
        ]

        for args in helpArgsList {
            var exitCalled = false
            var stderrMessages: [String] = []
            let token = SingleInstanceCLI.guardStandard(
                name: name,
                scope: scope,
                arguments: args,
                stderrWriter: { stderrMessages.append($0) },
                exitHandler: { _ in exitCalled = true }
            )
            XCTAssertNil(token, "\(args) 실행은 바이패스(nil)되어야 함")
            XCTAssertFalse(exitCalled, "\(args) 실행 시 exitHandler가 호출되면 안 됨")
            XCTAssertTrue(stderrMessages.isEmpty, "\(args) 실행 시 stderr가 비어 있어야 함")
        }

        heldToken.release()
    }
}
