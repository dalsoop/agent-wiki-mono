import Foundation

/// Austin Appleby's official MurmurHash64A algorithm implemented in pure Swift.
///
/// Designed for 64-bit architectures, this implementation operates on 64-bit little-endian
/// chunks with unrolled 8-byte blocks and handles 1..7-byte tails with zero heap allocations.
public struct MurmurHash64A: Sendable {
    /// MurmurHash64A multiplier constant ($M = 0xc6a4a7935bd1e995$).
    public static let m: UInt64 = 0xc6a4_a793_5bd1_e995

    /// MurmurHash64A rotation/shift constant ($R = 47$).
    public static let r: Int = 47

    /// Pre-configured seed for instance calls.
    public let seed: UInt64

    @inlinable
    public init(seed: UInt64 = 0) {
        self.seed = seed
    }

    /// Computes the 64-bit MurmurHash64A hash of the given raw byte buffer.
    ///
    /// - Parameters:
    ///   - bytes: The raw memory buffer to hash.
    ///   - seed: The initial 64-bit seed value (default: 0).
    /// - Returns: The resulting 64-bit hash value.
    @inlinable
    public static func hash(bytes: UnsafeRawBufferPointer, seed: UInt64 = 0) -> UInt64 {
        let len = bytes.count
        var h: UInt64 = seed ^ (UInt64(len) &* m)

        guard len > 0, let baseAddress = bytes.baseAddress else {
            h ^= h >> r
            h &*= m
            h ^= h >> r
            return h
        }

        let nblocks = len >> 3
        var offset = 0
        let n8 = nblocks << 3

        // Unroll 4 blocks (32 bytes) at a time for maximum instruction pipelining and throughput
        while offset + 32 <= n8 {
            var k0 = UInt64(littleEndian: baseAddress.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            k0 &*= m
            k0 ^= k0 >> r
            k0 &*= m
            h ^= k0
            h &*= m

            var k1 = UInt64(littleEndian: baseAddress.loadUnaligned(fromByteOffset: offset + 8, as: UInt64.self))
            k1 &*= m
            k1 ^= k1 >> r
            k1 &*= m
            h ^= k1
            h &*= m

            var k2 = UInt64(littleEndian: baseAddress.loadUnaligned(fromByteOffset: offset + 16, as: UInt64.self))
            k2 &*= m
            k2 ^= k2 >> r
            k2 &*= m
            h ^= k2
            h &*= m

            var k3 = UInt64(littleEndian: baseAddress.loadUnaligned(fromByteOffset: offset + 24, as: UInt64.self))
            k3 &*= m
            k3 ^= k3 >> r
            k3 &*= m
            h ^= k3
            h &*= m

            offset += 32
        }

        // Remaining 8-byte blocks
        while offset < n8 {
            var k = UInt64(littleEndian: baseAddress.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
            k &*= m
            k ^= k >> r
            k &*= m
            h ^= k
            h &*= m
            offset += 8
        }

        // Tail handling (remaining 1..7 bytes)
        let tail = len & 7
        if tail > 0 {
            let tailPtr = baseAddress.advanced(by: n8).assumingMemoryBound(to: UInt8.self)
            switch tail {
            case 7:
                h ^= UInt64(tailPtr[6]) &<< 48
                fallthrough
            case 6:
                h ^= UInt64(tailPtr[5]) &<< 40
                fallthrough
            case 5:
                h ^= UInt64(tailPtr[4]) &<< 32
                fallthrough
            case 4:
                h ^= UInt64(tailPtr[3]) &<< 24
                fallthrough
            case 3:
                h ^= UInt64(tailPtr[2]) &<< 16
                fallthrough
            case 2:
                h ^= UInt64(tailPtr[1]) &<< 8
                fallthrough
            case 1:
                h ^= UInt64(tailPtr[0])
                h &*= m
            default:
                break
            }
        }

        // Finalization mixing
        h ^= h >> r
        h &*= m
        h ^= h >> r

        return h
    }

    /// Computes the 64-bit MurmurHash64A hash of the given Data object.
    @inlinable
    public static func hash(data: Data, seed: UInt64 = 0) -> UInt64 {
        data.withUnsafeBytes { rawBuffer in
            hash(bytes: rawBuffer, seed: seed)
        }
    }

    /// Computes the 64-bit MurmurHash64A hash of the given String's UTF-8 representation.
    @inlinable
    public static func hash(string: String, seed: UInt64 = 0) -> UInt64 {
        var str = string
        return str.withUTF8 { utf8Buffer in
            hash(bytes: UnsafeRawBufferPointer(utf8Buffer), seed: seed)
        }
    }

    /// Computes the 64-bit MurmurHash64A hash using this instance's configured seed.
    @inlinable
    public func hash(bytes: UnsafeRawBufferPointer) -> UInt64 {
        Self.hash(bytes: bytes, seed: seed)
    }

    /// Computes the 64-bit MurmurHash64A hash of the given Data using this instance's configured seed.
    @inlinable
    public func hash(data: Data) -> UInt64 {
        Self.hash(data: data, seed: seed)
    }

    /// Computes the 64-bit MurmurHash64A hash of the given String using this instance's configured seed.
    @inlinable
    public func hash(string: String) -> UInt64 {
        Self.hash(string: string, seed: seed)
    }
}
