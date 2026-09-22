import Foundation

/// Pure Swift implementation of the BLAKE3 cryptographic hash algorithm (standard 256-bit output).
/// High-speed tree hash optimized for Apple Silicon 64-bit architectures.
public enum BLAKE3 {
    private static let iv: [UInt32] = [
        0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
        0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19
    ]

    private static let msgPermutation: [Int] = [
        2, 6, 3, 10, 7, 0, 4, 13, 1, 11, 12, 5, 9, 14, 15, 8
    ]

    public static let chunkSize = 1024
    public static let blockSize = 64
    public static let digestLength = 32

    // Flags
    private static let flagChunkStart: UInt32 = 1 << 0
    private static let flagChunkEnd: UInt32 = 1 << 1
    private static let flagParent: UInt32 = 1 << 2
    private static let flagRoot: UInt32 = 1 << 3

    @inline(__always)
    private static func rotRight(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }

    @inline(__always)
    private static func g(
        _ state: inout [UInt32],
        _ a: Int, _ b: Int, _ c: Int, _ d: Int,
        _ mx: UInt32, _ my: UInt32
    ) {
        state[a] = state[a] &+ state[b] &+ mx
        state[d] = rotRight(state[d] ^ state[a], 16)
        state[c] = state[c] &+ state[d]
        state[b] = rotRight(state[b] ^ state[c], 12)
        state[a] = state[a] &+ state[b] &+ my
        state[d] = rotRight(state[d] ^ state[a], 8)
        state[c] = state[c] &+ state[d]
        state[b] = rotRight(state[b] ^ state[c], 7)
    }

    @inline(__always)
    private static func round(_ state: inout [UInt32], _ m: [UInt32]) {
        // Columns
        g(&state, 0, 4, 8, 12, m[0], m[1])
        g(&state, 1, 5, 9, 13, m[2], m[3])
        g(&state, 2, 6, 10, 14, m[4], m[5])
        g(&state, 3, 7, 11, 15, m[6], m[7])
        // Diagonals
        g(&state, 0, 5, 10, 15, m[8], m[9])
        g(&state, 1, 6, 11, 12, m[10], m[11])
        g(&state, 2, 7, 8, 13, m[12], m[13])
        g(&state, 3, 4, 9, 14, m[14], m[15])
    }

    private static func compress(
        cv: [UInt32],
        block: [UInt32],
        counter: UInt64,
        blockLen: UInt32,
        flags: UInt32
    ) -> [UInt32] {
        var state = [UInt32](repeating: 0, count: 16)
        for i in 0..<8 {
            state[i] = cv[i]
        }
        state[8] = iv[0]
        state[9] = iv[1]
        state[10] = iv[2]
        state[11] = iv[3]
        state[12] = UInt32(truncatingIfNeeded: counter)
        state[13] = UInt32(truncatingIfNeeded: counter >> 32)
        state[14] = blockLen
        state[15] = flags

        var m = block
        round(&state, m)
        for _ in 0..<6 {
            var perm = [UInt32](repeating: 0, count: 16)
            for i in 0..<16 {
                perm[i] = m[msgPermutation[i]]
            }
            m = perm
            round(&state, m)
        }

        var out = [UInt32](repeating: 0, count: 16)
        for i in 0..<8 {
            out[i] = state[i] ^ state[i + 8]
            out[i + 8] = state[i + 8] ^ cv[i]
        }
        return out
    }

    private static func wordsFromBytes(_ bytes: UnsafeBufferPointer<UInt8>, count: Int) -> [UInt32] {
        var words = [UInt32](repeating: 0, count: 16)
        let fullWords = count / 4
        bytes.baseAddress?.withMemoryRebound(to: UInt32.self, capacity: fullWords) { ptr in
            for i in 0..<fullWords {
                words[i] = UInt32(littleEndian: ptr[i])
            }
        }
        let remainder = count % 4
        if remainder > 0 {
            let offset = fullWords * 4
            var lastWord: UInt32 = 0
            for i in 0..<remainder {
                lastWord |= UInt32(bytes[offset + i]) << (i * 8)
            }
            words[fullWords] = lastWord
        }
        return words
    }

    private static func chunkHash(
        bytes: UnsafeBufferPointer<UInt8>,
        chunkCounter: UInt64,
        flags: UInt32
    ) -> [UInt32] {
        var cv = iv
        let total = bytes.count
        var offset = 0
        var hasMore = true

        while hasMore {
            let take = min(total - offset, blockSize)
            let isFirst = offset == 0
            let isLast = (offset + take) >= total
            var blockFlags = flags
            if isFirst {
                blockFlags |= flagChunkStart
            }
            if isLast {
                blockFlags |= flagChunkEnd
            }

            let slice = UnsafeBufferPointer(
                rebasing: bytes[offset..<(offset + take)]
            )
            let words = wordsFromBytes(slice, count: take)
            let out = compress(
                cv: cv,
                block: words,
                counter: chunkCounter,
                blockLen: UInt32(take),
                flags: blockFlags
            )
            if isLast {
                return Array(out[0..<8])
            }
            cv = Array(out[0..<8])
            offset += take
            hasMore = offset < total
        }
        return cv
    }

    private static func parentHash(
        left: [UInt32],
        right: [UInt32],
        flags: UInt32
    ) -> [UInt32] {
        var block = [UInt32](repeating: 0, count: 16)
        for i in 0..<8 {
            block[i] = left[i]
            block[i + 8] = right[i]
        }
        let out = compress(
            cv: iv,
            block: block,
            counter: 0,
            blockLen: UInt32(blockSize),
            flags: flagParent | flags
        )
        return Array(out[0..<8])
    }

    /// Computes 256-bit BLAKE3 hash of raw Data.
    public static func hash(data: Data) -> Data {
        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            return hash(bytes: bytes)
        }
    }

    /// Computes 256-bit BLAKE3 hash of a byte buffer.
    public static func hash(bytes: UnsafeBufferPointer<UInt8>) -> Data {
        let totalBytes = bytes.count
        if totalBytes <= chunkSize {
            // Single chunk is the root
            let rootWords = chunkHash(
                bytes: bytes,
                chunkCounter: 0,
                flags: flagRoot
            )
            return wordsToData(rootWords)
        }

        // Multiple chunks: tree hashing with stack
        var stack: [[UInt32]] = []
        var chunkCounter: UInt64 = 0
        var offset = 0

        while offset < totalBytes {
            let take = min(totalBytes - offset, chunkSize)
            let slice = UnsafeBufferPointer(rebasing: bytes[offset..<(offset + take)])
            var currentCV = chunkHash(
                bytes: slice,
                chunkCounter: chunkCounter,
                flags: 0
            )
            chunkCounter += 1

            // Merge right children with stack
            var totalChunks = chunkCounter
            while (totalChunks & 1) == 0 {
                let leftCV = stack.removeLast()
                currentCV = parentHash(left: leftCV, right: currentCV, flags: 0)
                totalChunks >>= 1
            }
            stack.append(currentCV)
            offset += take
        }

        // Final merge to root
        var root = stack.removeLast()
        while let left = stack.popLast() {
            root = parentHash(left: left, right: root, flags: stack.isEmpty ? flagRoot : 0)
        }
        return wordsToData(root)
    }

    /// Hex representation of BLAKE3 hash.
    public static func hexHash(data: Data) -> String {
        let digest = hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func wordsToData(_ words: [UInt32]) -> Data {
        var data = Data(count: words.count * 4)
        data.withUnsafeMutableBytes { raw in
            let ptr = raw.bindMemory(to: UInt32.self)
            for i in 0..<words.count {
                ptr[i] = words[i].littleEndian
            }
        }
        return data
    }
}
