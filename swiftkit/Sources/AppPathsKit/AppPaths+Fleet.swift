import Foundation
import StateRootKit

// MARK: - AppPaths Fleet Resolution & System Helpers
extension AppPaths {

    public static let open = "/usr/bin/open"
    public static let homePathAlias = "~"

    public static let systemApplicationDirectories: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
    ]

    public static let openAppLookupDirectories: [String] = [
        "/Applications",
        "/System/Applications",
    ]

    // MARK: - Effective Home Resolution

    public static func effectiveHomeDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> URL {
        if let homeDirectory {
            return homeDirectory
        }
        if StateRootKit.isRunningUnderTest(environment) {
            return URL(
                fileURLWithPath: (NSTemporaryDirectory() as NSString)
                    .appendingPathComponent("swift-app-state-root-tests"),
                isDirectory: true
            )
        }
        return DurableAppLayout.defaultHomeDirectory
    }

    // MARK: - Fleet Cascade Resolution

    public static func resolveStateRoot(
        slug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> StatePath {
        resolveStateRootWithSource(
            slug: slug,
            environment: environment,
            homeDirectory: homeDirectory
        ).0
    }

    public static func resolveStateRootWithSource(
        slug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> (StatePath, PathSource) {
        let home = effectiveHomeDirectory(environment: environment, homeDirectory: homeDirectory)

        if let res = checkAppSpecificEnv(slug: slug, environment: environment) {
            return res
        }
        if let res = checkSwiftAppStateRoot(slug: slug, environment: environment) {
            return res
        }
        return resolveFallbackCascade(slug: slug, environment: environment, home: home)
    }

    private static func resolveFallbackCascade(
        slug: String,
        environment: [String: String],
        home: URL
    ) -> (StatePath, PathSource) {
        if let res = checkSandboxRoom(slug: slug, environment: environment, home: home) {
            return res
        }
        if let res = checkXDGStateHome(slug: slug, environment: environment) {
            return res
        }
        let url = DurableAppLayout.supportRoot(slug: slug, home: home)
        return (StatePath(url: url), .macosStandard)
    }

    private static func checkAppSpecificEnv(
        slug: String,
        environment: [String: String]
    ) -> (StatePath, PathSource)? {
        let keys = candidateEnvKeys(slug: slug)
        for key in keys {
            guard let val = environment[key], !val.isEmpty else { continue }
            return (StatePath(filePath: val, isDirectory: true), .appSpecificEnv(key: key, value: val))
        }
        return nil
    }

    private static func checkSwiftAppStateRoot(
        slug: String,
        environment: [String: String]
    ) -> (StatePath, PathSource)? {
        guard let fleetRoot = environment["SWIFT_APP_STATE_ROOT"], !fleetRoot.isEmpty else {
            return nil
        }
        let bundleID = DurableAppLayout.bundleID(slug: slug)
        let url = URL(fileURLWithPath: fleetRoot, isDirectory: true)
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(bundleID, isDirectory: true)
        return (StatePath(url: url), .swiftAppStateRoot(value: fleetRoot))
    }

    private static func checkSandboxRoom(
        slug: String,
        environment: [String: String],
        home: URL
    ) -> (StatePath, PathSource)? {
        guard let roomID = environment["SANDBOX_ROOM_ID"], !roomID.isEmpty else {
            return nil
        }
        let url = home
            .appendingPathComponent(".sandboxes", isDirectory: true)
            .appendingPathComponent("room-\(roomID)", isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
        return (StatePath(url: url), .sandboxRoom(roomID: roomID))
    }

    private static func checkXDGStateHome(
        slug: String,
        environment: [String: String]
    ) -> (StatePath, PathSource)? {
        guard let xdg = environment["XDG_STATE_HOME"], !xdg.isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: xdg, isDirectory: true)
            .appendingPathComponent(slug, isDirectory: true)
        return (StatePath(url: url), .xdg(variable: "XDG_STATE_HOME", value: xdg))
    }

    public static func candidateEnvKeys(slug: String) -> [String] {
        let normalized = slug
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")
            .uppercased()
        return [
            "\(normalized)_STATE_ROOT",
            "\(normalized)_HOME",
        ]
    }

    // MARK: - Factory Methods for Slug

    public static func lockFile(
        slug: String,
        name: String = "app.lock",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> LockPath {
        let (stateRoot, _) = resolveStateRootWithSource(
            slug: slug,
            environment: environment,
            homeDirectory: homeDirectory
        )
        let filename = name.hasSuffix(".lock") ? name : "\(name).lock"
        let lockURL = stateRoot.url
            .appendingPathComponent("locks", isDirectory: true)
            .appendingPathComponent(filename, isDirectory: false)
        return LockPath(url: lockURL)
    }

    public static func sqliteURL(
        slug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> URL {
        let (stateRoot, _) = resolveStateRootWithSource(
            slug: slug,
            environment: environment,
            homeDirectory: homeDirectory
        )
        return stateRoot.url.appendingPathComponent(DurableAppLayout.sqliteFileName, isDirectory: false)
    }

    public static func cacheDirectory(
        slug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> CachePath {
        let (stateRoot, source) = resolveStateRootWithSource(
            slug: slug,
            environment: environment,
            homeDirectory: homeDirectory
        )
        switch source {
        case .macosStandard:
            let home = effectiveHomeDirectory(environment: environment, homeDirectory: homeDirectory)
            let bundleID = DurableAppLayout.bundleID(slug: slug)
            let cacheURL = home
                .appendingPathComponent("Library/Caches", isDirectory: true)
                .appendingPathComponent(bundleID, isDirectory: true)
            return CachePath(url: cacheURL)
        case .swiftAppStateRoot(let fleetRoot):
            let bundleID = DurableAppLayout.bundleID(slug: slug)
            let cacheURL = URL(fileURLWithPath: fleetRoot, isDirectory: true)
                .appendingPathComponent("Library/Caches", isDirectory: true)
                .appendingPathComponent(bundleID, isDirectory: true)
            return CachePath(url: cacheURL)
        case .sandboxRoom, .xdg, .appSpecificEnv:
            return stateRoot.cacheDirectory()
        }
    }

    // MARK: - System App Discovery

    public static func applicationSearchDirectories(
        fileManager: FileManager = .default
    ) -> [String] {
        let userApps = fileManager.urls(
            for: .applicationDirectory,
            in: .userDomainMask
        ).map(\.path)
        return systemApplicationDirectories + userApps
    }

    public static func systemAppBundleURL(
        named nameOrPath: String,
        fileManager: FileManager = .default
    ) -> URL? {
        guard !nameOrPath.hasPrefix("/") else {
            return URL(fileURLWithPath: nameOrPath)
        }
        for dir in openAppLookupDirectories {
            let candidate = URL(fileURLWithPath: dir, isDirectory: true)
                .appendingPathComponent(nameOrPath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    public static func tildeDisplay(
        of url: URL,
        home: URL = DurableAppLayout.defaultHomeDirectory
    ) -> String {
        DurableAppLayout.tildePath(url, home: home)
    }
}
