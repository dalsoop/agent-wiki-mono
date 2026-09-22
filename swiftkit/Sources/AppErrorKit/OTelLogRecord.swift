import Foundation

/// OpenTelemetry (OTel) 의미 체계(Semantic Conventions) 호환 에러 로그 레코드.
public struct OTelLogRecord: Sendable, Codable, Equatable {
    public let timestamp: Date
    public let errorId: String
    public let errorCode: String
    public let category: String
    public let severity: String
    public let message: String
    public let recoverySuggestion: String?
    public let underlyingError: String?
    public let sourceLocation: String
    public let context: [String: String]

    public init(
        timestamp: Date,
        errorId: String,
        errorCode: String,
        category: String,
        severity: String,
        message: String,
        recoverySuggestion: String?,
        underlyingError: String?,
        sourceLocation: String,
        context: [String: String]
    ) {
        self.timestamp = timestamp
        self.errorId = errorId
        self.errorCode = errorCode
        self.category = category
        self.severity = severity
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.underlyingError = underlyingError
        self.sourceLocation = sourceLocation
        self.context = context
    }

    /// OTel 표준 Semantic Conventions 속성 맵 (`exception.type`, `exception.message` 등).
    public var attributes: [String: String] {
        var attrs: [String: String] = [
            "exception.type": errorCode,
            "exception.message": message,
            "code.filepath": sourceLocation,
            "app.error.id": errorId,
            "app.error.category": category,
            "app.error.severity": severity
        ]
        if let recovery = recoverySuggestion {
            attrs["app.error.recovery"] = recovery
        }
        if let underlying = underlyingError {
            attrs["exception.stacktrace"] = underlying
            attrs["app.error.underlying"] = underlying
        }
        for (key, value) in context {
            attrs["app.error.context.\(key)"] = value
        }
        return attrs
    }

    /// OTel JSON 직렬화 문자열.
    public func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        do {
            let data = try encoder.encode(self)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

extension AppErrorReporter {
    /// OpenTelemetry Semantic Conventions 호환 구조화 레코드를 생성합니다.
    public func otelRecord(
        for error: AnyAppError,
        file: StaticString = #fileID,
        line: UInt = #line
    ) -> OTelLogRecord {
        OTelLogRecord(
            timestamp: Date(),
            errorId: error.id.uuidString,
            errorCode: error.errorCode,
            category: error.category.rawValue,
            severity: error.severity.rawValue,
            message: error.userFacingMessage,
            recoverySuggestion: error.userFacingRecoverySuggestion,
            underlyingError: error.underlyingErrorDescription,
            sourceLocation: "\(file):\(line)",
            context: error.context
        )
    }
}
