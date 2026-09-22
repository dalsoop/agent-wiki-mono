import Foundation

/// Represents an immutable content-defined chunk with its cryptographic fingerprint.
public struct Chunk: Sendable, Equatable, Identifiable, Codable {
    /// Unique chunk identifier, matching its cryptographic hash.
    public var id: String { hash }
    /// Hex-encoded cryptographic digest (SHA-256 or BLAKE3).
    public let hash: String
    /// The algorithm used to generate the hash.
    public let algorithm: HashAlgorithm
    /// Byte offset within the original file or stream.
    public let offset: Int64
    /// Length of this chunk in bytes.
    public let length: Int
    /// Optional in-memory raw payload of the chunk.
    public let data: Data?

    public init(
        hash: String,
        algorithm: HashAlgorithm,
        offset: Int64,
        length: Int,
        data: Data? = nil
    ) {
        self.hash = hash
        self.algorithm = algorithm
        self.offset = offset
        self.length = length
        self.data = data
    }
}

/// Content-Defined Chunking (CDC) engine implementing the FastCDC algorithm.
/// Provides high-speed variable-size chunking (default 1MB~4MB) with normalization
/// to prevent full re-transmission when minor changes occur in large files.
public final class FastCDCChunker: Sendable {
    public let minChunkSize: Int
    public let avgChunkSize: Int
    public let maxChunkSize: Int
    public let defaultAlgorithm: HashAlgorithm

    private let maskS: UInt64
    private let maskL: UInt64
    private let gearTable: [UInt64]

    /// Default configuration: 1MB min, 2MB avg, 4MB max, SHA-256.
    public static let `default` = FastCDCChunker(
        minChunkSize: 1024 * 1024,      // 1 MB
        avgChunkSize: 2 * 1024 * 1024,  // 2 MB
        maxChunkSize: 4 * 1024 * 1024,  // 4 MB
        algorithm: .sha256
    )

    public init(
        minChunkSize: Int = 1024 * 1024,
        avgChunkSize: Int = 2 * 1024 * 1024,
        maxChunkSize: Int = 4 * 1024 * 1024,
        algorithm: HashAlgorithm = .sha256
    ) {
        precondition(minChunkSize > 0, "minChunkSize must be greater than 0")
        precondition(avgChunkSize >= minChunkSize, "avgChunkSize must be >= minChunkSize")
        precondition(maxChunkSize >= avgChunkSize, "maxChunkSize must be >= avgChunkSize")

        self.minChunkSize = minChunkSize
        self.avgChunkSize = avgChunkSize
        self.maxChunkSize = maxChunkSize
        self.defaultAlgorithm = algorithm

        // Calculate mask bits based on target average chunk size
        let k = max(1, Int(floor(log2(Double(avgChunkSize)))))
        let bitsS = min(62, k + 1)
        let bitsL = max(1, k - 1)
        self.maskS = (1 &<< bitsS) - 1
        self.maskL = (1 &<< bitsL) - 1

        // Deterministic 256-entry 64-bit Gear Matrix for FastCDC
        var table = [UInt64](repeating: 0, count: 256)
        var seed: UInt64 = 0x517cc1b727220a95
        for i in 0..<256 {
            // SplitMix64 generator for high-entropy deterministic gear values
            seed = seed &+ 0x9e3779b97f4a7c15
            var z = seed
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            table[i] = z ^ (z >> 31)
        }
        self.gearTable = table
    }

    /// Chunks in-memory data using FastCDC and computes hashes.
    public func chunk(
        data: Data,
        algorithm: HashAlgorithm? = nil,
        includeData: Bool = true
    ) -> [Chunk] {
        let algo = algorithm ?? self.defaultAlgorithm
        let count = data.count
        guard count > 0 else { return [] }

        if count <= minChunkSize {
            let hash = algo.hexHash(data: data)
            return [Chunk(
                hash: hash,
                algorithm: algo,
                offset: 0,
                length: count,
                data: includeData ? data : nil
            )]
        }

        var chunks: [Chunk] = []
        chunks.reserveCapacity(max(1, count / avgChunkSize))

        data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> Void in
            guard let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            var chunkStart = 0
            while chunkStart < count {
                let remaining = count - chunkStart
                if remaining <= minChunkSize {
                    // Remainder smaller than minChunkSize: emit as final chunk
                    let slice = data.subdata(in: chunkStart..<count)
                    let hash = algo.hexHash(data: slice)
                    chunks.append(Chunk(
                        hash: hash,
                        algorithm: algo,
                        offset: Int64(chunkStart),
                        length: remaining,
                        data: includeData ? slice : nil
                    ))
                    break
                }

                // Skip the first minChunkSize bytes (FastCDC optimization)
                var fp: UInt64 = 0
                var i = chunkStart + minChunkSize
                let chunkMaxEnd = min(count, chunkStart + maxChunkSize)
                let chunkAvgEnd = min(count, chunkStart + avgChunkSize)
                var cutFound = false

                // Phase 1 & 2: Search for cut point
                if let cut = Self.scanCutPoint(ptr: ptr, start: i, end: chunkAvgEnd, mask: maskS, gearTable: gearTable, fingerprint: &fp) {
                    i = cut
                    cutFound = true
                } else if let cut = Self.scanCutPoint(ptr: ptr, start: i, end: chunkMaxEnd, mask: maskL, gearTable: gearTable, fingerprint: &fp) {
                    i = cut
                    cutFound = true
                }

                let chunkLength = cutFound ? (i - chunkStart) : (chunkMaxEnd - chunkStart)
                let slice = data.subdata(in: chunkStart..<(chunkStart + chunkLength))
                let hash = algo.hexHash(data: slice)

                chunks.append(Chunk(
                    hash: hash,
                    algorithm: algo,
                    offset: Int64(chunkStart),
                    length: chunkLength,
                    data: includeData ? slice : nil
                ))

                chunkStart += chunkLength
            }
        }

        return chunks
    }

    /// Reads and chunks a file from disk efficiently with buffered file reading.
    public func chunk(
        fileURL: URL,
        algorithm: HashAlgorithm? = nil,
        includeData: Bool = false
    ) throws -> [Chunk] {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            do {
                try handle.close()
            } catch let closeError {
                _ = closeError
            }
        }

        let fileSize = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 ?? 0
        guard fileSize > 0 else { return [] }

        // For files smaller than 32MB, memory-map or read directly
        if fileSize <= 32 * 1024 * 1024 {
            let data = try Data(contentsOf: fileURL, options: .alwaysMapped)
            return chunk(data: data, algorithm: algorithm, includeData: includeData)
        }

        // For large files (>32MB), stream through buffer window
        let algo = algorithm ?? self.defaultAlgorithm
        return try streamChunk(handle: handle, algo: algo, includeData: includeData)
    }

    private func streamChunk(
        handle: FileHandle,
        algo: HashAlgorithm,
        includeData: Bool
    ) throws -> [Chunk] {
        var chunks: [Chunk] = []
        var chunkStartOffset: Int64 = 0
        var carryover = Data()
        let readBufferSize = 8 * 1024 * 1024

        while true {
            let chunkData = try handle.read(upToCount: readBufferSize) ?? Data()
            if chunkData.isEmpty {
                if !carryover.isEmpty {
                    let hash = algo.hexHash(data: carryover)
                    chunks.append(Chunk(
                        hash: hash,
                        algorithm: algo,
                        offset: chunkStartOffset,
                        length: carryover.count,
                        data: includeData ? carryover : nil
                    ))
                }
                break
            }

            var combined = carryover
            combined.append(chunkData)
            carryover.removeAll(keepingCapacity: true)

            // If combined is smaller than maxChunkSize and not at EOF, keep reading
            if combined.count < maxChunkSize * 2 && chunkData.count == readBufferSize {
                carryover = combined
                continue
            }

            let subChunks = chunk(data: combined, algorithm: algo, includeData: includeData)
            if subChunks.isEmpty {
                carryover = combined
                continue
            }

            // Keep the last chunk as carryover if it might continue past buffer boundary
            let lastIndex = subChunks.count - 1
            for (idx, sc) in subChunks.enumerated() {
                let isLastAndFull = (idx == lastIndex) && (chunkData.count == readBufferSize)
                if isLastAndFull && sc.length < maxChunkSize {
                    let lastSlice = combined.subdata(in: Int(sc.offset)..<combined.count)
                    carryover = lastSlice
                    break
                }

                let chunkPayload = includeData ? combined.subdata(in: Int(sc.offset)..<(Int(sc.offset) + sc.length)) : nil
                chunks.append(Chunk(
                    hash: sc.hash,
                    algorithm: algo,
                    offset: chunkStartOffset + sc.offset,
                    length: sc.length,
                    data: chunkPayload
                ))
            }

            let consumed = combined.count - carryover.count
            chunkStartOffset += Int64(consumed)
        }

        return chunks
    }

    private static func scanCutPoint(
        ptr: UnsafePointer<UInt8>,
        start: Int,
        end: Int,
        mask: UInt64,
        gearTable: [UInt64],
        fingerprint: inout UInt64
    ) -> Int? {
        var i = start
        while i < end {
            fingerprint = (fingerprint &<< 1) &+ gearTable[Int(ptr[i])]
            if (fingerprint & mask) == 0 {
                return i + 1
            }
            i += 1
        }
        return nil
    }
}
