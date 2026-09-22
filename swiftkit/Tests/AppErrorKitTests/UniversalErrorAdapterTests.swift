import XCTest
import Foundation
import LocalizationKit
@testable import AppErrorKit

private struct CustomDummyError: Error, Sendable, CustomStringConvertible {
    var description: String { "custom dummy error occurred" }
}

private struct CustomAppErrorSample: AppError {
    let errorCode: String = "CUSTOM.DUMMY"
    let category: ErrorCategory = .business
    let severity: ErrorSeverity = .warning
    let isSilent: Bool = false
    let context: [String: String] = ["foo": "bar"]
    let underlyingError: (any Error & Sendable)? = nil
    let l10nKey: (any LocalizationKey)? = nil
}

final class UniversalErrorAdapterTests: XCTestCase {

    // MARK: - 1. Cancellation Detection Tests

    func testCancellationErrorIsSilentAndCancelledCategory() {
        let cancellationError = CancellationError()
        let adapted = cancellationError.asUniversalAppError

        XCTAssertEqual(adapted.category, .cancelled)
        XCTAssertTrue(adapted.isSilent)
        XCTAssertEqual(adapted.severity, .info)
        XCTAssertEqual(adapted.errorCode, "SYSTEM.TASK_CANCELLED")
        XCTAssertEqual(adapted.context["cancellation_reason"], "CancellationError")
    }

    func testTaskIsCancelledDetectionInAsyncScope() async {
        let task = Task { () -> AnyAppError in
            while !Task.isCancelled {
                await Task.yield()
            }
            let dummy = CustomDummyError()
            return UniversalErrorAdapter.adapt(dummy)
        }

        task.cancel()
        let adapted = await task.value

        // CustomDummyError 는 CancellationError 가 아니므로 silent 로 삼키지 않는다.
        XCTAssertFalse(adapted.isSilent)
        XCTAssertNotEqual(adapted.category, .cancelled)
        XCTAssertEqual(adapted.context["task_cancelled"], "true")
    }

    func testCancellationErrorRemainsSilentInsideCancelledTask() async {
        let task = Task { () -> AnyAppError in
            while !Task.isCancelled {
                await Task.yield()
            }
            return UniversalErrorAdapter.adapt(CancellationError())
        }

        task.cancel()
        let adapted = await task.value

        XCTAssertTrue(adapted.isSilent)
        XCTAssertEqual(adapted.category, .cancelled)
        XCTAssertEqual(adapted.errorCode, "SYSTEM.TASK_CANCELLED")
    }

    func testURLErrorTimeoutIsNotCancelledWhenTaskIsCancelled() async {
        let task = Task { () -> AnyAppError in
            while !Task.isCancelled {
                await Task.yield()
            }
            return UniversalErrorAdapter.adapt(URLError(.timedOut))
        }

        task.cancel()
        let adapted = await task.value

        XCTAssertEqual(adapted.category, .network)
        XCTAssertEqual(adapted.errorCode, "NETWORK.TIMEOUT")
        XCTAssertFalse(adapted.isSilent)
        XCTAssertEqual(adapted.context["task_cancelled"], "true")
    }

    func testPOSIXPermissionIsNotCancelledWhenTaskIsCancelled() async {
        let task = Task { () -> AnyAppError in
            while !Task.isCancelled {
                await Task.yield()
            }
            return UniversalErrorAdapter.adapt(POSIXError(.EACCES))
        }

        task.cancel()
        let adapted = await task.value

        XCTAssertEqual(adapted.category, .permission)
        XCTAssertEqual(adapted.errorCode, "POSIX.EACCES")
        XCTAssertFalse(adapted.isSilent)
        XCTAssertEqual(adapted.context["task_cancelled"], "true")
    }

    // MARK: - 2. URLError Classification Tests

    func testURLErrorTimeoutClassification() {
        let urlError = URLError(.timedOut)
        let adapted = urlError.asUniversalAppError

        XCTAssertEqual(adapted.category, .network)
        XCTAssertEqual(adapted.errorCode, "NETWORK.TIMEOUT")
        XCTAssertEqual(adapted.severity, .warning)
        XCTAssertFalse(adapted.isSilent)
        XCTAssertEqual(adapted.context["ns_domain"], NSURLErrorDomain)
        XCTAssertEqual(adapted.context["ns_code"], String(URLError.timedOut.rawValue))
    }

    func testURLErrorCancelledClassification() {
        let urlError = URLError(.cancelled)
        let adapted = urlError.asUniversalAppError

        XCTAssertEqual(adapted.category, .cancelled)
        XCTAssertEqual(adapted.errorCode, "NETWORK.CANCELLED")
        XCTAssertEqual(adapted.severity, .info)
        XCTAssertTrue(adapted.isSilent)
    }

    func testURLErrorNetworkFailuresClassification() {
        let disconnected = URLError(.notConnectedToInternet).asUniversalAppError
        XCTAssertEqual(disconnected.category, .network)
        XCTAssertEqual(disconnected.errorCode, "NETWORK.NO_CONNECTION")

        let dnsFail = URLError(.cannotFindHost).asUniversalAppError
        XCTAssertEqual(dnsFail.category, .network)
        XCTAssertEqual(dnsFail.errorCode, "NETWORK.DNS_FAILURE")

        let connRefused = URLError(.cannotConnectToHost).asUniversalAppError
        XCTAssertEqual(connRefused.category, .network)
        XCTAssertEqual(connRefused.errorCode, "NETWORK.CONNECTION_REFUSED")

        let sslFail = URLError(.secureConnectionFailed).asUniversalAppError
        XCTAssertEqual(sslFail.category, .network)
        XCTAssertEqual(sslFail.errorCode, "NETWORK.SSL_FAILURE")
    }

    // MARK: - 3. CocoaError Classification Tests

    func testCocoaErrorFileSystemClassification() {
        let notFound = CocoaError(.fileNoSuchFile).asUniversalAppError
        XCTAssertEqual(notFound.category, .fileSystem)
        XCTAssertEqual(notFound.errorCode, "COCOA.FILE_NOT_FOUND")
        XCTAssertFalse(notFound.isSilent)

        let outOfSpace = CocoaError(.fileWriteOutOfSpace).asUniversalAppError
        XCTAssertEqual(outOfSpace.category, .fileSystem)
        XCTAssertEqual(outOfSpace.errorCode, "COCOA.OUT_OF_SPACE")
    }

    func testCocoaErrorPermissionClassification() {
        let readDenied = CocoaError(.fileReadNoPermission).asUniversalAppError
        XCTAssertEqual(readDenied.category, .permission)
        XCTAssertEqual(readDenied.errorCode, "COCOA.PERMISSION_DENIED")
        XCTAssertFalse(readDenied.isSilent)

        let writeDenied = CocoaError(.fileWriteNoPermission).asUniversalAppError
        XCTAssertEqual(writeDenied.category, .permission)
        XCTAssertEqual(writeDenied.errorCode, "COCOA.PERMISSION_DENIED")
    }

    func testCocoaErrorUserCancelledClassification() {
        let cancelled = CocoaError(.userCancelled).asUniversalAppError
        XCTAssertEqual(cancelled.category, .cancelled)
        XCTAssertEqual(cancelled.errorCode, "COCOA.USER_CANCELLED")
        XCTAssertEqual(cancelled.severity, .info)
        XCTAssertTrue(cancelled.isSilent)
    }

    // MARK: - 4. POSIXError Classification Tests

    func testPOSIXErrorPermissionClassification() {
        let eacces = POSIXError(.EACCES).asUniversalAppError
        XCTAssertEqual(eacces.category, .permission)
        XCTAssertEqual(eacces.errorCode, "POSIX.EACCES")
        XCTAssertFalse(eacces.isSilent)
        XCTAssertEqual(eacces.context["ns_domain"], NSPOSIXErrorDomain)

        let eperm = POSIXError(.EPERM).asUniversalAppError
        XCTAssertEqual(eperm.category, .permission)
        XCTAssertEqual(eperm.errorCode, "POSIX.EPERM")
    }

    func testPOSIXErrorFileSystemClassification() {
        let enoent = POSIXError(.ENOENT).asUniversalAppError
        XCTAssertEqual(enoent.category, .fileSystem)
        XCTAssertEqual(enoent.errorCode, "POSIX.ENOENT")
        XCTAssertFalse(enoent.isSilent)

        let eexist = POSIXError(.EEXIST).asUniversalAppError
        XCTAssertEqual(eexist.category, .fileSystem)
        XCTAssertEqual(eexist.errorCode, "POSIX.EEXIST")
    }

    func testPOSIXErrorCancelledClassification() {
        let ecanceled = POSIXError(.ECANCELED).asUniversalAppError
        XCTAssertEqual(ecanceled.category, .cancelled)
        XCTAssertEqual(ecanceled.errorCode, "POSIX.ECANCELED")
        XCTAssertEqual(ecanceled.severity, .info)
        XCTAssertTrue(ecanceled.isSilent)
    }

    func testPOSIXErrorNetworkClassification() {
        let etimedout = POSIXError(.ETIMEDOUT).asUniversalAppError
        XCTAssertEqual(etimedout.category, .network)
        XCTAssertEqual(etimedout.errorCode, "POSIX.ETIMEDOUT")
    }

    // MARK: - 5. NSError Domain & Code Preservation Tests

    func testNSErrorDomainAndCodePreservation() {
        let nsError = NSError(
            domain: "com.gujo.payment",
            code: 4002,
            userInfo: [
                NSLocalizedDescriptionKey: "Insufficient credits",
                NSLocalizedFailureReasonErrorKey: "User balance is below minimum threshold"
            ]
        )

        let adapted = nsError.asUniversalAppError

        XCTAssertEqual(adapted.errorCode, "COM.GUJO.PAYMENT.4002")
        XCTAssertEqual(adapted.context["ns_domain"], "com.gujo.payment")
        XCTAssertEqual(adapted.context["ns_code"], "4002")
        XCTAssertEqual(adapted.context["failure_reason"], "User balance is below minimum threshold")
        XCTAssertFalse(adapted.isSilent)
    }

    func testNSErrorCategoryInferenceFromDomain() {
        let netNsError = NSError(domain: "NetworkServiceClientErrorDomain", code: 500, userInfo: nil)
        XCTAssertEqual(netNsError.asUniversalAppError.category, .network)

        let fileNsError = NSError(domain: "DiskStorageIOErrorDomain", code: 12, userInfo: nil)
        XCTAssertEqual(fileNsError.asUniversalAppError.category, .fileSystem)

        let authNsError = NSError(domain: "AuthPermissionSecurityDomain", code: 403, userInfo: nil)
        XCTAssertEqual(authNsError.asUniversalAppError.category, .permission)
    }

    // MARK: - 6. AppError & AnyAppError Passthrough Tests

    func testAnyAppErrorPassthrough() {
        let original = AnyAppError(
            errorCode: "STORE.ITEM_EXPIRED",
            category: .business,
            severity: .warning,
            isSilent: false,
            context: ["itemId": "sku_991"]
        )

        let adapted = UniversalErrorAdapter.adapt(original)
        XCTAssertEqual(adapted.id, original.id)
        XCTAssertEqual(adapted.errorCode, original.errorCode)
        XCTAssertEqual(adapted.category, original.category)
        XCTAssertEqual(adapted.context["itemId"], "sku_991")
    }

    func testAppErrorProtocolConformanceWrapping() {
        let custom = CustomAppErrorSample()
        let adapted = custom.asUniversalAppError

        XCTAssertEqual(adapted.errorCode, "CUSTOM.DUMMY")
        XCTAssertEqual(adapted.category, .business)
        XCTAssertEqual(adapted.severity, .warning)
        XCTAssertEqual(adapted.context["foo"], "bar")
    }

    // MARK: - 7. Codable isSilent Roundtrip Tests

    func testCodableWithIsSilentRoundtrip() throws {
        let original = AnyAppError(
            errorCode: "TASK.CANCELLED_SILENT",
            category: .cancelled,
            severity: .info,
            isSilent: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AnyAppError.self, from: data)

        XCTAssertTrue(decoded.isSilent)
        XCTAssertEqual(decoded.category, .cancelled)
        XCTAssertEqual(decoded.errorCode, "TASK.CANCELLED_SILENT")
    }
}
