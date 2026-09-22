import XCTest
import Foundation
import LocalizationKit
@testable import AppErrorKit

private enum MockL10nKey: String, LocalizationKey {
    case resourceNotFound = "error.resource_not_found"
    case networkFailed = "error.network_failed"
}

private struct CustomSampleError: AppError {
    let errorCode: String
    let category: ErrorCategory
    let severity: ErrorSeverity
    let underlyingError: (any Error & Sendable)?
    let context: [String: String]
    let l10nKey: (any LocalizationKey)?

    init(
        errorCode: String,
        category: ErrorCategory = .business,
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

final class AnyAppErrorTests: XCTestCase {
    func testInitializationFromAppError() {
        struct Underlying: Error, Sendable, CustomStringConvertible {
            var description: String { "disk I/O error" }
        }

        let custom = CustomSampleError(
            errorCode: "STORAGE.READ_FAILED",
            category: .system,
            severity: .critical,
            underlyingError: Underlying(),
            context: ["path": "/data/db.sqlite"],
            l10nKey: MockL10nKey.resourceNotFound
        )

        let anyError = AnyAppError(custom)

        XCTAssertEqual(anyError.errorCode, "STORAGE.READ_FAILED")
        XCTAssertEqual(anyError.category, .system)
        XCTAssertEqual(anyError.severity, .critical)
        XCTAssertEqual(anyError.context["path"], "/data/db.sqlite")
        XCTAssertEqual(anyError.underlyingErrorDescription, "disk I/O error")
        XCTAssertEqual(anyError.rawL10nKey, "error.resource_not_found")
        XCTAssertEqual(anyError.l10nKey?.rawValue, "error.resource_not_found")
        XCTAssertNotNil(anyError.underlyingError)
        XCTAssertEqual(anyError.underlyingError?.localizedDescription, "disk I/O error")
    }

    func testIdentifiableUUID() {
        let err1 = AnyAppError(errorCode: "ERR.001")
        let err2 = AnyAppError(errorCode: "ERR.001")

        // 각 인스턴스는 SwiftUI 식별을 위한 고유 UUID를 가져야 함
        XCTAssertNotEqual(err1.id, err2.id)
    }

    func testEquatableAndHashableIgnoresId() {
        let uuid1 = UUID()
        let uuid2 = UUID()

        let err1 = AnyAppError(
            id: uuid1,
            errorCode: "NET.TIMEOUT",
            category: .network,
            severity: .error,
            context: ["host": "api.gujo.test"]
        )

        let err2 = AnyAppError(
            id: uuid2,
            errorCode: "NET.TIMEOUT",
            category: .network,
            severity: .error,
            context: ["host": "api.gujo.test"]
        )

        // id가 서로 달라도 errorCode와 context, category, severity가 같으면 Equatable 일치
        XCTAssertEqual(err1, err2)

        // Hashable도 일치하여 Set에 1개만 보관되어야 함
        let set: Set<AnyAppError> = [err1, err2]
        XCTAssertEqual(set.count, 1)

        // context가 다르면 불일치
        let err3 = err1.withContext(key: "host", value: "backup.gujo.test")
        XCTAssertNotEqual(err1, err3)

        // errorCode가 다르면 불일치
        let err4 = AnyAppError(
            id: uuid1,
            errorCode: "NET.RESET",
            category: .network,
            severity: .error,
            context: ["host": "api.gujo.test"]
        )
        XCTAssertNotEqual(err1, err4)
    }

    func testRustAnyhowStyleContextChaining() {
        let base = AnyAppError(
            errorCode: "AUTH.INVALID_TOKEN",
            category: .permission,
            severity: .warning
        )

        // 단일 .context 체이닝
        let step1 = base.context("failed to verify JWT")
        XCTAssertEqual(step1.context["context"], "failed to verify JWT")

        // 누적 체이닝: outer: inner
        let step2 = step1.context("user authentication pipeline failed")
        XCTAssertEqual(step2.context["context"], "user authentication pipeline failed: failed to verify JWT")

        // withContext(key:value:) 체이닝
        let step3 = step2
            .withContext(key: "userId", value: "user_12345")
            .withContext(key: "ip", value: "192.168.1.1")

        XCTAssertEqual(step3.context["userId"], "user_12345")
        XCTAssertEqual(step3.context["ip"], "192.168.1.1")
        XCTAssertEqual(step3.context["context"], "user authentication pipeline failed: failed to verify JWT")

        // withContext([key: value]) 배치 체이닝
        let step4 = base.withContext(["region": "kr", "env": "prod"])
        XCTAssertEqual(step4.context["region"], "kr")
        XCTAssertEqual(step4.context["env"], "prod")
    }

    func testCodableFullRoundtrip() throws {
        let expectedID = try XCTUnwrap(UUID(uuidString: "12345678-1234-1234-1234-123456789abc"))
        let original = AnyAppError(
            id: expectedID,
            errorCode: "LEDGER.INTEGRITY_VIOLATION",
            category: .business,
            severity: .critical,
            context: ["txId": "tx_998", "reason": "checksum_mismatch"],
            underlyingErrorDescription: "SHA256 hash does not match block header",
            rawL10nKey: "error.ledger_corrupt"
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(AnyAppError.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.errorCode, original.errorCode)
        XCTAssertEqual(decoded.category, original.category)
        XCTAssertEqual(decoded.severity, original.severity)
        XCTAssertEqual(decoded.context, original.context)
        XCTAssertEqual(decoded.underlyingErrorDescription, original.underlyingErrorDescription)
        XCTAssertEqual(decoded.rawL10nKey, original.rawL10nKey)
        XCTAssertEqual(decoded, original)
    }

    func testCodableResilientMinimalJSON() throws {
        let minimalJSON = """
        {
            "errorCode": "CONFIG.NOT_FOUND"
        }
        """
        let minimalData = try XCTUnwrap(minimalJSON.data(using: .utf8))

        let decoded = try JSONDecoder().decode(AnyAppError.self, from: minimalData)
        XCTAssertEqual(decoded.errorCode, "CONFIG.NOT_FOUND")
        XCTAssertEqual(decoded.category, .unknown)
        XCTAssertEqual(decoded.severity, .error)
        XCTAssertTrue(decoded.context.isEmpty)
        XCTAssertNil(decoded.underlyingErrorDescription)
        XCTAssertNil(decoded.rawL10nKey)
        XCTAssertNotNil(decoded.id)
    }

    func testSwift6SendableTaskBoundary() async {
        let error = AnyAppError(
            errorCode: "TASK.ISOLATION",
            category: .system,
            severity: .error,
            context: ["actor": "WorkerActor"]
        )

        let captured = await Task { () -> AnyAppError in
            return error.withContext(key: "workerId", value: "w1")
        }.value

        XCTAssertEqual(captured.errorCode, "TASK.ISOLATION")
        XCTAssertEqual(captured.context["workerId"], "w1")
    }

    func testEraseAndAsAnyAppError() {
        let custom = CustomSampleError(errorCode: "CUSTOM.ERR")
        let erased = custom.eraseToAnyAppError()
        XCTAssertEqual(erased.errorCode, "CUSTOM.ERR")

        struct StandardError: Error, Sendable {}
        let std = StandardError()
        let converted = std.asAnyAppError(category: .network, severity: .warning)
        XCTAssertEqual(converted.category, .network)
        XCTAssertEqual(converted.severity, .warning)
    }
}
