import Foundation
@_exported import FastDiskIOKit

/// AppPathsKit 전용 FastFileLock 편의 확장.
/// 심볼 정본은 `FastDiskIOKit.FastFileLock`이며, 여기서는 AppPaths 규격 경로 연동 오버로드만 제공합니다.
extension FastFileLock {

    /// 슬러그와 락 파일 이름을 받아 AppPaths 정본 락 경로에서 파일 락을 취득하고 클로저를 실행합니다.
    @discardableResult
    public static func withLock<T>(
        slug: String,
        name: String = "app.lock",
        exclusive: Bool = true,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL? = nil,
        _ body: () throws -> T
    ) throws -> T {
        let lockPath = AppPaths.lockFile(
            slug: slug,
            name: name,
            environment: environment,
            homeDirectory: homeDirectory
        )
        return try withLock(at: lockPath.url, exclusive: exclusive, body)
    }

    /// LockPath 정본 인스턴스에서 파일 락을 취득하고 클로저를 실행합니다.
    @discardableResult
    public static func withLock<T>(
        _ lockPath: LockPath,
        exclusive: Bool = true,
        _ body: () throws -> T
    ) throws -> T {
        try withLock(at: lockPath.url, exclusive: exclusive, body)
    }
}
