import XCTest
import Foundation
import LocalizationKit
@testable import AppErrorKit

private enum SampleL10n: String, LocalizationKey {
    case fileNotFound = "error.file_not_found"
    case permissionDenied = "error.permission_denied"
}

private struct TestCustomError: AppError {
    let errorCode: String
    let category: ErrorCategory
    let severity: ErrorSeverity
    let underlyingError: (any Error & Sendable)?
    let context: [String: String]
    let l10nKey: (any LocalizationKey)?

    init(
        errorCode: String,
        category: ErrorCategory,
        severity: ErrorSeverity,
        underlyingError: (any Error & Sendable)? = nil,
        context: [String: String] = [:],
        l10nKey: (any LocalizationKey)? = nil
    ) {
        self.errorCode = errorCode
        self.category = category
        self.severity = severity
        self.underlyingError = underlyingError
        self.context = context
        self.l10nKey = l10nKey
    }
}

final class AppErrorKitTests: XCTestCase {
    func testAppErrorDefaultProperties() {
        let error = TestCustomError(
            errorCode: "STORAGE.FILE_NOT_FOUND",
            category: .system,
            severity: .error
        )

        XCTAssertEqual(error.errorCode, "STORAGE.FILE_NOT_FOUND")
        XCTAssertEqual(error.category, .system)
        XCTAssertEqual(error.severity, .error)
        XCTAssertNil(error.underlyingError)
        XCTAssertTrue(error.context.isEmpty)
        XCTAssertNil(error.l10nKey)
        XCTAssertEqual(error.failureReason, "STORAGE.FILE_NOT_FOUND")
        XCTAssertEqual(error.errorDescription, "STORAGE.FILE_NOT_FOUND")
        XCTAssertEqual(error.description, "[STORAGE.FILE_NOT_FOUND] STORAGE.FILE_NOT_FOUND")
    }

    func testAppErrorWithContext() {
        let error = TestCustomError(
            errorCode: "STORAGE.FILE_NOT_FOUND",
            category: .system,
            severity: .error,
            context: ["path": "/tmp/test.txt"],
            l10nKey: SampleL10n.fileNotFound
        )

        XCTAssertEqual(error.errorCode, "STORAGE.FILE_NOT_FOUND")
        XCTAssertEqual(error.context["path"], "/tmp/test.txt")
        XCTAssertNotNil(error.l10nKey)
    }

    func testAppErrorUserFacingMessageSlotSubstitution() {
        struct MockUnderlying: LocalizedError, Sendable {
            var errorDescription: String? { "Error at %{path}: %{reason}" }
            var recoverySuggestion: String? { "Check %{path}" }
        }
        let error = TestCustomError(
            errorCode: "IO.FAILED",
            category: .system,
            severity: .error,
            underlyingError: MockUnderlying(),
            context: ["path": "/var/data", "reason": "permission denied"]
        )
        XCTAssertEqual(error.userFacingMessage, "Error at /var/data: permission denied")
        XCTAssertEqual(error.userFacingRecoverySuggestion, "Check /var/data")
    }

    func testAppErrorExistential() {
        // PAT가 아니므로 any AppError 컬렉션 저장이 가능해야 함
        let errors: [any AppError] = [
            TestCustomError(errorCode: "NET.TIMEOUT", category: .network, severity: .warning),
            TestCustomError(errorCode: "AUTH.DENIED", category: .permission, severity: .critical),
        ]

        XCTAssertEqual(errors.count, 2)
        XCTAssertEqual(errors[0].errorCode, "NET.TIMEOUT")
        XCTAssertEqual(errors[1].severity, .critical)
    }

    func testSwift6SendableConcurrency() async {
        let error: any AppError = TestCustomError(
            errorCode: "ASYNC.FAILED",
            category: .business,
            severity: .error
        )

        // Task 경계를 넘어 Sendable로 안전하게 전달되는지 확인
        let capturedCode = await Task { () -> String in
            return error.errorCode
        }.value

        XCTAssertEqual(capturedCode, "ASYNC.FAILED")
    }

    func testSeverityComparison() {
        XCTAssertTrue(ErrorSeverity.info < ErrorSeverity.warning)
        XCTAssertTrue(ErrorSeverity.warning < ErrorSeverity.error)
        XCTAssertTrue(ErrorSeverity.error < ErrorSeverity.critical)
    }

    func testAllCategoriesExist() {
        let expected: [ErrorCategory] = [
            .system, .fileSystem, .network, .business, .validation, .permission, .cancelled, .unknown
        ]
        XCTAssertEqual(Set(ErrorCategory.allCases), Set(expected))
    }
}
