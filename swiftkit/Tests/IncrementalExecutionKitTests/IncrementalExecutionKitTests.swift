import XCTest
@testable import IncrementalExecutionKit

final class IncrementalExecutionKitTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IncrementalExecutionKitTests_\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true) } catch { _ = error }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testStatCacheHitAndMiss() throws {
        let cacheFile = tempDir.appendingPathComponent("test-cache.json")
        let cache = StatCacheOracle(cacheFileURL: cacheFile)

        let filePath = "Sources/Sample.swift"
        let fullPath = tempDir.appendingPathComponent(filePath)
        try FileManager.default.createDirectory(at: fullPath.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "print(\"hello\")\n".write(to: fullPath, atomically: true, encoding: .utf8)

        let fingerprint = 42

        // 1. Initial lookup -> Miss
        XCTAssertNil(cache.lookup(path: filePath, root: tempDir.path, fingerprint: fingerprint))

        // 2. Record clean status
        let payload = "OK".data(using: .utf8)!
        cache.record(path: filePath, root: tempDir.path, fingerprint: fingerprint, payload: payload)
        XCTAssertEqual(cache.count, 1)

        // 3. Lookup -> Hit
        let hitPayload = cache.lookup(path: filePath, root: tempDir.path, fingerprint: fingerprint)
        XCTAssertNotNil(hitPayload)
        XCTAssertEqual(String(data: hitPayload!, encoding: .utf8), "OK")

        // 4. Invalidation upon file change
        Thread.sleep(forTimeInterval: 0.05)
        try "print(\"modified\")\n".write(to: fullPath, atomically: true, encoding: .utf8)
        XCTAssertNil(cache.lookup(path: filePath, root: tempDir.path, fingerprint: fingerprint))
    }

    func testBoundedStreamingEngineMap() async throws {
        let items = Array(1...50)
        let results = try await BoundedStreamingEngine.map(items: items, concurrencyLimit: 4) { value in
            return value * 2
        }

        XCTAssertEqual(results.count, 50)
        let sorted = results.sorted()
        XCTAssertEqual(sorted.first, 2)
        XCTAssertEqual(sorted.last, 100)
    }

    func testBoundedStreamingEngineCompactMap() async {
        let items = Array(1...20)
        let evenOnly = await BoundedStreamingEngine.compactMap(items: items, concurrencyLimit: 4) { value in
            return (value % 2 == 0) ? value : nil
        }

        XCTAssertEqual(evenOnly.count, 10)
        XCTAssertTrue(evenOnly.allSatisfy { $0 % 2 == 0 })
    }
}
