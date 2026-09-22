import XCTest
import Foundation
import LocalizationKit
@testable import AppErrorKit

private enum MockL10n: String, LocalizationKey {
    case fileNotFound = "mock.error.file_not_found"
    case missingKey = "mock.error.nonexistent_key"
}

private struct MockAppError: AppError {
    let errorCode: String
    let category: ErrorCategory
    let severity: ErrorSeverity
    let underlyingError: (any Error & Sendable)?
    let context: [String: String]
    let l10nKey: (any LocalizationKey)?

    init(
        errorCode: String = "STORAGE.FILE_NOT_FOUND",
        category: ErrorCategory = .system,
        severity: ErrorSeverity = .error,
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

final class AppErrorLocalizationTests: XCTestCase {

    // MARK: - Slot Substitution Tests

    func testSubstituteSlots_NamedPlaceholders() {
        let template = "파일 %{path}를 열 수 없습니다: %{reason}"
        let context = ["path": "/tmp/test.txt", "reason": "권한 없음"]
        let result = AppErrorLocalization.substituteSlots(into: template, context: context)
        XCTAssertEqual(result, "파일 /tmp/test.txt를 열 수 없습니다: 권한 없음")
    }

    func testSubstituteSlots_PreservesMissingNamedSlotsAndLiteralPercent() {
        let template = "진행률: 100%% 완료. 파일: %{path}, 기타: %{unknown}"
        let context = ["path": "/tmp/a"]
        let result = AppErrorLocalization.substituteSlots(into: template, context: context)
        XCTAssertEqual(result, "진행률: 100% 완료. 파일: /tmp/a, 기타: %{unknown}")
    }

    func testSubstituteSlots_PositionalSlotsViaCLILocalization() {
        let template = "연결 실패: %@ (재시도: %d회)"
        let result = AppErrorLocalization.substituteSlots(
            into: template,
            context: [:],
            positionalValues: ["타임아웃", 3]
        )
        XCTAssertEqual(result, "연결 실패: 타임아웃 (재시도: 3회)")
    }

    func testSubstituteSlots_MixedNamedAndPositional() {
        let template = "경로 '%{path}'에서 오류 발생: %@ (코드: %d)"
        let context = ["path": "/var/log"]
        let result = AppErrorLocalization.substituteSlots(
            into: template,
            context: context,
            positionalValues: ["권한 거부됨", 13]
        )
        XCTAssertEqual(result, "경로 '/var/log'에서 오류 발생: 권한 거부됨 (코드: 13)")
    }

    func testSubstituteSlots_IndexedContextValues() {
        let template = "인자 1: %@, 인자 2: %@"
        let context = ["1": "첫번째", "2": "두번째"]
        let result = AppErrorLocalization.substituteSlots(into: template, context: context)
        XCTAssertEqual(result, "인자 1: 첫번째, 인자 2: 두번째")
    }

    // MARK: - Fallback Mechanism Tests (CLI / Core)

    func testCLIMessage_FallbackToDefaultMessageWithSubstitution() {
        let error = MockAppError(
            errorCode: "IO.READ_FAILED",
            context: ["file": "config.json"],
            l10nKey: MockL10n.missingKey
        )

        let message = AppErrorLocalization.renderCLIMessage(
            errorCode: error.errorCode,
            l10nKey: error.l10nKey,
            defaultMessage: "설정 파일 '%{file}'을 읽을 수 없습니다.",
            context: error.context
        )

        XCTAssertEqual(message, "설정 파일 'config.json'을 읽을 수 없습니다.")
    }

    func testCLIMessage_FallbackToUnderlyingError() {
        struct Underlying: LocalizedError, Sendable {
            var errorDescription: String? { "디스크 공간 부족" }
        }

        let error = MockAppError(
            errorCode: "DISK.FULL",
            underlyingError: Underlying(),
            l10nKey: nil
        )

        let message = AppErrorLocalization.renderCLIMessage(for: error)
        XCTAssertEqual(message, "디스크 공간 부족")
    }

    func testCLIMessage_FallbackToErrorCode() {
        let error = MockAppError(
            errorCode: "KERNEL.PANIC",
            underlyingError: nil,
            l10nKey: MockL10n.missingKey
        )

        // 번역도 없고 defaultMessage도 없고 underlyingError도 없을 때
        let message = AppErrorLocalization.renderCLIMessage(for: error)
        XCTAssertEqual(message, "KERNEL.PANIC")
    }

    func testCLIRecoverySuggestion_Fallback() {
        let error = MockAppError(
            errorCode: "AUTH.EXPIRED",
            context: ["service": "GujoCloud"],
            l10nKey: MockL10n.missingKey
        )

        let suggestion = AppErrorLocalization.renderCLIRecoverySuggestion(
            l10nKey: error.l10nKey,
            defaultSuggestion: "%{service} 계정으로 다시 로그인하세요.",
            context: error.context
        )
        XCTAssertEqual(suggestion, "GujoCloud 계정으로 다시 로그인하세요.")

        let nilSuggestion = AppErrorLocalization.renderCLIRecoverySuggestion(for: error)
        XCTAssertNil(nilSuggestion)
    }

    // MARK: - GUI Rendering Tests

    @MainActor
    func testGUIRenderingWithFallback() {
        let bundle = Bundle(for: Self.self)
        let manager = LocalizationManager(baseBundle: bundle)

        let error = MockAppError(
            errorCode: "GUI.RENDER_FAIL",
            context: ["view": "MainView"],
            l10nKey: MockL10n.missingKey
        )

        let message = AppErrorLocalization.renderGUIMessage(
            errorCode: error.errorCode,
            l10nKey: error.l10nKey,
            defaultMessage: "뷰 %{view}를 렌더링하지 못했습니다.",
            context: error.context,
            using: manager
        )
        XCTAssertEqual(message, "뷰 MainView를 렌더링하지 못했습니다.")

        let info = AppErrorLocalization.renderGUI(for: error, using: manager)
        XCTAssertEqual(info.errorCode, "GUI.RENDER_FAIL")
        XCTAssertEqual(info.message, "GUI.RENDER_FAIL")
        XCTAssertNil(info.recoverySuggestion)
    }

    // MARK: - Combined LocalizedErrorInfo & AppError Convenience Tests

    func testCombinedLocalizedErrorInfo() {
        let info = AppErrorLocalization.LocalizedErrorInfo(
            errorCode: "NET.UNAVAILABLE",
            message: "네트워크에 연결할 수 없습니다.",
            recoverySuggestion: "Wi-Fi 상태를 확인하세요."
        )

        XCTAssertEqual(info.errorCode, "NET.UNAVAILABLE")
        XCTAssertEqual(info.message, "네트워크에 연결할 수 없습니다.")
        XCTAssertEqual(info.recoverySuggestion, "Wi-Fi 상태를 확인하세요.")
        XCTAssertEqual(info.description, "[NET.UNAVAILABLE] 네트워크에 연결할 수 없습니다. (Recovery: Wi-Fi 상태를 확인하세요.)")
    }

    func testAppErrorExtensionConvenience() {
        let error = MockAppError(
            errorCode: "STORAGE.QUOTA_EXCEEDED",
            context: ["user": "jeonghan"]
        )

        let cliInfo = error.localizedCLIInfo()
        XCTAssertEqual(cliInfo.errorCode, "STORAGE.QUOTA_EXCEEDED")
        XCTAssertEqual(cliInfo.message, "STORAGE.QUOTA_EXCEEDED")
        XCTAssertNil(cliInfo.recoverySuggestion)
    }
}
