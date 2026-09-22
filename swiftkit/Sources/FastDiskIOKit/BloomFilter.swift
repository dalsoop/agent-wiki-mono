import Foundation

public struct BloomFilter: Sendable {
    public private(set) var bitCount: Int, hashCount: Int, count: Int = 0
    private var bits: [UInt64]

    public init(expectedCount: Int = 10_000, targetFPRate: Double = 0.01) {
        let m = max(64, Int(ceil(-Double(expectedCount) * log(targetFPRate) / (log(2) * log(2)))))
        let k = max(1, Int(round((Double(m) / Double(expectedCount)) * log(2))))
        self.bitCount = m
        self.hashCount = k
        self.bits = [UInt64](repeating: 0, count: (m + 63) / 64)
    }

    public var memoryByteSize: Int { bits.count * MemoryLayout<UInt64>.stride }
    public var falsePositiveRate: Double {
        guard count > 0 else { return 0.0 }
        return pow(1.0 - exp(-Double(hashCount * count) / Double(bitCount)), Double(hashCount))
    }

    public mutating func insert(_ string: String) {
        let (h1, h2) = hashes(for: string)
        for i in 0..<hashCount {
            let idx = Int((h1 &+ UInt64(i) &* h2) % UInt64(bitCount))
            bits[idx / 64] |= (1 &<< (idx % 64))
        }
        count += 1
    }

    public func contains(_ string: String) -> Bool {
        let (h1, h2) = hashes(for: string)
        for i in 0..<hashCount {
            let idx = Int((h1 &+ UInt64(i) &* h2) % UInt64(bitCount))
            if (bits[idx / 64] & (1 &<< (idx % 64))) == 0 { return false }
        }
        return true
    }

    private func hashes(for string: String) -> (UInt64, UInt64) {
        var h1: UInt64 = 14695981039346656037, h2: UInt64 = 5381
        for b in string.utf8 {
            h1 = (h1 ^ UInt64(b)) &* 1099511628211
            h2 = ((h2 &<< 5) &+ h2) &+ UInt64(b)
        }
        return (h1, h2 == 0 ? 1 : h2)
    }
}
