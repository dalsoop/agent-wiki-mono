import Foundation

/// Metadata for a single file contained within a packfile.
public struct PackfileEntry: Sendable, Codable, Equatable {
    /// Relative path of the file from the backup source root.
    public let relativePath: String
    /// Byte offset of this file within the packfile's payload segment.
    public let offset: UInt64
    /// Length of the file in bytes.
    public let length: UInt64
    /// Content hash (SHA-256 or BLAKE3) of the file.
    public let hash: String
    /// POSIX file permissions (e.g. 0o644, 0o755).
    public let posixPermissions: UInt16
    /// Last modification timestamp (seconds since 1970).
    public let modifiedTimestamp: Double

    public init(
        relativePath: String,
        offset: UInt64,
        length: UInt64,
        hash: String,
        posixPermissions: UInt16 = 0o644,
        modifiedTimestamp: Double = Date().timeIntervalSince1970
    ) {
        self.relativePath = relativePath
        self.offset = offset
        self.length = length
        self.hash = hash
        self.posixPermissions = posixPermissions
        self.modifiedTimestamp = modifiedTimestamp
    }
}

/// A serialized packfile combining hundreds or thousands of small files into a single
/// contiguous 8~16MB container, crushing SMB round-trip time (RTT) overhead.
public struct Packfile: Sendable, Equatable {
    /// 8-byte magic header: "PACKDEDP"
    public static let magic = Data([0x50, 0x41, 0x43, 0x4B, 0x44, 0x45, 0x44, 0x50])
    public static let currentVersion: UInt32 = 1
    public static let headerSize = 40 // 8 (magic) + 4 (ver) + 4 (count) + 8 (idxOffset) + 8 (idxLen) + 8 (payloadLen)

    /// Unique identifier for this packfile (usually derived from index hash or UUID).
    public let id: String
    /// Array of file entries stored inside this packfile.
    public let entries: [PackfileEntry]
    /// Raw binary data of the complete packfile (header + payload + index).
    public let data: Data

    public var totalSize: Int { data.count }
    public var fileCount: Int { entries.count }

    public init(id: String, entries: [PackfileEntry], data: Data) {
        self.id = id
        self.entries = entries
        self.data = data
    }
}

/// Item to be queued for packfile aggregation.
public struct PackfileItem: Sendable {
    public let relativePath: String
    public let data: Data
    public let posixPermissions: UInt16
    public let modifiedDate: Date

    public init(
        relativePath: String,
        data: Data,
        posixPermissions: UInt16 = 0o644,
        modifiedDate: Date = Date()
    ) {
        self.relativePath = relativePath
        self.data = data
        self.posixPermissions = posixPermissions
        self.modifiedDate = modifiedDate
    }
}

/// Aggregates millions of small files into 8~16MB packfiles to reduce SMB RTT by 99.9%.
public actor PackfileAggregator {
    public let targetPackfileSize: Int
    public let smallFileThreshold: Int
    public let algorithm: HashAlgorithm

    private var currentPayload = Data()
    private var currentEntries: [PackfileEntry] = []
    private var packCounter: Int = 0

    /// Default configuration: 8MB target packfile size, 1MB small file threshold.
    public init(
        targetPackfileSize: Int = 8 * 1024 * 1024,
        smallFileThreshold: Int = 1024 * 1024,
        algorithm: HashAlgorithm = .sha256
    ) {
        precondition(targetPackfileSize > 0, "targetPackfileSize must be > 0")
        precondition(smallFileThreshold > 0, "smallFileThreshold must be > 0")
        self.targetPackfileSize = targetPackfileSize
        self.smallFileThreshold = smallFileThreshold
        self.algorithm = algorithm
    }

    /// Appends a small file. If accumulated payload hits `targetPackfileSize`, a completed Packfile is emitted.
    public func add(
        relativePath: String,
        data: Data,
        posixPermissions: UInt16 = 0o644,
        modifiedDate: Date = Date()
    ) throws -> Packfile? {
        let hash = algorithm.hexHash(data: data)
        let offset = UInt64(currentPayload.count)
        let length = UInt64(data.count)

        let entry = PackfileEntry(
            relativePath: relativePath,
            offset: offset,
            length: length,
            hash: hash,
            posixPermissions: posixPermissions,
            modifiedTimestamp: modifiedDate.timeIntervalSince1970
        )

        currentPayload.append(data)
        currentEntries.append(entry)

        if currentPayload.count >= targetPackfileSize {
            return try sealCurrentPackfile()
        }
        return nil
    }

    /// Flushes any pending files into a final Packfile.
    public func flush() throws -> Packfile? {
        guard !currentEntries.isEmpty else { return nil }
        return try sealCurrentPackfile()
    }

    /// Convenience: Packs a batch of items into packfiles.
    public func pack(items: [PackfileItem]) throws -> [Packfile] {
        var result: [Packfile] = []
        for item in items {
            if let pack = try add(
                relativePath: item.relativePath,
                data: item.data,
                posixPermissions: item.posixPermissions,
                modifiedDate: item.modifiedDate
            ) {
                result.append(pack)
            }
        }
        if let remaining = try flush() {
            result.append(remaining)
        }
        return result
    }

    private func sealCurrentPackfile() throws -> Packfile {
        packCounter += 1
        let packId = String(format: "pack-%06d-%08x", packCounter, UInt32.random(in: 0...UInt32.max))

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let indexData = try encoder.encode(currentEntries)

        let payloadLen = UInt64(currentPayload.count)
        let indexOffset = UInt64(Packfile.headerSize) + payloadLen
        let indexLen = UInt64(indexData.count)
        let fileCount = UInt32(currentEntries.count)

        var finalData = Data(capacity: Packfile.headerSize + currentPayload.count + indexData.count)

        // Header
        finalData.append(Packfile.magic)
        var ver = Packfile.currentVersion.littleEndian
        var cnt = fileCount.littleEndian
        var idxOff = indexOffset.littleEndian
        var idxLen = indexLen.littleEndian
        var payLen = payloadLen.littleEndian

        finalData.append(Data(bytes: &ver, count: 4))
        finalData.append(Data(bytes: &cnt, count: 4))
        finalData.append(Data(bytes: &idxOff, count: 8))
        finalData.append(Data(bytes: &idxLen, count: 8))
        finalData.append(Data(bytes: &payLen, count: 8))

        // Payload
        finalData.append(currentPayload)
        // Index
        finalData.append(indexData)

        let packfile = Packfile(
            id: packId,
            entries: currentEntries,
            data: finalData
        )

        // Reset state
        currentPayload.removeAll(keepingCapacity: true)
        currentEntries.removeAll(keepingCapacity: true)

        return packfile
    }

    // MARK: - Unpacking & Reading Support (Static Non-Isolated Helpers)

    /// Decodes and parses a Packfile's index table from raw data.
    public static func parseEntries(from packfileData: Data) throws -> [PackfileEntry] {
        guard packfileData.count >= Packfile.headerSize else {
            throw PackfileError.invalidHeader("Data too short to contain header")
        }

        let magic = packfileData.subdata(in: 0..<8)
        guard magic == Packfile.magic else {
            throw PackfileError.invalidMagic
        }

        let idxOff = packfileData.withUnsafeBytes { raw in
            raw.load(fromByteOffset: 16, as: UInt64.self).littleEndian
        }
        let idxLen = packfileData.withUnsafeBytes { raw in
            raw.load(fromByteOffset: 24, as: UInt64.self).littleEndian
        }

        let start = Int(idxOff)
        let end = start + Int(idxLen)
        guard start >= Packfile.headerSize, end <= packfileData.count else {
            throw PackfileError.corruptedIndex("Index offset or length out of bounds")
        }

        let indexData = packfileData.subdata(in: start..<end)
        let decoder = JSONDecoder()
        return try decoder.decode([PackfileEntry].self, from: indexData)
    }

    /// Reads an individual file entry's payload data from a Packfile.
    public static func readEntryData(from packfileData: Data, entry: PackfileEntry) throws -> Data {
        let payloadStart = Packfile.headerSize
        let fileStart = payloadStart + Int(entry.offset)
        let fileEnd = fileStart + Int(entry.length)

        guard fileStart >= payloadStart, fileEnd <= packfileData.count else {
            throw PackfileError.payloadOutOfBounds(entry.relativePath)
        }

        return packfileData.subdata(in: fileStart..<fileEnd)
    }

    /// Unpacks all files in a Packfile to the target directory.
    public static func unpack(packfileData: Data, to destinationDirectory: URL) throws {
        let entries = try parseEntries(from: packfileData)
        let fm = FileManager.default

        for entry in entries {
            let fileData = try readEntryData(from: packfileData, entry: entry)
            let targetURL = destinationDirectory.appendingPathComponent(entry.relativePath)
            let parentDir = targetURL.deletingLastPathComponent()

            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            try fileData.write(to: targetURL, options: .atomic)

            // Restore attributes
            let date = Date(timeIntervalSince1970: entry.modifiedTimestamp)
            let attrs: [FileAttributeKey: Any] = [
                .posixPermissions: NSNumber(value: entry.posixPermissions),
                .modificationDate: date
            ]
            do {
                try fm.setAttributes(attrs, ofItemAtPath: targetURL.path)
            } catch {
                _ = error
            }
        }
    }
}

public enum PackfileError: LocalizedError, Sendable {
    case invalidHeader(String)
    case invalidMagic
    case corruptedIndex(String)
    case payloadOutOfBounds(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHeader(let reason):
            return "Invalid packfile header: \(reason)"
        case .invalidMagic:
            return "Invalid packfile magic signature"
        case .corruptedIndex(let reason):
            return "Corrupted packfile index table: \(reason)"
        case .payloadOutOfBounds(let path):
            return "Packfile payload offset out of bounds for \(path)"
        }
    }
}
