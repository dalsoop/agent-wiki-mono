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

/// `.tenants` 층 조립 규칙 — 테넌트 루트들의 부모는 호스트 홈 한 층(`~/.tenants`)뿐이다.
///
/// 실측 2026-09-25(F1EBD86C): `~/.tenants/personal/.tenants/` 밑에 테넌트 디렉터리 11개
/// (gujo·wife·personal·ranode·default…)가 쌓여 있었다. 테넌트 컨텍스트가 켜진 프로세스가
/// `StateRootKit.path(".tenants/<slug>/…")`·`url(".tenants")` 를 부르면 상태 루트가 이미
/// `~/.tenants/personal` 이라 그 밑에 테넌트 루트를 한 벌 더 조립했다. `StateRootKit` 의
/// `path`·`url`·`hostPath`·`tenantPath`·`resolve` 는 이 타입으로 잇는다.
enum TenantsLayer {
    /// 루트에 상대 경로를 잇는다. 단 `.tenants` 층을 가리키는 상대 경로(`.tenants` ·
    /// `.tenants/<slug>/…`)는 `root` 안이 아니라 `root` 가 속한 `.tenants` 층에 잇는다.
    static func join(_ root: String, _ relative: String) -> String {
        guard let remainder = remainder(relative) else {
            return (root as NSString).appendingPathComponent(relative)
        }
        let base = directory(containing: root)
        return remainder.isEmpty ? base : (base as NSString).appendingPathComponent(remainder)
    }

    /// `relative` 가 `.tenants` 층을 가리키면 그 아래 나머지(`.tenants` 자체면 빈 문자열),
    /// 아니면 nil. 앞의 `./`·`/` 는 무시한다 — `appendingPathComponent` 가 그렇게 잇는다.
    static func remainder(_ relative: String) -> String? {
        let name = StateRootKit.tenantsDirectoryName
        var trimmed = Substring(relative)
        while trimmed.hasPrefix("./") { trimmed = trimmed.dropFirst(2) }
        while trimmed.hasPrefix("/") { trimmed = trimmed.dropFirst() }
        guard trimmed.hasPrefix(name) else { return nil }
        var rest = trimmed.dropFirst(name.count)
        guard rest.isEmpty || rest.hasPrefix("/") else { return nil }  // `.tenants-x` 는 다른 이름
        while rest.hasPrefix("/") { rest = rest.dropFirst() }
        return String(rest)
    }

    /// `root` 의 경로 성분에 `.tenants` 가 있으면 그 층까지 올라가고, 없으면 `<root>/.tenants`.
    /// `URL(fileURLWithPath:)` 를 쓰지 않는다 — 상대 루트를 cwd 기준으로 펴 버리면 예전
    /// `appendingPathComponent` 조립과 결과가 갈린다.
    static func directory(containing root: String) -> String {
        let name = StateRootKit.tenantsDirectoryName
        let components = (root as NSString).pathComponents
        if let index = components.lastIndex(of: name) {
            return NSString.path(withComponents: Array(components[...index]))
        }
        return (root as NSString).appendingPathComponent(name)
    }
}
