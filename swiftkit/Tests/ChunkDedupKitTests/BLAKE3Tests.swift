import Testing
import Foundation
@testable import ChunkDedupKit

@Suite("BLAKE3 Cryptographic Hash Tests")
struct BLAKE3Tests {
    @Test("Verifies BLAKE3 empty string test vector")
    func testEmptyStringVector() {
        let empty = Data()
        let hex = BLAKE3.hexHash(data: empty)
        // Official BLAKE3 test vector for 0-length input
        #expect(hex == "af1349b9f5f9a1a6a0404dea36dcc9499bcb25c9adc112b7cc9a93cae41f3262")
    }

    @Test("Verifies BLAKE3 short string hashing")
    func testShortString() {
        let data = Data("hello world".utf8)
        let hex = BLAKE3.hexHash(data: data)
        #expect(!hex.isEmpty)
        #expect(hex.count == 64)

        // Deterministic check
        let hex2 = BLAKE3.hexHash(data: data)
        #expect(hex == hex2)
    }

    @Test("Verifies BLAKE3 multi-chunk tree hashing (>1024 bytes)")
    func testMultiChunkTreeHashing() {
        // 5000 bytes spanning multiple 1024-byte chunks
        var data = Data(count: 5000)
        for i in 0..<data.count {
            data[i] = UInt8((i * 31) & 0xFF)
        }

        let digest = BLAKE3.hash(data: data)
        #expect(digest.count == 32)

        let hex = BLAKE3.hexHash(data: data)
        #expect(hex.count == 64)

        // Modify 1 byte in chunk 2 -> hash must change
        var modified = data
        modified[1500] ^= 0xFF
        let modifiedHex = BLAKE3.hexHash(data: modified)
        #expect(hex != modifiedHex)
    }

    @Test("Verifies HashAlgorithm selector")
    func testHashAlgorithmSelector() {
        let data = Data("Antigravity Swiftkit Deduplication".utf8)
        let shaHex = HashAlgorithm.sha256.hexHash(data: data)
        let blakeHex = HashAlgorithm.blake3.hexHash(data: data)

        #expect(shaHex.count == 64)
        #expect(blakeHex.count == 64)
        #expect(shaHex != blakeHex)
    }
}
