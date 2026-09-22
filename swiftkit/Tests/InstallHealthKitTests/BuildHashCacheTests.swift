import Foundation
import XCTest
@testable import InstallHealthKit

final class BuildHashCacheTests: XCTestCase {

    private var tempDir: URL!
    private var cacheDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BuildHashCacheTests-\(UUID().uuidString)", isDirectory: true)
        cacheDir = tempDir.appendingPathComponent("build-hash-cache", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    /// 해시 영속화 및 정상 조회 검증
    func testStoreAndReadCachedHash() {
        let slug = "test-app"
        let hash = "abc123456789abcdef0123456789abcdef012345"

        BuildHashCache.store(slug: slug, hash: hash, in: cacheDir)

        let retrieved = BuildHashCache.cachedHash(for: slug, in: cacheDir)
        XCTAssertEqual(retrieved, hash)

        let meta = BuildHashCache.cachedMetadata(for: slug, in: cacheDir)
        XCTAssertNotNil(meta)
        XCTAssertEqual(meta?.slug, slug)
        XCTAssertEqual(meta?.sourceHash, hash)
    }

    /// 동일 해시면 isStale: false (즉시 skip 가능) 검증
    func testIsStaleReturnsFalseWhenHashMatches() {
        let slug = "fresh-app"
        let hash = "hash-value-1111"

        BuildHashCache.store(slug: slug, hash: hash, in: cacheDir)

        let stale = BuildHashCache.isStale(slug: slug, currentHash: hash, in: cacheDir)
        XCTAssertFalse(stale, "동일한 해시일 경우 isStale 은 false 여야 합니다.")

        let shouldSkip = BuildHashCache.shouldSkipInstall(slug: slug, currentHash: hash, in: cacheDir)
        XCTAssertTrue(shouldSkip, "동일한 해시일 경우 shouldSkipInstall 은 true 여야 합니다.")
    }

    /// 해시가 다르면 isStale: true (빌드/설치 필요) 검증
    func testIsStaleReturnsTrueWhenHashDiffers() {
        let slug = "modified-app"
        let oldHash = "hash-value-old"
        let newHash = "hash-value-new"

        BuildHashCache.store(slug: slug, hash: oldHash, in: cacheDir)

        let stale = BuildHashCache.isStale(slug: slug, currentHash: newHash, in: cacheDir)
        XCTAssertTrue(stale, "해시가 다를 경우 isStale 은 true 여야 합니다.")

        let shouldSkip = BuildHashCache.shouldSkipInstall(slug: slug, currentHash: newHash, in: cacheDir)
        XCTAssertFalse(shouldSkip, "해시가 다를 경우 shouldSkipInstall 은 false 여야 합니다.")
    }

    /// 캐시가 없을 때 isStale: true 검증
    func testIsStaleReturnsTrueWhenCacheMissing() {
        let slug = "uncached-app"
        let stale = BuildHashCache.isStale(slug: slug, currentHash: "any-hash", in: cacheDir)
        XCTAssertTrue(stale, "캐시가 없으면 isStale 은 true 여야 합니다.")
    }

    /// 캐시 무효화(invalidate) 동작 검증
    func testInvalidateRemovesCache() {
        let slug = "invalidated-app"
        let hash = "hash-to-remove"

        BuildHashCache.store(slug: slug, hash: hash, in: cacheDir)
        XCTAssertEqual(BuildHashCache.cachedHash(for: slug, in: cacheDir), hash)

        BuildHashCache.invalidate(slug: slug, in: cacheDir)
        XCTAssertNil(BuildHashCache.cachedHash(for: slug, in: cacheDir))
        XCTAssertNil(BuildHashCache.cachedMetadata(for: slug, in: cacheDir))
    }

    /// 캐시 전체 삭제(purge) 동작 검증
    func testPurgeRemovesEntireDirectory() {
        BuildHashCache.store(slug: "app-1", hash: "hash1", in: cacheDir)
        BuildHashCache.store(slug: "app-2", hash: "hash2", in: cacheDir)

        BuildHashCache.purge(in: cacheDir)
        XCTAssertNil(BuildHashCache.cachedHash(for: "app-1", in: cacheDir))
        XCTAssertNil(BuildHashCache.cachedHash(for: "app-2", in: cacheDir))
    }

    /// 소스 디렉터리 기반 end-to-end 캐시 히트 및 무효화(내용 변경 시) 검증
    func testDirectoryBasedCacheHitAndContentChange() throws {
        let appDir = tempDir.appendingPathComponent("sample-app", isDirectory: true)
        let sourcesDir = appDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        let file = sourcesDir.appendingPathComponent("main.swift")
        try "print(\"Version 1\")".write(to: file, atomically: true, encoding: .utf8)

        let slug = "sample-app"

        // 1. 처음에는 캐시가 없으므로 isStale == true
        XCTAssertTrue(BuildHashCache.isStale(slug: slug, appDirectory: appDir, in: cacheDir))
        XCTAssertFalse(BuildHashCache.shouldSkipInstall(slug: slug, appDirectory: appDir, in: cacheDir))

        // 2. 빌드 성공 후 해시 영속화
        let storedHash = BuildHashCache.store(slug: slug, appDirectory: appDir, in: cacheDir)
        XCTAssertNotNil(storedHash)

        // 3. 소스 무변경 상태에서는 isStale == false, skip == true
        XCTAssertFalse(BuildHashCache.isStale(slug: slug, appDirectory: appDir, in: cacheDir))
        XCTAssertTrue(BuildHashCache.shouldSkipInstall(slug: slug, appDirectory: appDir, in: cacheDir))

        // 4. 소스 내용 변경 시 isStale == true, skip == false
        try "print(\"Version 2\")".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertTrue(BuildHashCache.isStale(slug: slug, appDirectory: appDir, in: cacheDir))
        XCTAssertFalse(BuildHashCache.shouldSkipInstall(slug: slug, appDirectory: appDir, in: cacheDir))

        // 5. 다시 빌드 성공 기록 시 최신화되어 isStale == false
        BuildHashCache.store(slug: slug, appDirectory: appDir, in: cacheDir)
        XCTAssertFalse(BuildHashCache.isStale(slug: slug, appDirectory: appDir, in: cacheDir))
        XCTAssertTrue(BuildHashCache.shouldSkipInstall(slug: slug, appDirectory: appDir, in: cacheDir))
    }

    /// InstallHealth 통합 인터페이스 호출 검증
    func testInstallHealthUnifiedInterface() throws {
        let appDir = tempDir.appendingPathComponent("unified-app", isDirectory: true)
        let sourcesDir = appDir.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
        try "let v = 1".write(to: sourcesDir.appendingPathComponent("lib.swift"), atomically: true, encoding: .utf8)

        let slug = "unified-app"

        let computedHash = InstallHealth.computeSourceHash(directory: appDir)
        XCTAssertNotNil(computedHash)

        // 빌드 성공 기록 (in: cacheDir)
        InstallHealth.recordBuildSuccess(slug: slug, hash: computedHash!, in: cacheDir)

        XCTAssertFalse(InstallHealth.isStale(slug: slug, currentHash: computedHash!, in: cacheDir))
        XCTAssertTrue(InstallHealth.shouldSkipInstall(slug: slug, currentHash: computedHash!, in: cacheDir))
        XCTAssertFalse(InstallHealth.isStale(slug: slug, appDirectory: appDir, in: cacheDir))
        XCTAssertTrue(InstallHealth.shouldSkipInstall(slug: slug, appDirectory: appDir, in: cacheDir))
    }

    /// 슬러그 정규화 검증 (경로 구분자 '/' 가 포함된 경우)
    func testSlugSanitization() {
        let slugWithPath = "apps/my-cool-app"
        let hash = "hash-999"

        BuildHashCache.store(slug: slugWithPath, hash: hash, in: cacheDir)

        // "my-cool-app" 또는 "apps/my-cool-app" 둘 다 동일하게 조회 가능해야 함
        XCTAssertEqual(BuildHashCache.cachedHash(for: slugWithPath, in: cacheDir), hash)
        XCTAssertEqual(BuildHashCache.cachedHash(for: "my-cool-app", in: cacheDir), hash)
    }

    /// customCacheDirectory의 OSAllocatedUnfairLock 멀티스레드 안전성 검증
    func testCustomCacheDirectoryLockThreadSafety() {
        let original = BuildHashCache.customCacheDirectory
        defer { BuildHashCache.customCacheDirectory = original }

        let iterations = 1000
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            if i % 2 == 0 {
                let dir = URL(fileURLWithPath: "/tmp/custom-\(i)")
                BuildHashCache.customCacheDirectory = dir
            } else {
                _ = BuildHashCache.customCacheDirectory
                _ = BuildHashCache.cacheDirectory
            }
        }
    }

    /// record, isCurrent, cleanStale 편의 인터페이스 검증
    func testRecordAndIsCurrentAndCleanStale() {
        let slug = "convenience-app"
        let hash = "hash-convenience-123"

        // 1. record
        BuildHashCache.record(slug: slug, hash: hash, in: cacheDir)

        // 2. isCurrent
        XCTAssertTrue(BuildHashCache.isCurrent(slug: slug, currentHash: hash, in: cacheDir))
        XCTAssertFalse(BuildHashCache.isCurrent(slug: slug, currentHash: "other-hash", in: cacheDir))

        // 3. cleanStale (by slug)
        BuildHashCache.cleanStale(slug: slug, in: cacheDir)
        XCTAssertNil(BuildHashCache.cachedHash(for: slug, in: cacheDir))
        XCTAssertFalse(BuildHashCache.isCurrent(slug: slug, currentHash: hash, in: cacheDir))

        // 4. cleanStale (olderThan)
        BuildHashCache.record(slug: "old-app", hash: "old-hash", in: cacheDir)
        let removed = BuildHashCache.cleanStale(in: cacheDir, olderThan: -1) // 즉시 만료 대상
        XCTAssertGreaterThanOrEqual(removed, 1)
        XCTAssertNil(BuildHashCache.cachedHash(for: "old-app", in: cacheDir))
    }

    /// 멀티스레드 동시 record/isCurrent/cachedHash I/O 경합 안전성 검증
    func testConcurrentRecordAndQuery() {
        guard let targetCacheDir = self.cacheDir else {
            XCTFail("cacheDir is nil")
            return
        }
        let iterations = 200
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            let slug = "thread-app-\(i % 10)"
            let hash = "hash-\(i)"

            BuildHashCache.record(slug: slug, hash: hash, in: targetCacheDir)
            _ = BuildHashCache.cachedHash(for: slug, in: targetCacheDir)
            _ = BuildHashCache.cachedMetadata(for: slug, in: targetCacheDir)
            _ = BuildHashCache.isCurrent(slug: slug, currentHash: hash, in: targetCacheDir)

            if i % 20 == 0 {
                BuildHashCache.cleanStale(slug: slug, in: targetCacheDir)
            }
        }
    }
}
