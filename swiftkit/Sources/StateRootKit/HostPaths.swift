import Foundation

/// 호스트 경로 및 표준 디렉터리(XDG / macOS) 해석 SSOT.
public enum HostPaths: Sendable {
    /// 사용자 홈 디렉터리 경로 (크로스플랫폼: HOME 환경변수 우선, NSHomeDirectory() 폴백).
    public static func userHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallback: String = NSHomeDirectory()
    ) -> String {
        if let home = environment["HOME"], !home.isEmpty {
            return (home as NSString).standardizingPath
        }
        return fallback
    }

    /// URL 형태의 userHome.
    public static func userHomeURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallback: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> URL {
        URL(fileURLWithPath: userHome(environment: environment, fallback: fallback.path), isDirectory: true)
    }

    /// Linux XDG Data Home ($XDG_DATA_HOME 또는 ~/.local/share).
    public static func xdgDataHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        if let dataHome = environment["XDG_DATA_HOME"], !dataHome.isEmpty {
            return (dataHome as NSString).standardizingPath
        }
        let home = homeDirectory ?? userHome(environment: environment)
        return (home as NSString).appendingPathComponent(".local/share")
    }

    /// Linux XDG Config Home ($XDG_CONFIG_HOME 또는 ~/.config).
    public static func xdgConfigHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        if let configHome = environment["XDG_CONFIG_HOME"], !configHome.isEmpty {
            return (configHome as NSString).standardizingPath
        }
        let home = homeDirectory ?? userHome(environment: environment)
        return (home as NSString).appendingPathComponent(".config")
    }

    /// Linux XDG State Home ($XDG_STATE_HOME 또는 ~/.local/state).
    public static func xdgStateHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        if let stateHome = environment["XDG_STATE_HOME"], !stateHome.isEmpty {
            return (stateHome as NSString).standardizingPath
        }
        let home = homeDirectory ?? userHome(environment: environment)
        return (home as NSString).appendingPathComponent(".local/state")
    }

    /// Linux XDG Cache Home ($XDG_CACHE_HOME 또는 ~/.cache).
    public static func xdgCacheHome(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        if let cacheHome = environment["XDG_CACHE_HOME"], !cacheHome.isEmpty {
            return (cacheHome as NSString).standardizingPath
        }
        let home = homeDirectory ?? userHome(environment: environment)
        return (home as NSString).appendingPathComponent(".cache")
    }

    /// 기본 상태 디렉터리 경로 반환 로직.
    /// - macOS: `<home>/.swift-app-state`
    /// - Linux: `$XDG_DATA_HOME/swift-app-state` (기본값: `<home>/.local/share/swift-app-state`)
    public static func defaultStateDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String {
        let home = homeDirectory ?? userHome(environment: environment)
        #if os(Linux)
        return (xdgDataHome(environment: environment, homeDirectory: home) as NSString)
            .appendingPathComponent("swift-app-state")
        #else
        return (home as NSString).appendingPathComponent(".swift-app-state")
        #endif
    }
}
