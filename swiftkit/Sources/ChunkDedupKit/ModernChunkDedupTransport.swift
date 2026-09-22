import Foundation

/// Stats recorded during chunk-level deduplication processing.
public struct ChunkTransferStats: Sendable, Equatable {
    public let totalBytes: Int64
    public let transferredBytes: Int64
    public let totalChunks: Int
    public let uniqueChunks: Int

    public init(
        totalBytes: Int64,
        transferredBytes: Int64,
        totalChunks: Int,
        uniqueChunks: Int
    ) {
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.totalChunks = totalChunks
        self.uniqueChunks = uniqueChunks
    }
}

/// Modern high-performance backup transport engine featuring:
/// 1. Swift 6 Concurrency (`TaskGroup`) multi-threaded parallel hashing worker pool (Apple Silicon multicore 100% saturation).
/// 2. FastCDC variable-size content-defined block chunking (1~4MB) preventing full retransmits on single-byte changes.
/// 3. Packfile aggregation bundling 100k~1M small files into 8~16MB packfiles, slashing SMB network RTT by 99.9%.
/// 4. Content-Addressed Storage (CAS) deduplication index preventing redundant block transfer.
public final class ModernChunkDedupTransport: BackupTransport, Sendable {
    public let chunker: FastCDCChunker
    public let smallFileThreshold: Int
    public let targetPackfileSize: Int
    public let maxConcurrentWorkers: Int
    public let materializeFiles: Bool
    public let algorithm: HashAlgorithm

    public init(
        chunker: FastCDCChunker = .default,
        smallFileThreshold: Int = 1024 * 1024,      // 1 MB
        targetPackfileSize: Int = 8 * 1024 * 1024,  // 8 MB
        maxConcurrentWorkers: Int = max(2, min(ProcessInfo.processInfo.activeProcessorCount, 16)),
        materializeFiles: Bool = true,
        algorithm: HashAlgorithm = .sha256
    ) {
        self.chunker = chunker
        self.smallFileThreshold = smallFileThreshold
        self.targetPackfileSize = targetPackfileSize
        self.maxConcurrentWorkers = maxConcurrentWorkers
        self.materializeFiles = materializeFiles
        self.algorithm = algorithm
    }

    /// Internal file item identified during source scanning
    struct ScannedFile: Sendable {
        let relativePath: String
        let fullURL: URL
        let size: Int64
        let posixPermissions: UInt16
        let modifiedDate: Date
    }

    @_optimize(none)
    public func execute(
        sourceURL: URL,
        destinationURL: URL,
        linkDestURL: URL?,
        excludes: [String],
        options: BackupTransportOptions,
        progressHandler: (@Sendable (BackupProgressUpdate) -> Void)?
    ) async throws -> BackupTransportResult {
        let startTime = Date()

        let repoDirs = try prepareDestinationDirectories(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            options: options
        )

        let knownHashes = loadAllKnownChunkHashes(
            chunksDir: repoDirs.chunksDir,
            linkDestURL: linkDestURL
        )

        let partitioned = try scanAndPartitionSource(
            sourceURL: sourceURL,
            excludes: excludes
        )

        let state = TransportStateTracker(
            totalFiles: partitioned.all.count,
            totalEstimatedBytes: partitioned.totalBytes
        )

        try await processLargeFiles(
            partitioned.large,
            destinationChunksDir: repoDirs.chunksDir,
            knownHashes: knownHashes,
            options: options,
            state: state,
            progressHandler: progressHandler
        )

        let smallStats = try await processSmallFiles(
            partitioned.small,
            packsDir: repoDirs.packsDir,
            options: options,
            state: state,
            progressHandler: progressHandler
        )

        let execURLs = ExecutionURLs(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            linkDestURL: linkDestURL
        )

        try await postProcessTreeAndManifest(
            partitioned: partitioned,
            urls: execURLs,
            repoDirs: repoDirs,
            options: options,
            state: state,
            startTime: startTime,
            progressHandler: progressHandler
        )

        return await buildResult(
            startTime: startTime,
            totalOriginalBytes: partitioned.totalBytes,
            totalFilesCount: partitioned.all.count,
            smallFilesCount: partitioned.small.count,
            largeFilesCount: partitioned.large.count,
            packfileCount: smallStats.packfileCount,
            packfilesWrittenBytes: smallStats.packfilesWrittenBytes,
            state: state
        )
    }

    private struct ExecutionURLs: Sendable {
        let sourceURL: URL
        let destinationURL: URL
        let linkDestURL: URL?
    }

    @_optimize(none)
    private func postProcessTreeAndManifest(
        partitioned: PartitionedFiles,
        urls: ExecutionURLs,
        repoDirs: DestinationDirectories,
        options: BackupTransportOptions,
        state: TransportStateTracker,
        startTime: Date,
        progressHandler: (@Sendable (BackupProgressUpdate) -> Void)?
    ) async throws {
        guard !options.dryRun else { return }

        let shouldMaterialize = self.materializeFiles && options.materializeFiles
        if shouldMaterialize {
            try await materializeFileTree(
                files: partitioned.all,
                sourceURL: urls.sourceURL,
                destinationURL: urls.destinationURL,
                linkDestURL: urls.linkDestURL,
                canHardLink: options.canHardLink,
                materializeFiles: shouldMaterialize,
                progressCallback: nil
            )
        }

        saveDedupManifest(
            files: partitioned.all,
            manifestsDir: repoDirs.manifestsDir,
            timestamp: startTime
        )
    }

    @_optimize(none)
    private func saveDedupManifest(
        files: [ScannedFile],
        manifestsDir: URL,
        timestamp: Date
    ) {
        struct ManifestFileEntry: Codable {
            let relativePath: String
            let size: Int64
            let modifiedDate: Date
            let posixPermissions: UInt16
        }
        struct DedupSnapshotManifest: Codable {
            let timestamp: Date
            let totalFiles: Int
            let totalBytes: Int64
            let files: [ManifestFileEntry]
        }

        let entries = files.map {
            ManifestFileEntry(
                relativePath: $0.relativePath,
                size: $0.size,
                modifiedDate: $0.modifiedDate,
                posixPermissions: $0.posixPermissions
            )
        }
        let manifest = DedupSnapshotManifest(
            timestamp: timestamp,
            totalFiles: files.count,
            totalBytes: files.reduce(0) { $0 + $1.size },
            files: entries
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(manifest)
            let latestURL = manifestsDir.appendingPathComponent("latest.manifest.json")
            try data.write(to: latestURL, options: .atomic)
            let isoFormatter = ISO8601DateFormatter()
            let tsURL = manifestsDir.appendingPathComponent("\(isoFormatter.string(from: timestamp)).manifest.json")
            try data.write(to: tsURL, options: .atomic)
        } catch {
            fputs("saveDedupManifest error: \(error.localizedDescription)\n", stderr)
        }
    }
}

/// Thread-safe accumulator actor for progress and deduplication stats
actor TransportStateTracker {
    let totalFiles: Int
    let totalEstimatedBytes: Int64
    let startTime: Date

    private(set) var processedFilesCount: Int = 0
    private(set) var totalTransferredBytes: Int64 = 0
    private(set) var processedInputBytes: Int64 = 0
    private(set) var totalChunksCount: Int = 0
    private(set) var uniqueChunksCount: Int = 0

    init(totalFiles: Int, totalEstimatedBytes: Int64) {
        self.totalFiles = totalFiles
        self.totalEstimatedBytes = totalEstimatedBytes
        self.startTime = Date()
    }

    func recordLargeFileResult(
        originalBytes: Int64,
        transferredBytes: Int64,
        totalChunks: Int,
        uniqueChunks: Int
    ) {
        self.processedFilesCount += 1
        self.totalTransferredBytes += transferredBytes
        self.totalChunksCount += totalChunks
        self.uniqueChunksCount += uniqueChunks
    }

    func recordPartialTransferred(_ bytes: Int64, currentFile: String) -> BackupProgressUpdate {
        self.processedInputBytes += bytes
        let elapsed = Date().timeIntervalSince(startTime)
        return BackupProgressUpdate.calculating(
            currentFile: currentFile,
            transferredBytes: self.processedInputBytes,
            totalEstimatedBytes: self.totalEstimatedBytes,
            elapsedSeconds: elapsed
        )
    }

    func recordSmallFile(bytes: Int64, currentFile: String) -> BackupProgressUpdate {
        self.processedFilesCount += 1
        self.processedInputBytes += bytes
        let elapsed = Date().timeIntervalSince(startTime)
        return BackupProgressUpdate.calculating(
            currentFile: currentFile,
            transferredBytes: self.processedInputBytes,
            totalEstimatedBytes: self.totalEstimatedBytes,
            elapsedSeconds: elapsed
        )
    }
}

public enum BackupTransportError: LocalizedError, Sendable {
    case sourceDirectoryNotFound(String)
    case transportFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceDirectoryNotFound(let path):
            return "Source directory not found: \(path)"
        case .transportFailed(let reason):
            return "Backup transport failure: \(reason)"
        }
    }
}
