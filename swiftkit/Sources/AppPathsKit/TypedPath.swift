import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Path Categories (Phantom Types)

/// 정적 타입 세이프 경로를 위한 팬텀 타입 프로토콜.
public protocol PathCategory: Sendable, Equatable, Hashable {}

/// 영속적인 앱 상태(설정, 원장, SQLite 데이터베이스 등)를 저장하는 경로 카테고리.
public enum StateCategory: PathCategory {}

/// 언제든 삭제되거나 재생성 가능한 임시/캐시 데이터를 저장하는 경로 카테고리.
public enum CacheCategory: PathCategory {}

/// 프로세스 간 상호 배제 및 동기화를 위한 파일 락(flock 등) 경로 카테고리.
public enum LockCategory: PathCategory {}

// MARK: - Type Aliases

/// 영속 상태 경로 (`TypedPath<StateCategory>`)
public typealias StatePath = TypedPath<StateCategory>

/// 캐시 경로 (`TypedPath<CacheCategory>`)
public typealias CachePath = TypedPath<CacheCategory>

/// 락 파일 경로 (`TypedPath<LockCategory>`)
public typealias LockPath = TypedPath<LockCategory>

// MARK: - TypedPath

/// 팬텀 타입 `Category`를 통해 컴파일 타임에 상태(State), 캐시(Cache), 잠금(Lock) 경로의 오용을 방지하는 정적 타입 세이프 경로 구조체.
///
/// SwiftPM `AbsolutePath`, Tuist `Path`, Cargo 파일시스템 레이아웃의 안전성 모범 사례를 따릅니다.
public struct TypedPath<Category: PathCategory>:
    Sendable,
    Equatable,
    Hashable,
    Comparable,
    CustomStringConvertible,
    Codable,
    ExpressibleByStringLiteral
{

    /// 표준화된 파일 URL
    public let url: URL

    /// 파일시스템 절대 경로 문자열
    public var path: String {
        url.path
    }

    /// 파일 URL 표현
    public var fileURL: URL {
        url
    }

    /// 경로의 마지막 컴포넌트 (파일명 또는 디렉터리명)
    public var lastPathComponent: String {
        url.lastPathComponent
    }

    /// 파일 확장자 (점 제외)
    public var pathExtension: String {
        url.pathExtension
    }

    /// 확장자가 제거된 경로
    public var deletingPathExtension: TypedPath<Category> {
        TypedPath(url: url.deletingPathExtension())
    }

    /// 마지막 컴포넌트가 제거된 부모 경로 (URL)
    public var parentDirectory: URL {
        url.deletingLastPathComponent()
    }

    /// 마지막 컴포넌트가 제거된 부모 경로 (`TypedPath`)
    public var deletingLastPathComponent: TypedPath<Category> {
        TypedPath(url: url.deletingLastPathComponent())
    }

    /// 파일 또는 디렉터리의 실존 여부
    public var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// 해당 경로가 디렉터리인지 여부
    public var isDirectory: Bool {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            return isDir.boolValue
        }
        return url.hasDirectoryPath
    }

    /// 홈 디렉터리 기준 틸드(`~`) 축약 경로
    public var tildePath: String {
        DurableAppLayout.tildePath(url)
    }

    // MARK: - Initializers

    public init(url: URL) {
        self.url = url.standardizedFileURL
    }

    public init(filePath: String, isDirectory: Bool = false) {
        self.url = URL(fileURLWithPath: filePath, isDirectory: isDirectory).standardizedFileURL
    }

    public init(_ url: URL) {
        self.init(url: url)
    }

    public init(stringLiteral value: String) {
        self.init(filePath: value)
    }

    // MARK: - Path Operations

    /// 하위 컴포넌트를 덧붙인 동일 카테고리의 `TypedPath`를 반환합니다.
    public func appending(_ component: String, isDirectory: Bool = false) -> TypedPath<Category> {
        TypedPath(url: url.appendingPathComponent(component, isDirectory: isDirectory))
    }

    /// 여러 하위 컴포넌트를 순서대로 덧붙인 동일 카테고리의 `TypedPath`를 반환합니다.
    public func appending(components: [String], isDirectory: Bool = false) -> TypedPath<Category> {
        var current = url
        for (index, comp) in components.enumerated() {
            let isLast = index == (components.count - 1)
            current = current.appendingPathComponent(comp, isDirectory: isLast ? isDirectory : true)
        }
        return TypedPath(url: current)
    }

    /// 파일 확장자를 덧붙인 경로를 반환합니다.
    public func appendingPathExtension(_ ext: String) -> TypedPath<Category> {
        TypedPath(url: url.appendingPathExtension(ext))
    }

    // MARK: - Type-Safe Category Conversion

    /// 명시적으로 카테고리를 변환합니다 (예: State 경로 내 특정 하위 파일을 Lock 경로로 전환할 때 등).
    public func unsafeCast<NewCategory: PathCategory>() -> TypedPath<NewCategory> {
        TypedPath<NewCategory>(url: url)
    }

    // MARK: - POSIX / Directory Helpers

    /// 이 경로가 가리키는 디렉터리가 존재하도록 보장하며, POSIX 퍼미션(기본 0o700)을 강제 적용합니다.
    @discardableResult
    public func ensureDirectory(permissions: Int = 0o700) throws -> TypedPath<Category> {
        try AppPaths.ensureDirectory(at: url, permissions: permissions)
        return self
    }

    /// 부모 디렉터리가 존재하도록 보장하며, POSIX 퍼미션(기본 0o700)을 강제 적용합니다.
    @discardableResult
    public func ensureParentDirectory(permissions: Int = 0o700) throws -> TypedPath<Category> {
        try AppPaths.ensureDirectory(at: url.deletingLastPathComponent(), permissions: permissions)
        return self
    }

    // MARK: - Protocol Conformances

    public var description: String {
        path
    }

    public static func < (lhs: TypedPath<Category>, rhs: TypedPath<Category>) -> Bool {
        lhs.path < rhs.path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawPath = try container.decode(String.self)
        self.init(filePath: rawPath)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
}

// MARK: - Category Specific Extensions

extension TypedPath where Category == StateCategory {
    /// 관례상 주 상태 파일 (`state.json`)
    public var stateFile: StatePath {
        appending("state.json")
    }

    /// 관례상 설정 파일 (`settings.json`)
    public var settingsFile: StatePath {
        appending("settings.json")
    }

    /// SQLite 데이터베이스 파일 (`app.sqlite`)
    public var sqliteFile: StatePath {
        appending(DurableAppLayout.sqliteFileName)
    }

    /// 상태 디렉터리 내 하위 파일 경로를 반환합니다.
    public func file(_ name: String) -> StatePath {
        appending(name, isDirectory: false)
    }

    /// 상태 디렉터리 내 하위 디렉터리 경로를 반환합니다.
    public func directory(_ name: String) -> StatePath {
        appending(name, isDirectory: true)
    }

    /// 상태 경로와 연계된 락 파일을 생성합니다.
    public func lockFile(name: String = "app.lock") -> LockPath {
        let filename = name.hasSuffix(".lock") ? name : "\(name).lock"
        return appending("locks", isDirectory: true).appending(filename).unsafeCast()
    }

    /// 상태 경로와 연계된 캐시 디렉터리를 반환합니다.
    public func cacheDirectory(name: String = "cache") -> CachePath {
        appending(name, isDirectory: true).unsafeCast()
    }
}

extension TypedPath where Category == LockCategory {
    /// 파일 락(`FastFileLock`)을 취득한 상태에서 클로저를 실행합니다.
    ///
    /// 부모 디렉터리가 없으면 0o700 퍼미션으로 자동 생성합니다.
    public func withFileLock<T>(shared: Bool = false, _ body: () throws -> T) throws -> T {
        try FastFileLock.withLock(at: url, exclusive: !shared, body)
    }
}
