import XCTest
import Foundation
import os
import LocalizationKit
@testable import AppErrorKit

/// Swift 6 동시성 테스트를 위한 스레드 안전 값 래퍼.
private final class TestBox<T: Sendable>: Sendable {
    private let state: OSAllocatedUnfairLock<T>

    init(_ value: T) {
        self.state = OSAllocatedUnfairLock(initialState: value)
    }

    var value: T {
        state.withLock { $0 }
    }

    func mutate(_ transform: @Sendable (inout T) -> Void) {
        state.withLock { transform(&$0) }
    }

    func set(_ newValue: T) {
        state.withLock { $0 = newValue }
    }
}

private struct MockTestError: AppError, Equatable {
    let errorCode: String
    let category: ErrorCategory
    let severity: ErrorSeverity
    let context: [String: String]
    let underlyingError: (any Error & Sendable)?
    let l10nKey: (any LocalizationKey)?

    init(
        errorCode: String = "TEST.MOCK_ERROR",
        category: ErrorCategory = .business,
        severity: ErrorSeverity = .error,
        context: [String: String] = [:],
        underlyingError: (any Error & Sendable)? = nil,
        l10nKey: (any LocalizationKey)? = nil
    ) {
        self.errorCode = errorCode
        self.category = category
        self.severity = severity
        self.context = context
        self.underlyingError = underlyingError
        self.l10nKey = l10nKey
    }

    static func == (lhs: MockTestError, rhs: MockTestError) -> Bool {
        lhs.errorCode == rhs.errorCode &&
        lhs.category == rhs.category &&
        lhs.severity == rhs.severity &&
        lhs.context == rhs.context
    }
}

final class AppErrorReporterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppErrorReporter.shared.reset()
    }

    override func tearDown() {
        AppErrorReporter.shared.reset()
        super.tearDown()
    }

    // MARK: - Basic Report & Record Tests

    func testReportAnyAppErrorAndRecord() {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))
        let receivedError = TestBox<AnyAppError?>(nil)
        let receivedFile = TestBox<String?>(nil)
        let receivedLine = TestBox<UInt?>(nil)

        reporter.registerHandler { error, file, line in
            receivedError.set(error)
            receivedFile.set("\(file)")
            receivedLine.set(line)
        }

        let customError = MockTestError(
            errorCode: "STORAGE.IO_ERROR",
            category: .system,
            severity: .critical,
            context: ["path": "/data/db.sqlite"]
        )

        reporter.report(customError, file: "StorageService.swift", line: 105)

        XCTAssertNotNil(receivedError.value)
        XCTAssertEqual(receivedError.value?.errorCode, "STORAGE.IO_ERROR")
        XCTAssertEqual(receivedError.value?.category, .system)
        XCTAssertEqual(receivedError.value?.severity, .critical)
        XCTAssertEqual(receivedError.value?.context["path"], "/data/db.sqlite")
        XCTAssertEqual(receivedFile.value, "StorageService.swift")
        XCTAssertEqual(receivedLine.value, 105)
    }

    func testRecordDirectAnyAppError() {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))
        let receivedError = TestBox<AnyAppError?>(nil)

        reporter.registerHandler { error, _, _ in
            receivedError.set(error)
        }

        let anyError = AnyAppError(
            errorCode: "NET.TIMEOUT",
            category: .network,
            severity: .warning,
            context: ["endpoint": "/api/v1/sync"]
        )

        reporter.record(anyError)

        XCTAssertNotNil(receivedError.value)
        XCTAssertEqual(receivedError.value?.errorCode, "NET.TIMEOUT")
        XCTAssertEqual(receivedError.value?.category, .network)
        XCTAssertEqual(receivedError.value?.severity, .warning)
        XCTAssertEqual(receivedError.value?.context["endpoint"], "/api/v1/sync")
    }

    func testAppErrorConvenienceReportExtension() {
        AppErrorReporter.shared.configuration.recordTestFailures = false
        let capturedCode = TestBox<String?>(nil)

        let token = AppErrorReporter.registerHandler { error, _, _ in
            capturedCode.set(error.errorCode)
        }
        defer { AppErrorReporter.unregisterHandler(token) }

        let error = MockTestError(errorCode: "CONVENIENCE.EXT_CALL")
        error.report()

        XCTAssertEqual(capturedCode.value, "CONVENIENCE.EXT_CALL")
    }

    func testAppErrorExistentialCollectionReporting() {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))
        let capturedCodes = TestBox<[String]>([])

        reporter.registerHandler { error, _, _ in
            capturedCodes.mutate { $0.append(error.errorCode) }
        }

        let errors: [any AppError] = [
            MockTestError(errorCode: "ERR.1"),
            AnyAppError(errorCode: "ERR.2"),
            MockTestError(errorCode: "ERR.3")
        ]

        for err in errors {
            reporter.report(err)
        }

        XCTAssertEqual(capturedCodes.value, ["ERR.1", "ERR.2", "ERR.3"])
    }

    // MARK: - Handler Management Tests

    func testMultipleHandlerRegistrationAndUnregistration() {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))
        let handlerACalls = TestBox<[String]>([])
        let handlerBCalls = TestBox<[String]>([])

        let tokenA = reporter.registerHandler { error, _, _ in
            handlerACalls.mutate { $0.append(error.errorCode) }
        }
        let tokenB = reporter.registerHandler { error, _, _ in
            handlerBCalls.mutate { $0.append(error.errorCode) }
        }

        reporter.record(AnyAppError(errorCode: "FIRST"))
        XCTAssertEqual(handlerACalls.value, ["FIRST"])
        XCTAssertEqual(handlerBCalls.value, ["FIRST"])

        // Unregister A with token
        reporter.unregisterHandler(tokenA)
        reporter.record(AnyAppError(errorCode: "SECOND"))
        XCTAssertEqual(handlerACalls.value, ["FIRST"])
        XCTAssertEqual(handlerBCalls.value, ["FIRST", "SECOND"])

        // Unregister B with UUID
        reporter.unregisterHandler(tokenB.id)
        reporter.record(AnyAppError(errorCode: "THIRD"))
        XCTAssertEqual(handlerACalls.value, ["FIRST"])
        XCTAssertEqual(handlerBCalls.value, ["FIRST", "SECOND"])
    }

    func testSetSingleHandlerAndClearHandlers() {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))
        let singleCalls = TestBox<[String]>([])

        reporter.setHandler { error, _, _ in
            singleCalls.mutate { $0.append("H1:\(error.errorCode)") }
        }
        reporter.record(AnyAppError(errorCode: "E1"))
        XCTAssertEqual(singleCalls.value, ["H1:E1"])

        // Replace single handler
        reporter.setHandler { error, _, _ in
            singleCalls.mutate { $0.append("H2:\(error.errorCode)") }
        }
        reporter.record(AnyAppError(errorCode: "E2"))
        XCTAssertEqual(singleCalls.value, ["H1:E1", "H2:E2"])

        // Clear handlers
        reporter.clearHandlers()
        reporter.record(AnyAppError(errorCode: "E3"))
        XCTAssertEqual(singleCalls.value, ["H1:E1", "H2:E2"])
    }

    // MARK: - NotificationCenter Posting

    @MainActor
    func testNotificationPostingOnRecord() {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))
        let expectation = expectation(description: "Notification received")

        let sample = AnyAppError(errorCode: "NOTIF.ERR", category: .system, severity: .warning)
        let receivedError = TestBox<AnyAppError?>(nil)
        let receivedFile = TestBox<String?>(nil)
        let receivedLine = TestBox<UInt?>(nil)

        let token = NotificationCenter.default.addObserver(
            forName: AppErrorReporter.didRecordErrorNotification,
            object: nil,
            queue: nil
        ) { notification in
            if let err = notification.object as? AnyAppError, err.errorCode == "NOTIF.ERR" {
                receivedError.set(err)
                receivedFile.set(notification.userInfo?["file"] as? String)
                receivedLine.set(notification.userInfo?["line"] as? UInt)
                expectation.fulfill()
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }

        reporter.record(sample, file: "TestFile.swift", line: 42)
        waitForExpectations(timeout: 2.0)

        XCTAssertEqual(receivedError.value?.errorCode, "NOTIF.ERR")
        XCTAssertEqual(receivedFile.value, "TestFile.swift")
        XCTAssertEqual(receivedLine.value, 42)
    }

    // MARK: - Point-Free withExpectedError & Scoped Handlers

    func testWithExpectedErrorSuppressesTestFailure() {
        // Point-Free 철학: 테스트 중 예기치 못한 에러는 test failure를 유발하지만,
        // withExpectedError 스코프 안에서는 테스트 실패가 억제됨
        AppErrorReporter.shared.configuration.recordTestFailures = true

        let caughtCode = TestBox<String?>(nil)
        AppErrorReporter.withExpectedError(handler: { error, _, _ in
            caughtCode.set(error.errorCode)
        }) {
            AppErrorReporter.record(AnyAppError(errorCode: "EXPECTED.TEST_ERROR"))
        }

        XCTAssertEqual(caughtCode.value, "EXPECTED.TEST_ERROR")
    }

    func testWithExpectedErrorAsync() async {
        AppErrorReporter.shared.configuration.recordTestFailures = true

        let collector = TestBox<String?>(nil)

        await AppErrorReporter.withExpectedError(handler: { error, _, _ in
            collector.set(error.errorCode)
        }) {
            try? await Task.sleep(nanoseconds: 5_000_000)
            AppErrorReporter.record(AnyAppError(errorCode: "ASYNC.EXPECTED"))
        }

        XCTAssertEqual(collector.value, "ASYNC.EXPECTED")
    }

    func testCaptureExpectedErrorsSync() {
        let (value, errors) = AppErrorReporter.captureExpectedErrors { () -> Int in
            AppErrorReporter.record(AnyAppError(errorCode: "CAPTURED.1"))
            AppErrorReporter.record(AnyAppError(errorCode: "CAPTURED.2"))
            return 42
        }

        XCTAssertEqual(value, 42)
        XCTAssertEqual(errors.count, 2)
        XCTAssertEqual(errors.map(\.errorCode), ["CAPTURED.1", "CAPTURED.2"])
    }

    func testCaptureExpectedErrorsAsync() async {
        let (value, errors) = await AppErrorReporter.captureExpectedErrors { () async -> String in
            try? await Task.sleep(nanoseconds: 5_000_000)
            AppErrorReporter.record(AnyAppError(errorCode: "ASYNC.CAPTURED.1"))
            AppErrorReporter.record(AnyAppError(errorCode: "ASYNC.CAPTURED.2"))
            return "ok"
        }

        XCTAssertEqual(value, "ok")
        XCTAssertEqual(errors.count, 2)
        XCTAssertEqual(errors.map(\.errorCode), ["ASYNC.CAPTURED.1", "ASYNC.CAPTURED.2"])
    }

    func testWithHandlerScoped() {
        AppErrorReporter.shared.configuration.recordTestFailures = false

        let scopedCalls = TestBox<[String]>([])
        let globalCalls = TestBox<[String]>([])

        let globalToken = AppErrorReporter.registerHandler { error, _, _ in
            globalCalls.mutate { $0.append(error.errorCode) }
        }
        defer { AppErrorReporter.unregisterHandler(globalToken) }

        AppErrorReporter.withHandler({ error, _, _ in
            scopedCalls.mutate { $0.append(error.errorCode) }
        }) {
            AppErrorReporter.record(AnyAppError(errorCode: "IN_SCOPE"))
        }

        AppErrorReporter.record(AnyAppError(errorCode: "OUT_SCOPE"))

        XCTAssertEqual(scopedCalls.value, ["IN_SCOPE"])
        XCTAssertEqual(globalCalls.value, ["IN_SCOPE", "OUT_SCOPE"])
    }

    func testWithHandlerAsyncScoped() async {
        AppErrorReporter.shared.configuration.recordTestFailures = false

        let collector = TestBox<[String]>([])

        await AppErrorReporter.withHandler({ error, _, _ in
            collector.mutate { $0.append(error.errorCode) }
        }) {
            try? await Task.sleep(nanoseconds: 5_000_000)
            AppErrorReporter.record(AnyAppError(errorCode: "ASYNC.SCOPED"))
        }

        XCTAssertEqual(collector.value, ["ASYNC.SCOPED"])
    }

    // MARK: - Swift 6 Sendable / Concurrency Stress Tests

    func testSwift6SendableAndConcurrencyStress() async {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))

        let counter = TestBox<Int>(0)
        let token = reporter.registerHandler { _, _, _ in
            counter.mutate { $0 += 1 }
        }
        defer { reporter.unregisterHandler(token) }

        let iterations = 50
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<iterations {
                group.addTask {
                    let err = AnyAppError(
                        errorCode: "CONCURRENT.\(i)",
                        category: .network,
                        severity: .info
                    )
                    reporter.record(err)
                }
            }
        }

        XCTAssertEqual(counter.value, iterations)
    }

    func testConcurrentHandlerRegistrationAndDispatch() async {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))
        let recordedCount = TestBox<Int>(0)

        await withTaskGroup(of: Void.self) { group in
            for i in 0..<30 {
                group.addTask {
                    let token = reporter.registerHandler { _, _, _ in
                        recordedCount.mutate { $0 += 1 }
                    }
                    reporter.record(AnyAppError(errorCode: "TASK.\(i)"))
                    reporter.unregisterHandler(token)
                }
            }
        }

        XCTAssertGreaterThanOrEqual(recordedCount.value, 0)
    }

    func testSendableReporterPassingAcrossTasks() async {
        let reporter = AppErrorReporter(configuration: .init(recordTestFailures: false))

        let code = await Task { () -> String in
            let recorded = TestBox<String>("")
            reporter.registerHandler { error, _, _ in
                recorded.set(error.errorCode)
            }
            reporter.record(AnyAppError(errorCode: "ACROSS_TASK"))
            return recorded.value
        }.value

        XCTAssertEqual(code, "ACROSS_TASK")
    }

    // MARK: - Formatting & OTel Integration Tests

    func testFormatTestFailureMessage() {
        let reporter = AppErrorReporter()
        let error = AnyAppError(
            errorCode: "STORAGE.DISK_FULL",
            category: .system,
            severity: .critical,
            context: ["mount": "/Volumes/Data", "available": "0MB"],
            underlyingErrorDescription: "POSIXError: No space left on device"
        )

        let message = reporter.formatTestFailureMessage(for: error, file: "DiskService.swift", line: 128)

        XCTAssertTrue(message.contains("An unexpected AppError was reported:"))
        XCTAssertTrue(message.contains("[STORAGE.DISK_FULL]"))
        XCTAssertTrue(message.contains("CRITICAL"))
        XCTAssertTrue(message.contains("system"))
        XCTAssertTrue(message.contains("No space left on device"))
        XCTAssertTrue(message.contains("mount=/Volumes/Data"))
        XCTAssertTrue(message.contains("available=0MB"))
        XCTAssertTrue(message.contains("DiskService.swift:128"))
    }

    func testFormatStructuredLogMessage() {
        let reporter = AppErrorReporter()
        let error = AnyAppError(
            errorCode: "AUTH.INVALID_TOKEN",
            category: .permission,
            severity: .error,
            context: ["userId": "user-123"]
        )

        let logLine = reporter.formatStructuredLogMessage(for: error, file: "AuthService.swift", line: 77)

        XCTAssertTrue(logLine.contains("[ERROR]"))
        XCTAssertTrue(logLine.contains("[AUTH.INVALID_TOKEN]"))
        XCTAssertTrue(logLine.contains("category=permission"))
        XCTAssertTrue(logLine.contains("source=AuthService.swift:77"))
        XCTAssertTrue(logLine.contains("id=\(error.id.uuidString)"))
        XCTAssertTrue(logLine.contains("userId"))
    }

    func testOTelRecordGeneration() throws {
        let reporter = AppErrorReporter()
        let error = AnyAppError(
            errorCode: "NET.CONNECTION_REFUSED",
            category: .network,
            severity: .error,
            context: ["host": "api.gujo.test", "port": "443"],
            underlyingErrorDescription: "Connection reset by peer"
        )

        let otel = reporter.otelRecord(for: error, file: "NetworkClient.swift", line: 200)

        XCTAssertEqual(otel.errorCode, "NET.CONNECTION_REFUSED")
        XCTAssertEqual(otel.category, "network")
        XCTAssertEqual(otel.severity, "error")
        XCTAssertEqual(otel.sourceLocation, "NetworkClient.swift:200")
        XCTAssertEqual(otel.underlyingError, "Connection reset by peer")
        XCTAssertEqual(otel.context["host"], "api.gujo.test")

        let attrs = otel.attributes
        XCTAssertEqual(attrs["exception.type"], "NET.CONNECTION_REFUSED")
        XCTAssertEqual(attrs["code.filepath"], "NetworkClient.swift:200")
        XCTAssertEqual(attrs["app.error.id"], error.id.uuidString)
        XCTAssertEqual(attrs["app.error.category"], "network")
        XCTAssertEqual(attrs["app.error.severity"], "error")
        XCTAssertEqual(attrs["app.error.context.host"], "api.gujo.test")
        XCTAssertEqual(attrs["app.error.context.port"], "443")

        let jsonString = try XCTUnwrap(otel.toJSONString())
        XCTAssertTrue(jsonString.contains("NET.CONNECTION_REFUSED"))
    }

    // MARK: - Configuration & Environment Tests

    func testConfigurationUpdateAndReset() {
        let reporter = AppErrorReporter()
        XCTAssertTrue(reporter.configuration.recordTestFailures)
        XCTAssertTrue(reporter.configuration.emitOSLog)
        XCTAssertEqual(reporter.configuration.logSubsystem, "com.gujo.apperror")
        XCTAssertEqual(reporter.configuration.logCategory, "AppError")

        reporter.configuration = AppErrorReporter.Configuration(
            recordTestFailures: false,
            emitOSLog: false,
            logSubsystem: "custom.subsystem",
            logCategory: "CustomCat"
        )

        XCTAssertFalse(reporter.configuration.recordTestFailures)
        XCTAssertFalse(reporter.configuration.emitOSLog)
        XCTAssertEqual(reporter.configuration.logSubsystem, "custom.subsystem")
        XCTAssertEqual(reporter.configuration.logCategory, "CustomCat")

        reporter.reset()
        XCTAssertTrue(reporter.configuration.recordTestFailures)
        XCTAssertTrue(reporter.configuration.emitOSLog)
        XCTAssertEqual(reporter.configuration.logSubsystem, "com.gujo.apperror")
    }

    func testIsTestingDetection() {
        // XCTest 실행 환경 감지
        XCTAssertTrue(AppErrorReporter.isTesting)
    }
}
