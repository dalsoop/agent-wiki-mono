import os
import XCTest
import AppErrorKit
import LocalizationKit
@testable import AgentCLIKit

final class OutputBox: Sendable {
    private struct State: Sendable {
        var text: String = ""
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    var text: String {
        get {
            state.withLock { $0.text }
        }
        set {
            state.withLock { $0.text = newValue }
        }
    }
}

final class UniversalCLIErrorHandlerTests: XCTestCase {

    struct MockDomainError: AppError {
        let errorCode: String
        let category: ErrorCategory
        let severity: ErrorSeverity
        let context: [String: String]
        let message: String
        let suggestion: String?
        let underlying: (any Error & Sendable)?

        init(
            errorCode: String = "STORAGE.FILE_NOT_FOUND",
            category: ErrorCategory = .fileSystem,
            severity: ErrorSeverity = .error,
            context: [String: String] = ["path": "/tmp/test.json"],
            message: String = "요청한 파일을 찾을 수 없습니다.",
            suggestion: String? = "경로를 확인하거나 파일을 재생성하세요.",
            underlying: (any Error & Sendable)? = nil
        ) {
            self.errorCode = errorCode
            self.category = category
            self.severity = severity
            self.context = context
            self.message = message
            self.suggestion = suggestion
            self.underlying = underlying
        }

        var underlyingError: (any Error & Sendable)? { underlying }
        func userFacingMessage(using manager: LocalizationManager?) -> String { message }
        func userFacingRecoverySuggestion(using manager: LocalizationManager?) -> String? { suggestion }
    }

    // MARK: - Normal Operation Tests

    func testRunWithUniversalErrorSuccessReturnsOk() {
        let code = runWithUniversalError(arguments: ["my-cli", "run"], exitOnCatch: false) {
            // No error
        }
        XCTAssertEqual(code, POSIXSysexits.ok)
    }

    func testRunWithUniversalErrorAsyncSuccessReturnsOk() async {
        let code = await runWithUniversalError(arguments: ["my-cli", "run"], exitOnCatch: false) {
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        XCTAssertEqual(code, POSIXSysexits.ok)
    }

    // MARK: - RFC 9457 JSON Output Tests

    func testJSONFlagOutputsRFC9457CompliantJSON() {
        AppErrorReporter.withExpectedError {
            let mockError = MockDomainError(
                errorCode: "CONFIG.INVALID_SYNTAX",
                category: .validation,
                severity: .error,
                context: ["line": "42", "file": "config.yaml"],
                message: "설정 파일 구문이 올바르지 않습니다.",
                suggestion: "YAML 문법 오류를 교정하세요."
            )

            let box = OutputBox()
            let code = runWithUniversalError(
                arguments: ["my-cli", "validate", "--json"],
                exitOnCatch: false,
                outputDestination: .custom { box.text = $0 }
            ) {
                throw mockError
            }

            XCTAssertEqual(code, POSIXSysexits.usage) // EX_USAGE (64)
            let capturedOutput = box.text
            XCTAssertFalse(capturedOutput.isEmpty)

            // RFC 9457 필수 규격 필드 디코딩 검증
            guard let data = capturedOutput.data(using: .utf8) else {
                return XCTFail("Output is not UTF-8")
            }

            do {
                let details = try JSONDecoder().decode(RFC9457ProblemDetails.self, from: data)
                XCTAssertEqual(details.type, "urn:problem:config.invalid-syntax")
                XCTAssertEqual(details.title, "CONFIG.INVALID_SYNTAX")
                XCTAssertEqual(details.status, Int(POSIXSysexits.usage))
                XCTAssertEqual(details.detail, "설정 파일 구문이 올바르지 않습니다.")
                XCTAssertTrue(details.instance.hasPrefix("urn:uuid:"))
                XCTAssertEqual(details.code, "CONFIG.INVALID_SYNTAX")
                XCTAssertEqual(details.category, "validation")
                XCTAssertEqual(details.severity, "error")
                XCTAssertEqual(details.recoverySuggestion, "YAML 문법 오류를 교정하세요.")
                XCTAssertEqual(details.context["line"], "42")
                XCTAssertEqual(details.context["file"], "config.yaml")
            } catch {
                XCTFail("RFC 9457 JSON 파싱 실패: \(error), raw JSON: \(capturedOutput)")
            }
        }
    }

    // MARK: - ANSI Box & TTY Formatting Tests

    func testDiagnosticBoxFormattingWithColors() {
        let mockError = MockDomainError(
            errorCode: "AUTH.TOKEN_EXPIRED",
            category: .permission,
            severity: .error,
            context: ["user_id": "usr_9981"],
            message: "세션 토큰이 만료되었습니다.",
            suggestion: "agent-login 명령으로 다시 로그인하세요."
        )

        let formatted = UniversalCLIErrorHandler.formatDiagnosticBox(for: mockError, useColor: true)

        XCTAssertTrue(formatted.contains("AUTH.TOKEN_EXPIRED"))
        XCTAssertTrue(formatted.contains("PERMISSION"))
        XCTAssertTrue(formatted.contains("Message: "))
        XCTAssertTrue(formatted.contains("세션 토큰이 만료되었습니다."))
        XCTAssertTrue(formatted.contains("[Action] Suggested Action:"))
        XCTAssertTrue(formatted.contains("agent-login 명령으로 다시 로그인하세요."))
        XCTAssertTrue(formatted.contains("Metadata:"))
        XCTAssertTrue(formatted.contains("user_id: usr_9981"))
        XCTAssertTrue(formatted.contains("\u{001B}[")) // ANSI escape codes included
    }

    func testDiagnosticBoxFormattingPlainWithoutColors() {
        let mockError = MockDomainError(
            errorCode: "NETWORK.CONNECTION_LOST",
            category: .network,
            severity: .warning,
            context: ["endpoint": "https://api.gujo.kr"],
            message: "네트워크 연결이 끊겼습니다.",
            suggestion: "인터넷 연결 상태를 점검하세요."
        )

        let formatted = UniversalCLIErrorHandler.formatDiagnosticBox(for: mockError, useColor: false)

        XCTAssertTrue(formatted.contains("NETWORK.CONNECTION_LOST"))
        XCTAssertTrue(formatted.contains("Message: "))
        XCTAssertTrue(formatted.contains("네트워크 연결이 끊겼습니다."))
        XCTAssertTrue(formatted.contains("[Action] Suggested Action:"))
        XCTAssertFalse(formatted.contains("\u{001B}[")) // No ANSI escape codes
    }

    // MARK: - Sysexits Code Mapping Tests

    func testSysexitsCodeMappingByCategory() {
        // validation -> EX_USAGE (64)
        let valErr = MockDomainError(category: .validation)
        XCTAssertEqual(UniversalCLIErrorHandler.sysexitsCode(for: valErr), POSIXSysexits.usage)

        // permission -> EX_NOPERM (77)
        let permErr = MockDomainError(category: .permission)
        XCTAssertEqual(UniversalCLIErrorHandler.sysexitsCode(for: permErr), POSIXSysexits.noPerm)

        // fileSystem -> EX_IOERR (74)
        let fsErr = MockDomainError(category: .fileSystem)
        XCTAssertEqual(UniversalCLIErrorHandler.sysexitsCode(for: fsErr), POSIXSysexits.ioErr)

        // network -> EX_UNAVAILABLE (69)
        let netErr = MockDomainError(category: .network)
        XCTAssertEqual(UniversalCLIErrorHandler.sysexitsCode(for: netErr), POSIXSysexits.unavailable)

        // system -> EX_OSERR (71)
        let sysErr = MockDomainError(category: .system)
        XCTAssertEqual(UniversalCLIErrorHandler.sysexitsCode(for: sysErr), POSIXSysexits.osErr)

        // business -> EX_SOFTWARE (70)
        let bizErr = MockDomainError(category: .business)
        XCTAssertEqual(UniversalCLIErrorHandler.sysexitsCode(for: bizErr), POSIXSysexits.software)

        // cancelled -> 130
        let cancelErr = MockDomainError(category: .cancelled)
        XCTAssertEqual(UniversalCLIErrorHandler.sysexitsCode(for: cancelErr), 130)

        // unknown -> EX_SOFTWARE (70)
        let unkErr = MockDomainError(category: .unknown)
        XCTAssertEqual(UniversalCLIErrorHandler.sysexitsCode(for: unkErr), POSIXSysexits.software)
    }

    // MARK: - The Invisible Hook: Untyped Swift.Error Fallback Tests

    func testInvisibleHookCatchesUntypedErrorAndFormatsProperly() {
        AppErrorReporter.withExpectedError {
            enum RawSampleError: Error, LocalizedError {
                case fileMissing

                var errorDescription: String? {
                    "지정된 대상 파일을 찾을 수 없습니다."
                }
            }

            let box = OutputBox()
            let code = runWithUniversalError(
                arguments: ["app", "--json"],
                exitOnCatch: false,
                outputDestination: .custom { box.text = $0 }
            ) {
                throw RawSampleError.fileMissing
            }

            XCTAssertTrue(code > 0)
            let output = box.text
            XCTAssertTrue(output.contains("\"detail\" : \"지정된 대상 파일을 찾을 수 없습니다.\"") || output.contains("지정된 대상 파일을 찾을 수 없습니다."))
        }
    }

    func testExitOnCatchInvokesExitHandlerInsteadOfDarwinExit() {
        AppErrorReporter.withExpectedError {
            let mockError = MockDomainError(
                errorCode: "CONFIG.INVALID_SYNTAX",
                category: .validation,
                severity: .error
            )

            let box = OutputBox()
            let capturedExit = OSAllocatedUnfairLock<Int32?>(initialState: nil)
            let code = runWithUniversalError(
                arguments: ["my-cli", "validate"],
                exitOnCatch: true,
                outputDestination: .custom { box.text = $0 },
                exitHandler: { value in capturedExit.withLock { $0 = value } }
            ) {
                throw mockError
            }

            XCTAssertEqual(capturedExit.withLock { $0 }, POSIXSysexits.usage)
            XCTAssertEqual(code, POSIXSysexits.usage)
            XCTAssertFalse(box.text.isEmpty)
        }
    }

    func testInvisibleHookCatchesCocoaError() {
        AppErrorReporter.withExpectedError {
            let cocoaNotFound = CocoaError(.fileNoSuchFile)

            let box = OutputBox()
            let code = runWithUniversalError(
                arguments: ["app", "--json"],
                exitOnCatch: false,
                outputDestination: .custom { box.text = $0 }
            ) {
                throw cocoaNotFound
            }

            XCTAssertEqual(code, POSIXSysexits.ioErr) // 74
            let output = box.text
            XCTAssertTrue(output.contains("COCOA.FILE_NOT_FOUND"))
            XCTAssertTrue(output.contains("\"status\" : 74"))
        }
    }
}
