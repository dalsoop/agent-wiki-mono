#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
#if canImport(os)
import os
#endif

/// 빌드 결과 해시 캐시 — 동일 소스 해시면 설치(install)를 즉시 skip 한다.
///
/// 빌드 성공 시 계산된 소스 해시를 `/tmp/gujo-build-hash/<slug>.hash` (및 메타데이터 JSON)에 영속화하고,
/// stale 판정(`isStale`) 시 기존의 불안정한 mtime(수정시각) 대신 소스 콘텐츠 해시를 대조한다.
/// 해시가 일치하면 `isStale: false` (0초 즉각 skip).
public enum BuildHashCache: Sendable {

    /// 기본 캐시 디렉터리 경로 (/tmp/gujo-build-hash)
    public static let defaultCacheDirectory: URL = URL(fileURLWithPath: "/tmp/gujo-build-hash", isDirectory: true)

    #if canImport(os)
    private static let _customCacheDirectoryLock = OSAllocatedUnfairLock<URL?>(initialState: nil)
    private static let _ioLock = OSAllocatedUnfairLock()
    #else
    private static let _customCacheDirectoryLock = NSLock()
    private static nonisolated(unsafe) var _customCacheDirectoryStorage: URL? = nil
    private static let _ioLock = NSLock()
    #endif

    /// 테스트 또는 환경 오버라이드용 커스텀 캐시 디렉터리 (OSAllocatedUnfairLock 원자적 보호)
    public static var customCacheDirectory: URL? {
        get {
            #if canImport(os)
            return _customCacheDirectoryLock.withLock { $0 }
            #else
            _customCacheDirectoryLock.lock()
            defer { _customCacheDirectoryLock.unlock() }
            return _customCacheDirectoryStorage
            #endif
        }
        set {
            #if canImport(os)
            _customCacheDirectoryLock.withLock { $0 = newValue }
            #else
            _customCacheDirectoryLock.lock()
            defer { _customCacheDirectoryLock.unlock() }
            _customCacheDirectoryStorage = newValue
            #endif
        }
    }

    /// 현재 활성 캐시 디렉터리
    public static var cacheDirectory: URL {
        customCacheDirectory ?? defaultCacheDirectory
    }

    @discardableResult
    private static func withIOLock<T: Sendable>(_ body: @Sendable () throws -> T) rethrows -> T {
        #if canImport(os)
        return try _ioLock.withLock {
            try body()
        }
        #else
        _ioLock.lock()
        defer { _ioLock.unlock() }
        return try body()
        #endif
    }

    /// 캐시 메타데이터
    public struct Metadata: Codable, Sendable, Equatable {
        public let slug: String
        public let sourceHash: String
        public let builtAt: String
        public let appPath: String?

        public init(
            slug: String,
            sourceHash: String,
            builtAt: String = ISO8601DateFormatter().string(from: Date()),
            appPath: String? = nil
        ) {
            self.slug = slug
            self.sourceHash = sourceHash
            self.builtAt = builtAt
            self.appPath = appPath
        }
    }

    /// 슬러그에 대응하는 캐시 파일 URL 반환 (`/tmp/gujo-build-hash/<slug>.hash`)
    public static func cacheFileURL(for slug: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? cacheDirectory
        let safeSlug = sanitizeSlug(slug)
        return dir.appendingPathComponent("\(safeSlug).hash")
    }

    /// 슬러그에 대응하는 메타데이터 파일 URL 반환 (`/tmp/gujo-build-hash/<slug>.json`)
    public static func metadataFileURL(for slug: String, in directory: URL? = nil) -> URL {
        let dir = directory ?? cacheDirectory
        let safeSlug = sanitizeSlug(slug)
        return dir.appendingPathComponent("\(safeSlug).json")
    }

    /// 캐시된 소스 해시 문자열 조회
    public static func cachedHash(for slug: String, in directory: URL? = nil) -> String? {
        withIOLock {
            let hashURL = cacheFileURL(for: slug, in: directory)
            do {
                let raw = try String(contentsOf: hashURL, encoding: .utf8)
                if let parsed = parseHash(from: raw) {
                    return parsed
                }
            } catch {
                _ = error
            }
            return fallbackHashFromMetadata(for: slug, in: directory)
        }
    }

    private static func parseHash(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let openBrace: Character = "\u{7B}"
        guard trimmed.first == openBrace else { return trimmed }
        guard let data = trimmed.data(using: .utf8),
              let meta = try? JSONDecoder().decode(Metadata.self, from: data) else {
            return trimmed
        }
        return meta.sourceHash
    }

    private static func fallbackHashFromMetadata(for slug: String, in directory: URL?) -> String? {
        let metaURL = metadataFileURL(for: slug, in: directory)
        do {
            let data = try Data(contentsOf: metaURL)
            let meta = try JSONDecoder().decode(Metadata.self, from: data)
            return meta.sourceHash
        } catch {
            return nil
        }
    }

    /// 캐시된 메타데이터 조회
    public static func cachedMetadata(for slug: String, in directory: URL? = nil) -> Metadata? {
        withIOLock {
            let metaURL = metadataFileURL(for: slug, in: directory)
            do {
                let data = try Data(contentsOf: metaURL)
                return try JSONDecoder().decode(Metadata.self, from: data)
            } catch {
                return nil
            }
        }
    }

    /// 빌드 성공 시 소스 해시 영속화
    public static func store(
        slug: String,
        hash: String,
        appPath: String? = nil,
        in directory: URL? = nil
    ) {
        withIOLock {
            let dir = directory ?? cacheDirectory
            let fm = FileManager.default
            do {
                if !fm.fileExists(atPath: dir.path) {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                let hashURL = cacheFileURL(for: slug, in: dir)
                try hash.write(to: hashURL, atomically: true, encoding: .utf8)

                let metaURL = metadataFileURL(for: slug, in: dir)
                let meta = Metadata(slug: sanitizeSlug(slug), sourceHash: hash, appPath: appPath)
                let data = try JSONEncoder().encode(meta)
                try data.write(to: metaURL, options: .atomic)
            } catch {
                FileHandle.standardError.write(Data("BuildHashCache store 실패: \(error)\n".utf8))
            }
        }
    }

    /// 빌드 성공 시 소스 해시 영속화 (`store` 와 동일)
    public static func record(
        slug: String,
        hash: String,
        appPath: String? = nil,
        in directory: URL? = nil
    ) {
        store(slug: slug, hash: hash, appPath: appPath, in: directory)
    }

    /// 앱 디렉터리의 현재 소스 해시를 계산하여 빌드 성공 캐시를 저장한다.
    @discardableResult
    public static func store(
        slug: String,
        appDirectory: URL,
        in directory: URL? = nil
    ) -> String? {
        guard let hash = ContentHasher.computeHash(for: appDirectory) else { return nil }
        store(slug: slug, hash: hash, appPath: appDirectory.path, in: directory)
        return hash
    }

    /// 앱 디렉터리의 현재 소스 해시를 계산하여 빌드 성공 캐시를 저장한다 (`store` 와 동일).
    @discardableResult
    public static func record(
        slug: String,
        appDirectory: URL,
        in directory: URL? = nil
    ) -> String? {
        store(slug: slug, appDirectory: appDirectory, in: directory)
    }

    /// 소스 변경 여부(stale) 판정.
    ///
    /// 기존 mtime 비교 대신 현재 소스 해시와 캐시된 해시를 비교한다.
    /// - 캐시가 없거나 해시가 다르면 `true` (stale - 빌드/설치 필요)
    /// - 해시가 동일하면 `false` (최신 - 0초 즉각 skip 가능)
    public static func isStale(
        slug: String,
        currentHash: String,
        in directory: URL? = nil
    ) -> Bool {
        guard let cached = cachedHash(for: slug, in: directory) else {
            return true
        }
        return cached != currentHash
    }

    /// 앱 디렉터리 기반 stale 판정
    public static func isStale(
        slug: String,
        appDirectory: URL,
        in directory: URL? = nil
    ) -> Bool {
        guard let currentHash = ContentHasher.computeHash(for: appDirectory) else {
            return true
        }
        return isStale(slug: slug, currentHash: currentHash, in: directory)
    }

    /// 앱 경로 문자열 기반 stale 판정
    public static func isStale(
        slug: String,
        appPath: String,
        in directory: URL? = nil
    ) -> Bool {
        isStale(
            slug: slug,
            appDirectory: URL(fileURLWithPath: appPath, isDirectory: true),
            in: directory
        )
    }

    /// 동일 해시인지 확인하여 설치 skip 여부 반환 (`!isStale(...)` 과 동일)
    public static func shouldSkipInstall(
        slug: String,
        currentHash: String,
        in directory: URL? = nil
    ) -> Bool {
        !isStale(slug: slug, currentHash: currentHash, in: directory)
    }

    /// 동일 소스 해시인지 확인하여 설치 skip 여부 반환
    public static func shouldSkipInstall(
        slug: String,
        appDirectory: URL,
        in directory: URL? = nil
    ) -> Bool {
        !isStale(slug: slug, appDirectory: appDirectory, in: directory)
    }

    /// 동일 소스 해시인지 확인하여 설치 skip 여부 반환
    public static func shouldSkipInstall(
        slug: String,
        appPath: String,
        in directory: URL? = nil
    ) -> Bool {
        !isStale(slug: slug, appPath: appPath, in: directory)
    }

    /// 캐시된 해시가 최신(동일)인지 판정 (`!isStale(...)` 과 동일)
    public static func isCurrent(
        slug: String,
        currentHash: String,
        in directory: URL? = nil
    ) -> Bool {
        !isStale(slug: slug, currentHash: currentHash, in: directory)
    }

    /// 앱 디렉터리 기반 캐시 최신 여부 판정 (`!isStale(...)` 과 동일)
    public static func isCurrent(
        slug: String,
        appDirectory: URL,
        in directory: URL? = nil
    ) -> Bool {
        !isStale(slug: slug, appDirectory: appDirectory, in: directory)
    }

    /// 앱 경로 문자열 기반 캐시 최신 여부 판정 (`!isStale(...)` 과 동일)
    public static func isCurrent(
        slug: String,
        appPath: String,
        in directory: URL? = nil
    ) -> Bool {
        !isStale(slug: slug, appPath: appPath, in: directory)
    }

    /// 특정 슬러그 캐시 무효화 (삭제)
    public static func invalidate(slug: String, in directory: URL? = nil) {
        withIOLock {
            let dir = directory ?? cacheDirectory
            let hashURL = cacheFileURL(for: slug, in: dir)
            let metaURL = metadataFileURL(for: slug, in: dir)
            try? FileManager.default.removeItem(at: hashURL)
            try? FileManager.default.removeItem(at: metaURL)
        }
    }

    /// 특정 슬러그의 stale 캐시 무효화/삭제 (`invalidate` 와 동일)
    public static func cleanStale(slug: String, in directory: URL? = nil) {
        invalidate(slug: slug, in: directory)
    }

    /// 캐시 디렉터리 내 지정 시간(초) 이상 경과한 stale 캐시 파일 정리
    @discardableResult
    public static func cleanStale(in directory: URL? = nil, olderThan threshold: TimeInterval = 86400 * 7) -> Int {
        withIOLock {
            let dir = directory ?? cacheDirectory
            let fm = FileManager.default
            guard let contents = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else {
                return 0
            }
            let now = Date()
            var removedCount = 0
            for fileURL in contents {
                guard fileURL.pathExtension == "hash" || fileURL.pathExtension == "json" else { continue }
                guard let attrs = try? fm.attributesOfItem(atPath: fileURL.path) else { continue }
                if let modDate = attrs[.modificationDate] as? Date,
                   now.timeIntervalSince(modDate) > threshold {
                    do {
                        try fm.removeItem(at: fileURL)
                        removedCount += 1
                    } catch {
                        _ = error
                    }
                }
            }
            return removedCount
        }
    }

    /// 캐시 디렉터리 전체 삭제
    public static func purge(in directory: URL? = nil) {
        withIOLock {
            let dir = directory ?? cacheDirectory
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Helpers

    public static func sanitizeSlug(_ slug: String) -> String {
        let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed
    }
}
