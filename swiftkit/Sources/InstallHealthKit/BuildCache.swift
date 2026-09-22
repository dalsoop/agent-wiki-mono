#if canImport(CryptoKit)
import CryptoKit
#endif
import Foundation
import StateRootKit

/// 빌드 결과 해시 캐시 — 소스가 안 바뀌었으면 install 을 skip 한다.
///
/// 흐름: `InstallLock.withLock` 안에서
/// 1. `BuildCache.hit(appPath:root:)` → non-nil 이면 빌드 skip
/// 2. miss → swift build → `BuildCache.store(appPath:root:)`
/// 3. 다른 세션이 락 잡고 재확인 → 높은 확률로 hit
///
/// 캐시 키 = `InstallProvenance.sourceHash` (Merkle-ish SHA256 of .swift files).
/// 실제 바이너리를 복사하지 않는다 — "이 해시로 이미 설치됨" 플래그만.
public enum BuildCache {

    public static var cacheDirectory: URL {
        StateRootKit.url(".agent-ops/build-cache")
    }

    /// 캐시 히트 — 이 소스 해시로 이미 설치된 적 있으면 기록 반환.
    public static func hit(appPath: String, root: String) -> CacheEntry? {
        guard let key = cacheKey(appPath: appPath, root: root) else { return nil }
        let url = cacheDirectory.appendingPathComponent("\(key).json")
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(CacheEntry.self, from: data)
        } catch {
            let slug = (appPath as NSString).lastPathComponent
            if let cached = BuildHashCache.cachedHash(for: slug), cached == key {
                return CacheEntry(sourceHash: key, appPath: appPath, builtAt: "")
            }
            return nil
        }
    }

    /// 빌드 완료 후 캐시 기록.
    public static func store(appPath: String, root: String) {
        guard let key = cacheKey(appPath: appPath, root: root) else { return }
        let fm = FileManager.default
        let dir = cacheDirectory
        do {
            if !fm.fileExists(atPath: dir.path) {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let entry = CacheEntry(
                sourceHash: key,
                appPath: appPath,
                builtAt: ISO8601DateFormatter().string(from: Date())
            )
            let data = try JSONEncoder().encode(entry)
            try data.write(to: dir.appendingPathComponent("\(key).json"), options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("BuildCache 쓰기 실패: \(error)\n".utf8))
        }
        let slug = (appPath as NSString).lastPathComponent
        BuildHashCache.store(slug: slug, hash: key, appPath: appPath)
    }

    /// 수동 캐시 무효화.
    public static func invalidate(appPath: String, root: String) {
        guard let key = cacheKey(appPath: appPath, root: root) else { return }
        try? FileManager.default.removeItem(
            at: cacheDirectory.appendingPathComponent("\(key).json"))
        let slug = (appPath as NSString).lastPathComponent
        BuildHashCache.invalidate(slug: slug)
    }

    /// 전체 캐시 삭제.
    public static func purge() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        BuildHashCache.purge()
    }

    // MARK: - Types

    public struct CacheEntry: Codable, Sendable {
        public let sourceHash: String
        public let appPath: String
        public let builtAt: String
    }

    // MARK: - Private

    static func cacheKey(appPath: String, root: String) -> String? {
        InstallProvenance.sourceHash(appPath: appPath, root: root)
    }
}
