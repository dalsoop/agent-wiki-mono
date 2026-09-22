import Foundation

/// InstallHealthKit 의 소스 해싱, 빌드 캐시 및 설치 건강성 관리 통합 인터페이스.
public enum InstallHealth: Sendable {

    // MARK: - Content Hashing

    /// 대상 디렉터리의 결정론적 소스 콘텐츠 해시 계산
    public static func computeSourceHash(directory: URL) -> String? {
        ContentHasher.computeHash(for: directory)
    }

    /// 대상 디렉터리 경로(String)의 결정론적 소스 콘텐츠 해시 계산
    public static func computeSourceHash(directoryPath: String) -> String? {
        ContentHasher.computeHash(forDirectoryPath: directoryPath)
    }

    // MARK: - Build Hash Cache & Stale Check

    /// 소스 해시 기반 stale 판정 (캐시와 동일 해시면 false)
    public static func isStale(slug: String, currentHash: String, in directory: URL? = nil) -> Bool {
        BuildHashCache.isStale(slug: slug, currentHash: currentHash, in: directory)
    }

    /// 앱 디렉터리의 소스 해시 기반 stale 판정
    public static func isStale(slug: String, appDirectory: URL, in directory: URL? = nil) -> Bool {
        BuildHashCache.isStale(slug: slug, appDirectory: appDirectory, in: directory)
    }

    /// 앱 경로의 소스 해시 기반 stale 판정
    public static func isStale(slug: String, appPath: String, in directory: URL? = nil) -> Bool {
        BuildHashCache.isStale(slug: slug, appPath: appPath, in: directory)
    }

    /// 빌드 성공 기록: 소스 해시 영속화
    public static func recordBuildSuccess(slug: String, hash: String, appPath: String? = nil, in directory: URL? = nil) {
        BuildHashCache.store(slug: slug, hash: hash, appPath: appPath, in: directory)
    }

    /// 빌드 성공 기록: 디렉터리 소스 해시 계산 후 영속화
    @discardableResult
    public static func recordBuildSuccess(slug: String, appDirectory: URL, in directory: URL? = nil) -> String? {
        BuildHashCache.store(slug: slug, appDirectory: appDirectory, in: directory)
    }

    /// 빌드 성공 기록: 경로 소스 해시 계산 후 영속화
    @discardableResult
    public static func recordBuildSuccess(slug: String, appPath: String, in directory: URL? = nil) -> String? {
        recordBuildSuccess(slug: slug, appDirectory: URL(fileURLWithPath: appPath, isDirectory: true), in: directory)
    }

    /// 설치 생략(skip) 가능 여부 확인
    public static func shouldSkipInstall(slug: String, currentHash: String, in directory: URL? = nil) -> Bool {
        BuildHashCache.shouldSkipInstall(slug: slug, currentHash: currentHash, in: directory)
    }

    /// 설치 생략(skip) 가능 여부 확인
    public static func shouldSkipInstall(slug: String, appDirectory: URL, in directory: URL? = nil) -> Bool {
        BuildHashCache.shouldSkipInstall(slug: slug, appDirectory: appDirectory, in: directory)
    }

    /// 설치 생략(skip) 가능 여부 확인
    public static func shouldSkipInstall(slug: String, appPath: String, in directory: URL? = nil) -> Bool {
        BuildHashCache.shouldSkipInstall(slug: slug, appPath: appPath, in: directory)
    }

    // MARK: - Concurrency Safe Record, isCurrent, cleanStale Conveniences

    public static func record(slug: String, hash: String, appPath: String? = nil, in directory: URL? = nil) {
        BuildHashCache.record(slug: slug, hash: hash, appPath: appPath, in: directory)
    }

    @discardableResult
    public static func record(slug: String, appDirectory: URL, in directory: URL? = nil) -> String? {
        BuildHashCache.record(slug: slug, appDirectory: appDirectory, in: directory)
    }

    public static func isCurrent(slug: String, currentHash: String, in directory: URL? = nil) -> Bool {
        BuildHashCache.isCurrent(slug: slug, currentHash: currentHash, in: directory)
    }

    public static func isCurrent(slug: String, appDirectory: URL, in directory: URL? = nil) -> Bool {
        BuildHashCache.isCurrent(slug: slug, appDirectory: appDirectory, in: directory)
    }

    public static func cleanStale(slug: String, in directory: URL? = nil) {
        BuildHashCache.cleanStale(slug: slug, in: directory)
    }

    @discardableResult
    public static func cleanStale(in directory: URL? = nil, olderThan threshold: TimeInterval = 86400 * 7) -> Int {
        BuildHashCache.cleanStale(in: directory, olderThan: threshold)
    }
}
