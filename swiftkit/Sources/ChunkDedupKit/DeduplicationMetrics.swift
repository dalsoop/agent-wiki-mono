import Foundation

/// Performance and savings metrics calculated from deduplication.
public struct DeduplicationMetrics: Sendable, Codable, Equatable {
    /// Total original uncompressed bytes processed.
    public let totalInputBytes: Int64
    /// Unique bytes stored after removing duplicate chunks.
    public let uniqueBytes: Int64
    /// Total number of chunks generated.
    public let totalChunksCount: Int
    /// Number of unique chunks retained.
    public let uniqueChunksCount: Int

    /// Bytes saved via deduplication.
    public var savedBytes: Int64 {
        max(0, totalInputBytes - uniqueBytes)
    }

    /// Deduplication ratio: totalInputBytes / uniqueBytes (e.g. 2.5 means 2.5x reduction).
    /// Returns 1.0 if uniqueBytes == 0 or totalInputBytes <= uniqueBytes.
    public var deduplicationRatio: Double {
        guard uniqueBytes > 0 else { return 1.0 }
        let ratio = Double(totalInputBytes) / Double(uniqueBytes)
        return (ratio.isFinite && !ratio.isNaN) ? max(1.0, ratio) : 1.0
    }

    /// Percentage of storage saved: (savedBytes / totalInputBytes) * 100.
    public var savingsPercentage: Double {
        guard totalInputBytes > 0 else { return 0.0 }
        let pct = (Double(savedBytes) / Double(totalInputBytes)) * 100.0
        return (pct.isFinite && !pct.isNaN) ? min(100.0, max(0.0, pct)) : 0.0
    }

    /// Number of duplicate chunks reused rather than written.
    public var reusedChunksCount: Int {
        max(0, totalChunksCount - uniqueChunksCount)
    }

    /// Reused chunk ratio: (reusedChunksCount / totalChunksCount).
    public var reusedChunkRatio: Double {
        guard totalChunksCount > 0 else { return 0.0 }
        let ratio = Double(reusedChunksCount) / Double(totalChunksCount)
        return (ratio.isFinite && !ratio.isNaN) ? min(1.0, max(0.0, ratio)) : 0.0
    }

    /// Deduplication factor alias (same as deduplicationRatio).
    public var deduplicationFactor: Double {
        deduplicationRatio
    }

    public init(
        totalInputBytes: Int64,
        uniqueBytes: Int64,
        totalChunksCount: Int,
        uniqueChunksCount: Int
    ) {
        self.totalInputBytes = totalInputBytes
        self.uniqueBytes = uniqueBytes
        self.totalChunksCount = totalChunksCount
        self.uniqueChunksCount = uniqueChunksCount
    }

    /// Computes metrics from a list of chunks and a set of already known chunk hashes.
    public static func calculate(
        chunks: [Chunk],
        existingHashes: Set<String> = []
    ) -> DeduplicationMetrics {
        var seen = existingHashes
        var totalBytes: Int64 = 0
        var uniqueBytes: Int64 = 0
        var uniqueCount = 0

        for chunk in chunks {
            totalBytes += Int64(chunk.length)
            if !seen.contains(chunk.hash) {
                seen.insert(chunk.hash)
                uniqueBytes += Int64(chunk.length)
                uniqueCount += 1
            }
        }

        return DeduplicationMetrics(
            totalInputBytes: totalBytes,
            uniqueBytes: uniqueBytes,
            totalChunksCount: chunks.count,
            uniqueChunksCount: uniqueCount
        )
    }
}
