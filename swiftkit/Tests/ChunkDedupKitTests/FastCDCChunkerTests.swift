import Testing
import Foundation
@testable import ChunkDedupKit

@Suite("FastCDC Content-Defined Chunking Tests")
struct FastCDCChunkerTests {
    @Test("Basic chunking produces chunks within valid size ranges")
    func testBasicChunking() {
        // FastCDC chunker with 16KB min, 32KB avg, 64KB max for fast in-memory testing
        let chunker = FastCDCChunker(
            minChunkSize: 16 * 1024,
            avgChunkSize: 32 * 1024,
            maxChunkSize: 64 * 1024,
            algorithm: .sha256
        )

        // Generate 200KB of pseudo-random data
        var data = Data(count: 200 * 1024)
        for i in 0..<data.count {
            data[i] = UInt8((i * 37 + (i >> 3)) & 0xFF)
        }

        let chunks = chunker.chunk(data: data, includeData: true)
        #expect(!chunks.isEmpty)

        var totalReconstructedLength = 0
        for (idx, chunk) in chunks.enumerated() {
            #expect(!chunk.hash.isEmpty)
            #expect(chunk.offset == Int64(totalReconstructedLength))

            // Non-final chunks should satisfy minChunkSize <= length <= maxChunkSize
            if idx < chunks.count - 1 {
                #expect(chunk.length >= chunker.minChunkSize)
                #expect(chunk.length <= chunker.maxChunkSize)
            }
            totalReconstructedLength += chunk.length
        }

        #expect(totalReconstructedLength == data.count)
    }

    @Test("1-byte modification test: single byte change leaves subsequent chunk hashes intact")
    func testSingleByteChangeBoundaryPreservation() {
        // Chunker with 16KB min, 32KB avg, 64KB max
        let chunker = FastCDCChunker(
            minChunkSize: 16 * 1024,
            avgChunkSize: 32 * 1024,
            maxChunkSize: 64 * 1024,
            algorithm: .sha256
        )

        // Generate 256KB of data
        var originalData = Data(count: 256 * 1024)
        for i in 0..<originalData.count {
            originalData[i] = UInt8((i * 43 ^ (i >> 2)) & 0xFF)
        }

        let originalChunks = chunker.chunk(data: originalData)
        #expect(originalChunks.count >= 3, "Expected at least 3 chunks for boundary test")

        // Mutate exactly 1 byte in the first chunk within its minChunkSize skip zone
        var mutatedData = originalData
        let mutateOffset = 100 // inside first chunk's skipped minChunkSize
        mutatedData[mutateOffset] ^= 0x55

        let mutatedChunks = chunker.chunk(data: mutatedData)
        #expect(mutatedChunks.count == originalChunks.count)

        // Chunk 0 MUST have a different hash because byte changed
        #expect(mutatedChunks[0].hash != originalChunks[0].hash)
        #expect(mutatedChunks[0].length == originalChunks[0].length)

        // Subsequent chunks MUST be completely identical!
        // This directly verifies FastCDC boundary synchronization preventing full re-transmissions.
        for i in 1..<originalChunks.count {
            #expect(mutatedChunks[i].hash == originalChunks[i].hash, "Chunk \(i) hash must match")
            #expect(mutatedChunks[i].length == originalChunks[i].length, "Chunk \(i) length must match")
            #expect(mutatedChunks[i].offset == originalChunks[i].offset, "Chunk \(i) offset must match")
        }
    }

    @Test("Small data below minChunkSize produces single chunk")
    func testSmallDataSingleChunk() {
        let chunker = FastCDCChunker.default // 1MB min
        let smallData = Data("Quick brown fox jumps over the lazy dog".utf8)

        let chunks = chunker.chunk(data: smallData)
        #expect(chunks.count == 1)
        #expect(chunks[0].length == smallData.count)
        #expect(chunks[0].offset == 0)
        #expect(chunks[0].hash == HashAlgorithm.sha256.hexHash(data: smallData))
    }

    @Test("Determinism: identical input always produces identical chunks")
    func testDeterminism() {
        let chunker = FastCDCChunker(
            minChunkSize: 8 * 1024,
            avgChunkSize: 16 * 1024,
            maxChunkSize: 32 * 1024,
            algorithm: .blake3
        )

        var data = Data(count: 100 * 1024)
        for i in 0..<data.count {
            data[i] = UInt8(i & 0xFF)
        }

        let run1 = chunker.chunk(data: data)
        let run2 = chunker.chunk(data: data)

        #expect(run1.count == run2.count)
        for i in 0..<run1.count {
            #expect(run1[i].hash == run2[i].hash)
            #expect(run1[i].length == run2[i].length)
            #expect(run1[i].offset == run2[i].offset)
        }
    }
}
