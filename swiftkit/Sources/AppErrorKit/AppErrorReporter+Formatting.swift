import Foundation
#if canImport(os)
import os
#endif

extension AppErrorReporter {

    // MARK: - OSLog Structured Logging

    func logToOSLog(
        for error: AnyAppError,
        file: StaticString,
        line: UInt,
        config: Configuration
    ) {
        let structuredMessage = formatStructuredLogMessage(for: error, file: file, line: line)

        #if canImport(os)
        let category = "\(config.logCategory).\(error.category.rawValue)"
        let logger = Logger(subsystem: config.logSubsystem, category: category)

        switch error.severity {
        case .info:
            logger.info("\(structuredMessage, privacy: .public)")
        case .warning:
            logger.warning("\(structuredMessage, privacy: .public)")
        case .error:
            logger.error("\(structuredMessage, privacy: .public)")
        case .critical:
            logger.fault("\(structuredMessage, privacy: .public)")
        }
        #else
        fputs("\(structuredMessage)\n", stderr)
        #endif
    }

    // MARK: - Structured Message Formatting

    /// 런타임/프로덕션 Unified Logging 및 로그 수집기 파싱에 최적화된 단일행 구조화 메시지를 생성합니다.
    public func formatStructuredLogMessage(for error: AnyAppError, file: StaticString, line: UInt) -> String {
        let parts: [String] = [
            "[\(error.severity.rawValue.uppercased())]",
            "[\(error.errorCode)]",
            error.userFacingMessage
        ]

        var metadata: [String] = [
            "id=\(error.id.uuidString)",
            "category=\(error.category.rawValue)",
            "source=\(file):\(line)"
        ]

        appendLogMetadata(to: &metadata, for: error)

        return "\(parts.joined(separator: " ")) | \(metadata.joined(separator: " "))"
    }

    private func appendLogMetadata(to metadata: inout [String], for error: AnyAppError) {
        if let recovery = error.userFacingRecoverySuggestion {
            metadata.append("recovery=\"\(recovery)\"")
        }
        if let underlying = error.underlyingErrorDescription {
            metadata.append("underlying=\"\(underlying)\"")
        }
        guard !error.context.isEmpty else { return }
        metadata.append("context=\(formatContextJSON(error.context))")
    }

    private func formatContextJSON(_ context: [String: String]) -> String {
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: context, options: [.sortedKeys])
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                return jsonString
            }
        } catch {
            let pairs = context.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: ",")
            return "{\(pairs)}"
        }
        let pairs = context.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: ",")
        return "{\(pairs)}"
    }
}
