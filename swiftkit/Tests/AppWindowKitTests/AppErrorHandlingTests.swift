#if canImport(AppKit) && canImport(SwiftUI)
import XCTest
import SwiftUI
import AppErrorKit
import LocalizationKit
import NoticeBannerUIKit
@testable import AppWindowKit

final class AppErrorHandlingTests: XCTestCase {

    // MARK: - Silent Error Filtering Tests

    func testSilentErrorDetection() {
        // 1. CancellationError 자동 감지
        let cancellation = CancellationError()
        let anyFromCancellation = cancellation.asAnyAppError()
        XCTAssertTrue(anyFromCancellation.isSilent)
        XCTAssertEqual(anyFromCancellation.category, .cancelled)

        // 2. 카테고리가 .cancelled 인 경우
        let cancelledAppError = AnyAppError(
            errorCode: "SYNC.CANCELLED",
            category: .cancelled,
            severity: .info
        )
        XCTAssertTrue(cancelledAppError.isSilent)

        // 3. withSilent 체이닝
        let silentExplicit = AnyAppError(errorCode: "BG_TASK.STOPPED")
            .withSilent(true)
        XCTAssertTrue(silentExplicit.isSilent)

        // 4. 일반 오류는 isSilent false
        let normalError = AnyAppError(
            errorCode: "NETWORK.TIMEOUT",
            category: .network,
            severity: .error
        )
        XCTAssertFalse(normalError.isSilent)
    }

    // MARK: - ViewModifier Application Tests

    @MainActor
    func testAppErrorHandlingModifierApplication() {
        var dummyError: AnyAppError? = AnyAppError(
            errorCode: "TEST.ERROR",
            category: .system,
            severity: .error
        )
        let binding = Binding(get: { dummyError }, set: { dummyError = $0 })

        var recoveryInvoked = false
        let view = Text("Main Content")
            .appErrorHandling(
                error: binding,
                actionTitle: "다시 시도",
                onRecovery: { _ in
                    recoveryInvoked = true
                }
            )

        let typeName = String(describing: type(of: view))
        XCTAssertTrue(typeName.contains("AppErrorHandlingModifier"), typeName)
        XCTAssertFalse(recoveryInvoked)
    }

    @MainActor
    func testAppErrorHandlingTransparentReporterSubscription() {
        let view = Text("Main Content")
            .appErrorHandling(subscribeToReporter: true)

        let typeName = String(describing: type(of: view))
        XCTAssertTrue(typeName.contains("AppErrorHandlingModifier"), typeName)
    }

    // MARK: - WindowScaffold Tests

    @MainActor
    func testWindowScaffoldInstantiation() {
        let scaffold = WindowScaffold {
            Text("Scaffold Content")
        }
        let scaffoldType = String(describing: type(of: scaffold))
        XCTAssertTrue(scaffoldType.contains("WindowScaffold"), scaffoldType)
        XCTAssertTrue(scaffoldType.contains("EmptyView"), scaffoldType)

        let scaffoldWithFooter = WindowScaffold {
            Text("Footer Bar")
        } content: {
            Text("Scaffold Content")
        }
        let footerType = String(describing: type(of: scaffoldWithFooter))
        XCTAssertTrue(footerType.contains("WindowScaffold"), footerType)
        XCTAssertNotEqual(scaffoldType, footerType)
    }

    @MainActor
    func testWindowScaffoldWithErrorHandling() {
        var capturedError: AnyAppError? = nil
        let binding = Binding(get: { capturedError }, set: { capturedError = $0 })

        let scaffold = WindowScaffold(
            error: binding,
            subscribeToReporter: true,
            actionTitle: "재시도",
            onRecovery: { _ in }
        ) {
            Text("Window Content")
        }

        let typeName = String(describing: type(of: scaffold))
        XCTAssertTrue(typeName.contains("WindowScaffold"), typeName)
        XCTAssertNil(capturedError)
    }

    // MARK: - NoticeBanner Action & Recovery Tests

    @MainActor
    func testNoticeBannerWithRecoveryAction() {
        var actionClicked = false
        let banner = NoticeBanner(
            "서버와의 연결이 끊어졌습니다.",
            style: .error,
            actionTitle: "다시 시도",
            action: {
                actionClicked = true
            },
            onDismiss: {}
        )
        XCTAssertEqual(String(describing: type(of: banner)), String(describing: NoticeBanner.self))
        XCTAssertFalse(actionClicked)

        let errorBanner = ErrorBanner(
            "오류가 발생했습니다.",
            actionTitle: "복구",
            action: {
                actionClicked = true
            }
        )
        XCTAssertEqual(String(describing: type(of: errorBanner)), String(describing: ErrorBanner.self))
        XCTAssertFalse(actionClicked)
    }

    // MARK: - Localization Integration Tests

    @MainActor
    func testAppErrorLocalizationRendering() {
        let error = AnyAppError(
            errorCode: "STORAGE.NOT_FOUND",
            category: .system,
            severity: .error,
            context: ["path": "/tmp/test.txt"]
        )

        let info = AppErrorLocalization.render(error: error, using: nil)
        XCTAssertEqual(info.errorCode, "STORAGE.NOT_FOUND")
        XCTAssertFalse(info.message.isEmpty)
    }
}
#endif
