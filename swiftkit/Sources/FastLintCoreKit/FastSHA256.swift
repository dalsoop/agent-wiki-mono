import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// 고속 SHA256 해시 유틸리티.
/// macOS/Darwin 에서는 CryptoKit 을 우선 사용하며, Linux 또는 헤더 부재 환경에서는
/// 의존성이 없는 순수 Swift SHA-256 구현으로 투명하게 폴백한다.
public enum FastSHA256: Sendable {

    @inlinable
    public static func hash(data: Data) -> String {
        #if canImport(CryptoKit)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #else
        return pureSwiftSHA256(data)
        #endif
    }

    @inlinable
    public static func hash(string: String) -> String {
        hash(data: Data(string.utf8))
    }

    /// Linux/컨테이너 및 무의존성 검증용 순수 Swift SHA-256
    public static func pureSwiftSHA256(_ data: Data) -> String {
        var h: [UInt32] = [
            0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
            0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
        ]
        let k: [UInt32] = [
            0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
            0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
            0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
            0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
            0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
            0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
            0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
            0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
        ]

        @inline(__always)
        func rotate(_ value: UInt32, _ by: UInt32) -> UInt32 {
            (value >> by) | (value << (32 - by))
        }

        var bytes = [UInt8](data)
        let bitLen = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        bytes.append(contentsOf: withUnsafeBytes(of: bitLen.bigEndian, Array.init))

        var w = [UInt32](repeating: 0, count: 64)
        var offset = 0
        while offset < bytes.count {
            for i in 0..<16 {
                let o = offset + i * 4
                w[i] = (UInt32(bytes[o]) << 24) | (UInt32(bytes[o + 1]) << 16)
                    | (UInt32(bytes[o + 2]) << 8) | UInt32(bytes[o + 3])
            }
            for i in 16..<64 {
                let s0 = rotate(w[i - 15], 7) ^ rotate(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotate(w[i - 2], 17) ^ rotate(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3]
            var e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let S1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ S1 &+ ch &+ k[i] &+ w[i]
                let S0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = S0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1
                d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d
            h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
            offset += 64
        }
        var out = ""
        out.reserveCapacity(64)
        for word in h {
            out.append(String(format: "%08x", word))
        }
        return out
    }
}
