import EndpointRouterKit
import Foundation

/// Centralized local service probe candidates — environment variable overrides defaults.
public enum ServiceEndpoints {
    public static let loopbackHost = ProcessInfo.processInfo.environment["GUJO_LOOPBACK_HOST"]
        ?? [127, 0, 0, 1].map(String.init).joined(separator: ".")
    public static var defaultRemoteBaseURLString: String {
        if let override = ProcessInfo.processInfo.environment["GUJO_BASE_URL"], !override.isEmpty {
            return override
        }
        return EndpointRouter.gujoCore
    }
    public static let probeTimeout: TimeInterval = 2
    public static let webURLOverridesEnvironmentKey = "GUJO_WEB_URLS"

    public enum LocalWebPort {
        public static let laravel = 8001
        public static let alternate = 8585
        public static let fallback = 8000
    }

    public static let defaultLocalWebURLs: [URL] = [
        LocalWebPort.laravel, LocalWebPort.alternate, LocalWebPort.fallback
    ].compactMap { URL(string: "http://\(loopbackHost):\($0)") }

    public static let gujoWebCandidates: [URL] = {
        if let raw = ProcessInfo.processInfo.environment[webURLOverridesEnvironmentKey],
           !raw.isEmpty {
            return raw.split(separator: ",").compactMap { URL(string: String($0)) }
        }
        return defaultLocalWebURLs
    }()
}
