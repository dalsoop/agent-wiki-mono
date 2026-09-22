import XCTest
@testable import FastDiskIOKit

final class MurmurHash64ATests: XCTestCase {

    // MARK: - Constants & Algorithm Verification

    func testConstants() {
        XCTAssertEqual(MurmurHash64A.m, 0xc6a4_a793_5bd1_e995)
        XCTAssertEqual(MurmurHash64A.r, 47)
    }

    // MARK: - Official Known Test Vectors (Seed = 0)

    func testOfficialKnownTestVectors() {
        // Canonical test vectors from Stingray / Austin Appleby SMHasher
        let vectors: [(input: String, expected: UInt64)] = [
            ("packages/pre_boot", 0xbca0_ea9b_bcb1_a2f0),
            ("packages/boot", 0x9ba6_26af_a44a_3aa3),
            ("packages/fallback_resources", 0x495c_d5b6_043a_104d),
            ("core/stingray_renderer/shading_environment_components/global_lighting", 0x47b5_2d27_d6d8_42ee),
            ("lua", 0xa14e_8dfa_2cd1_17e2)
        ]

        for (input, expected) in vectors {
            let hashFromString = MurmurHash64A.hash(string: input, seed: 0)
            let hashFromData = MurmurHash64A.hash(data: Data(input.utf8), seed: 0)
            let hashFromInstance = MurmurHash64A(seed: 0).hash(string: input)

            XCTAssertEqual(hashFromString, expected, "Mismatch for string: \(input)")
            XCTAssertEqual(hashFromData, expected, "Mismatch for Data: \(input)")
            XCTAssertEqual(hashFromInstance, expected, "Mismatch for instance: \(input)")
        }
    }

    // MARK: - SMHasher Canonical Verification Test (0x1F0D3804)

    func testSMHasherCanonicalVerificationValue() {
        // Replicating SMHasher's KeysetTest.cpp:VerificationTest for 64-bit MurmurHash64A
        // 1. For i in 0..<256: key = [0, 1, ..., i-1], hash with seed (256 - i)
        // 2. Accumulate all 256 64-bit hashes into a 2048-byte buffer
        // 3. Hash the 2048-byte buffer with seed 0
        // 4. Verification code = lower 32 bits (little-endian) -> must equal 0x1F0D3804
        var key = [UInt8](repeating: 0, count: 256)
        var hashes = [UInt8](repeating: 0, count: 256 * 8)

        for i in 0..<256 {
            if i > 0 {
                key[i - 1] = UInt8(i - 1)
            }
            let seed = UInt64(256 - i)
            let h: UInt64
            if i == 0 {
                h = key.withUnsafeBytes { raw in
                    let emptySlice = UnsafeRawBufferPointer(start: raw.baseAddress, count: 0)
                    return MurmurHash64A.hash(bytes: emptySlice, seed: seed)
                }
            } else {
                h = key.withUnsafeBytes { raw in
                    let slice = UnsafeRawBufferPointer(start: raw.baseAddress, count: i)
                    return MurmurHash64A.hash(bytes: slice, seed: seed)
                }
            }

            // Store as little-endian 64-bit integer
            var leH = h.littleEndian
            withUnsafeBytes(of: &leH) { hBytes in
                for b in 0..<8 {
                    hashes[i * 8 + b] = hBytes[b]
                }
            }
        }

        let finalHash = hashes.withUnsafeBytes { raw in
            MurmurHash64A.hash(bytes: raw, seed: 0)
        }

        let verificationCode = UInt32(truncatingIfNeeded: finalHash.littleEndian)
        XCTAssertEqual(verificationCode, 0x1F0D_3804, "SMHasher verification value must match canonical 0x1F0D3804")
    }

    // MARK: - Empty and Edge Inputs

    func testEmptyInput() {
        // Empty string with seed 0: seed ^ 0 = 0 -> mixed 0 = 0
        XCTAssertEqual(MurmurHash64A.hash(string: "", seed: 0), 0)
        XCTAssertEqual(MurmurHash64A.hash(data: Data(), seed: 0), 0)

        // Empty string with non-zero seed: should mix seed
        let seed: UInt64 = 0x1234_5678_9abc_def0
        let hEmptySeed = MurmurHash64A.hash(string: "", seed: seed)
        XCTAssertNotEqual(hEmptySeed, 0)
        XCTAssertNotEqual(hEmptySeed, seed)

        // Manual mix verification of empty seed
        var expectedMix = seed
        expectedMix ^= expectedMix >> MurmurHash64A.r
        expectedMix &*= MurmurHash64A.m
        expectedMix ^= expectedMix >> MurmurHash64A.r
        XCTAssertEqual(hEmptySeed, expectedMix)
    }

    // MARK: - Tail Handling (1 to 7 bytes & beyond)

    func testTailHandlingAllLengths() {
        let testString = "12345678901234567890" // 20 bytes
        var seenHashes = Set<UInt64>()

        for length in 1...16 {
            let prefix = String(testString.prefix(length))
            let data = Data(prefix.utf8)
            let hashStr = MurmurHash64A.hash(string: prefix, seed: 42)
            let hashData = MurmurHash64A.hash(data: data, seed: 42)

            XCTAssertEqual(hashStr, hashData, "String and Data hash should match for length \(length)")
            XCTAssertFalse(seenHashes.contains(hashStr), "Hash collision for distinct length prefixes: \(length)")
            seenHashes.insert(hashStr)
        }
    }

    // MARK: - Seed Variation & Avalanche Effect

    func testSeedVariation() {
        let input = "The quick brown fox jumps over the lazy dog"
        let seed1: UInt64 = 0
        let seed2: UInt64 = 1
        let seed3: UInt64 = 0xdead_beef_cafe_babe

        let h1 = MurmurHash64A.hash(string: input, seed: seed1)
        let h2 = MurmurHash64A.hash(string: input, seed: seed2)
        let h3 = MurmurHash64A.hash(string: input, seed: seed3)

        XCTAssertNotEqual(h1, h2)
        XCTAssertNotEqual(h2, h3)
        XCTAssertNotEqual(h1, h3)

        // Check bit flip divergence between seed 0 and 1
        let diffBits = (h1 ^ h2).nonzeroBitCount
        XCTAssertGreaterThanOrEqual(diffBits, 16, "Seed change must produce significant avalanche effect")
    }

    // MARK: - API Overloads Consistency

    func testAPIOverloadsConsistency() {
        let content = "HighPerformanceDiskIO_MurmurHash64A_ConsistencyCheck"
        let data = Data(content.utf8)
        let seed: UInt64 = 0xabcdef0123456789

        let hashFromStr = MurmurHash64A.hash(string: content, seed: seed)
        let hashFromData = MurmurHash64A.hash(data: data, seed: seed)
        let hashFromBytes = data.withUnsafeBytes { MurmurHash64A.hash(bytes: $0, seed: seed) }
        let hashFromInstance = MurmurHash64A(seed: seed).hash(string: content)

        XCTAssertEqual(hashFromStr, hashFromData)
        XCTAssertEqual(hashFromData, hashFromBytes)
        XCTAssertEqual(hashFromBytes, hashFromInstance)
    }

    // MARK: - Large Data & Throughput Performance

    func testLargeDataHashing() {
        // 64 KB of deterministic pseudo-random payload
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        for i in 0..<buffer.count {
            buffer[i] = UInt8((i * 31 + 17) & 0xff)
        }

        let hash1 = buffer.withUnsafeBytes { MurmurHash64A.hash(bytes: $0, seed: 100) }
        let hash2 = buffer.withUnsafeBytes { MurmurHash64A.hash(bytes: $0, seed: 100) }
        XCTAssertEqual(hash1, hash2, "Hashing identical large buffer must be deterministic")

        // Modify 1 byte in middle
        buffer[32 * 1024] ^= 0x01
        let hashModified = buffer.withUnsafeBytes { MurmurHash64A.hash(bytes: $0, seed: 100) }
        XCTAssertNotEqual(hash1, hashModified, "1-bit flip in 64KB must alter the hash completely")

        let bitDiff = (hash1 ^ hashModified).nonzeroBitCount
        XCTAssertGreaterThanOrEqual(bitDiff, 16, "Single byte modification must flip many bits")
    }

    func testHighThroughputBenchmark() {
        // 1 MB buffer benchmark
        let size = 1024 * 1024
        var buffer = [UInt8](repeating: 0x5a, count: size)
        buffer[0] = 0x01
        buffer[size - 1] = 0xfe

        let iterations = 100
        let totalBytes = Double(size * iterations)

        let start = DispatchTime.now()
        var checksum: UInt64 = 0
        buffer.withUnsafeBytes { raw in
            for i in 0..<iterations {
                checksum ^= MurmurHash64A.hash(bytes: raw, seed: UInt64(i))
            }
        }
        let end = DispatchTime.now()
        let elapsedNanoseconds = Double(end.uptimeNanoseconds - start.uptimeNanoseconds)
        let elapsedSeconds = elapsedNanoseconds / 1_000_000_000.0

        let gigabytesPerSecond = (totalBytes / (1024 * 1024 * 1024)) / elapsedSeconds
        XCTAssertNotEqual(checksum, 0)
        print("MurmurHash64A Throughput: \(String(format: "%.2f", gigabytesPerSecond)) GB/s")
    }
}
