#if os(macOS)
import Foundation
import os.log

private let logger = Logger(subsystem: "TelemetryKit", category: "lifecycle")

/// Sentry 제거 후 no-op 스텁. API 호환만 유지하고 아무것도 하지 않는다.
public enum TelemetryKit {
    public static func start(
        app: String,
        dsn: String? = nil,
        environment: String? = nil,
        sampleRate: Double = 0.2,
        tracesSampleRate: Double = 0.05
    ) {
        logger.info("TelemetryKit: Sentry 제거됨 — 텔레메트리 비활성")
    }

    public static func captureError(_ error: Error, extra: [String: Any]? = nil) {}
    public static func captureMessage(_ message: String) {}
    public static func addBreadcrumb(category: String, message: String) {}
    public static func flush(timeout: TimeInterval = 2.0) {}
}
#endif
