import Testing
import Foundation
@testable import ChunkDedupKit

@Suite("Deduplication Metrics & Savings Tests")
struct DeduplicationMetricsTests {
    @Test("Calculates deduplication ratio and savings percentage correctly")
    func testDeduplicationCalculations() {
        let chunk1 = Chunk(hash: "hash_a", algorithm: .sha256, offset: 0, length: 1000)
        let chunk2 = Chunk(hash: "hash_b", algorithm: .sha256, offset: 1000, length: 1000)
        let chunk3 = Chunk(hash: "hash_a", algorithm: .sha256, offset: 2000, length: 1000) // duplicate of chunk1
        let chunk4 = Chunk(hash: "hash_b", algorithm: .sha256, offset: 3000, length: 1000) // duplicate of chunk2

        let chunks = [chunk1, chunk2, chunk3, chunk4]
        let metrics = DeduplicationMetrics.calculate(chunks: chunks)

        #expect(metrics.totalInputBytes == 4000)
        #expect(metrics.uniqueBytes == 2000)
        #expect(metrics.totalChunksCount == 4)
        #expect(metrics.uniqueChunksCount == 2)
        #expect(metrics.savedBytes == 2000)
        #expect(metrics.deduplicationRatio == 2.0)
        #expect(metrics.savingsPercentage == 50.0)
    }

    @Test("Calculates metrics when all chunks are unique")
    func testAllUniqueChunks() {
        let chunk1 = Chunk(hash: "hash_1", algorithm: .sha256, offset: 0, length: 500)
        let chunk2 = Chunk(hash: "hash_2", algorithm: .sha256, offset: 500, length: 500)

        let metrics = DeduplicationMetrics.calculate(chunks: [chunk1, chunk2])

        #expect(metrics.totalInputBytes == 1000)
        #expect(metrics.uniqueBytes == 1000)
        #expect(metrics.savedBytes == 0)
        #expect(metrics.deduplicationRatio == 1.0)
        #expect(metrics.savingsPercentage == 0.0)
    }

    @Test("Calculates metrics against existing destination chunk cache")
    func testExistingCacheDeduplication() {
        let chunk1 = Chunk(hash: "cached_hash", algorithm: .sha256, offset: 0, length: 10000)
        let chunk2 = Chunk(hash: "new_hash", algorithm: .sha256, offset: 10000, length: 2000)

        let existing: Set<String> = ["cached_hash"]
        let metrics = DeduplicationMetrics.calculate(chunks: [chunk1, chunk2], existingHashes: existing)

        #expect(metrics.totalInputBytes == 12000)
        #expect(metrics.uniqueBytes == 2000)
        #expect(metrics.savedBytes == 10000)
        #expect(metrics.deduplicationRatio == 6.0)
        #expect(metrics.savingsPercentage > 83.0)
    }
}
