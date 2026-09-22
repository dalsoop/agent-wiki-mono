import XCTest
import CoreGraphics
@testable import ScreenGrabKit

final class WindowPreviewPipelineTests: XCTestCase {

    private func createDummyImage(width: Int = 10, height: Int = 10) -> CGImage {
        let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1.0))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testWindowThumbnailCacheSWRFlow() {
        let cache = WindowThumbnailCache(activeTTL: 0.1, backgroundTTL: 0.2, countLimit: 4, inflightTimeout: 1.0)
        let dummyImage = createDummyImage()

        // 1. 처음 조회 시 Miss
        let initialLookup = cache.lookup(id: "win-1")
        XCTAssertNil(initialLookup.value)
        XCTAssertFalse(initialLookup.isFresh)
        XCTAssertFalse(initialLookup.isStale)

        // 2. Revalidation Claim
        let targets = [WindowCaptureTarget(id: "win-1", windowID: 100)]
        let claimed = cache.claimRevalidationTargets(targets)
        XCTAssertEqual(claimed.count, 1)

        // 3. 중복 Claim 시도 시 방어 (Inflight Stampede 차단)
        let claimedAgain = cache.claimRevalidationTargets(targets)
        XCTAssertTrue(claimedAgain.isEmpty)

        // 4. Store Batch
        let results = [WindowCaptureResultItem(id: "win-1", image: dummyImage, durationMs: 12.5)]
        cache.storeBatch(items: results, completedTargets: claimed)
        XCTAssertEqual(cache.count, 1)

        // 5. Fresh Hit
        let freshLookup = cache.lookup(id: "win-1")
        XCTAssertNotNil(freshLookup.value)
        XCTAssertTrue(freshLookup.isFresh)
        XCTAssertFalse(freshLookup.isStale)

        // 6. TTL 경과 후 Stale Hit
        Thread.sleep(forTimeInterval: 0.25)
        let staleLookup = cache.lookup(id: "win-1")
        XCTAssertNotNil(staleLookup.value)
        XCTAssertFalse(staleLookup.isFresh)
        XCTAssertTrue(staleLookup.isStale)

        // 7. Flush 시 VRAM 0B 완전 해제
        cache.flush()
        XCTAssertEqual(cache.count, 0)
        let flushedLookup = cache.lookup(id: "win-1")
        XCTAssertNil(flushedLookup.value)
    }

    func testWindowThumbnailCacheTrueLRU() {
        let cache = WindowThumbnailCache(activeTTL: 5.0, backgroundTTL: 5.0, countLimit: 2, inflightTimeout: 1.0)
        let dummyImage = createDummyImage()

        // 2개 엔트리 추가
        cache.storeBatch(items: [
            WindowCaptureResultItem(id: "win-1", image: dummyImage, durationMs: 5.0),
            WindowCaptureResultItem(id: "win-2", image: dummyImage, durationMs: 5.0)
        ], completedTargets: [])
        XCTAssertEqual(cache.count, 2)

        // win-1에 접근하여 MRU로 갱신
        _ = cache.lookup(id: "win-1")

        // 3번째 엔트리 추가 -> win-2가 축출되어야 함
        cache.storeBatch(items: [
            WindowCaptureResultItem(id: "win-3", image: dummyImage, durationMs: 5.0)
        ], completedTargets: [])

        XCTAssertEqual(cache.count, 2)
        XCTAssertNotNil(cache.lookup(id: "win-1").value)
        XCTAssertNil(cache.lookup(id: "win-2").value) // 축출됨
        XCTAssertNotNil(cache.lookup(id: "win-3").value)
    }

    #if os(macOS)
    func testCaptureThrottleLimiter() async {
        let limiter = CaptureThrottleLimiter(maxConcurrent: 2)

        let start = Date()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await limiter.withPermitNonThrowing {
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    }
                }
            }
        }
        let elapsed = Date().timeIntervalSince(start)
        // 4개 태스크가 2개씩 병렬 실행되므로 최소 100ms 이상 소요되어야 함
        XCTAssertGreaterThanOrEqual(elapsed, 0.08)
    }
    #endif
}
