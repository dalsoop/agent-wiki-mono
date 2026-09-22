import Foundation
import StateRootKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - App Paths Error
public enum AppPathsError: Error, LocalizedError, Equatable, Sendable {
    case notADirectory(String)
    case permissionFailed(path: String, errno: Int32)
    case invalidPath(String)

    public var errorDescription: String? {
        switch self {
        case .notADirectory(let path):
            return "경로가 디렉터리가 아닙니다: \(path)"
        case .permissionFailed(let path, let code):
            return "디렉터리 권한(POSIX 0o700) 설정 실패 [errno: \(code)]: \(path)"
        case .invalidPath(let path):
            return "유효하지 않은 경로입니다: \(path)"
        }
    }
}

// MARK: - Path Source
public enum PathSource: Sendable, Equatable {
    case appSpecificEnv(key: String, value: String)
    case swiftAppStateRoot(value: String)
    case sandboxRoom(roomID: String)
    case xdg(variable: String, value: String)
    case macosStandard
}

// MARK: - AppPaths
public struct AppPaths: Sendable, Equatable {
    public var root: URL
    public let slug: String?
    public let source: PathSource

    public init(root: URL) {
        self.root = root.standardizedFileURL
        self.slug = nil
        self.source = .macosStandard
    }

    public init(root: URL, slug: String?, source: PathSource = .macosStandard) {
        self.root = root.standardizedFileURL
        self.slug = slug
        self.source = source
    }

    public init(
        slug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) {
        let (resolvedPath, resolvedSource) = Self.resolveStateRootWithSource(
            slug: slug,
            environment: environment,
            homeDirectory: homeDirectory
        )
        self.root = resolvedPath.url
        self.slug = slug
        self.source = resolvedSource
    }

    // MARK: - Factory Constructors
    public static func applicationSupport(_ appName: String) -> AppPaths {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppPaths(
            root: base.appendingPathComponent(appName, isDirectory: true),
            slug: appName,
            source: .macosStandard
        )
    }

    public static func applicationSupport(slug: String) -> AppPaths {
        applicationSupport(slug)
    }

    public static func homeDotDir(_ appName: String) -> AppPaths {
        AppPaths(root: StateRootKit.url(".\(appName)"), slug: appName, source: .macosStandard)
    }

    public static func resolve(
        slug: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil
    ) -> AppPaths {
        AppPaths(slug: slug, environment: environment, homeDirectory: homeDirectory)
    }

    // MARK: - POSIX Permission & Directory Helpers
    @discardableResult
    public static func ensureDirectory(
        at url: URL,
        permissions: Int = 0o700,
        fileManager: FileManager = .default
    ) throws -> URL {
        let standardized = url.standardizedFileURL
        let path = standardized.path
        var isDir: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDir) else {
            try fileManager.createDirectory(
                at: standardized,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: NSNumber(value: permissions)]
            )
            try applyDirectoryPermissions(atPath: path, permissions: permissions)
            return standardized
        }

        guard isDir.boolValue else {
            throw AppPathsError.notADirectory(path)
        }

        try applyDirectoryPermissions(atPath: path, permissions: permissions)
        return standardized
    }

    private static func applyDirectoryPermissions(atPath path: String, permissions: Int) throws {
        #if canImport(Darwin)
        guard Darwin.chmod(path, mode_t(permissions)) == 0 else {
            let err = errno
            guard err == EPERM else {
                throw AppPathsError.permissionFailed(path: path, errno: err)
            }
            return
        }
        #elseif canImport(Glibc)
        guard Glibc.chmod(path, mode_t(permissions)) == 0 else {
            let err = errno
            guard err == EPERM else {
                throw AppPathsError.permissionFailed(path: path, errno: err)
            }
            return
        }
        #endif
    }

    @discardableResult
    public static func ensureDirectory(
        atPath path: String,
        permissions: Int = 0o700,
        fileManager: FileManager = .default
    ) throws -> String {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let ensured = try ensureDirectory(at: url, permissions: permissions, fileManager: fileManager)
        return ensured.path
    }

    // MARK: - Path Helpers
    public func file(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: false)
    }

    public func directory(_ name: String) -> URL {
        root.appendingPathComponent(name, isDirectory: true)
    }

    public var stateFile: URL { file("state.json") }
    public var settingsFile: URL { file("settings.json") }
    public var sqliteFile: URL { file(DurableAppLayout.sqliteFileName) }
    public var statePath: StatePath { StatePath(url: root) }

    public var cachePath: CachePath {
        if let slug = slug { return Self.cacheDirectory(slug: slug) }
        return CachePath(url: root.appendingPathComponent("cache", isDirectory: true))
    }

    public func lockFile(name: String = "app.lock") -> LockPath {
        if let slug = slug { return Self.lockFile(slug: slug, name: name) }
        let filename = name.hasSuffix(".lock") ? name : "\(name).lock"
        return LockPath(url: root.appendingPathComponent("locks", isDirectory: true).appendingPathComponent(filename))
    }

    public var lockFile: LockPath { lockFile(name: "app.lock") }
    public var lockFileURL: URL { lockFile.url }

    @discardableResult
    public func ensureDirectory(permissions: Int = 0o700) throws -> AppPaths {
        try Self.ensureDirectory(at: root, permissions: permissions)
        return self
    }
}
