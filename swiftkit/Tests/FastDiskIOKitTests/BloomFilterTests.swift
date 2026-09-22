import XCTest
import Foundation
@testable import FastDiskIOKit

final class BloomFilterTests: XCTestCase {
    func testBloomFilter10000Keys() {
        var filter = BloomFilter(expectedCount: 10_000, targetFPRate: 0.01)

        // 메모리 12KB 내외 (약 11.98KB)
        XCTAssertLessThanOrEqual(filter.memoryByteSize, 13 * 1024)
        XCTAssertGreaterThanOrEqual(filter.memoryByteSize, 11 * 1024)

        // 1만 건 고유 키 삽입
        let inserted = (0..<10_000).map { "key-prefix-\($0)" }
        for key in inserted {
            filter.insert(key)
        }
        XCTAssertEqual(filter.count, 10_000)

        // 100% True Positive 검증
        for key in inserted {
            XCTAssertTrue(filter.contains(key), "All inserted keys must be detected")
        }

        // 무작위 1만 건 False Positive 1%대 검증
        let testSet = (10_000..<20_000).map { "nonexistent-key-\($0)" }
        var falsePositives = 0
        for key in testSet {
            if filter.contains(key) {
                falsePositives += 1
            }
        }

        let empiricalFPR = Double(falsePositives) / Double(testSet.count)
        // 실측 FPR 1% 수준 (0.004 ~ 0.025 허용)
        XCTAssertLessThan(empiricalFPR, 0.025, "Empirical False Positive Rate (\(empiricalFPR)) should be around 1%")
        XCTAssertGreaterThan(empiricalFPR, 0.003, "Empirical False Positive Rate (\(empiricalFPR)) should be around 1%")

        // 이론적 falsePositiveRate 계산값도 약 1% 수준
        XCTAssertEqual(filter.falsePositiveRate, 0.01, accuracy: 0.005)
    }
}
