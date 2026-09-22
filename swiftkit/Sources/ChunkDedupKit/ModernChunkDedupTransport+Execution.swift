import FastDiskIOKit
import Foundation

// MARK: - Execution Extension

extension ModernChunkDedupTransport {
    struct DestinationDirectories {
        let chunksDir: URL
        let packsDir: URL
        let manifestsDir: URL
    }

    struct PartitionedFiles {
        let all: [ScannedFile]
        let small: [ScannedFile]
        let large: [ScannedFile]
        let totalBytes: Int64
    }

    struct SmallFilesResult {
        let packfileCount: Int
        let packfilesWrittenBytes: Int64
    }

    func prepareDestinationDirectories(
        sourceURL: URL,
        destinationURL: URL,
        options: BackupTransportOptions
    ) throws -> DestinationDirectories {
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir) else {
            throw BackupTransportError.sourceDirectoryNotFound(sourceURL.path)
        }

        if !options.dryRun && !fm.fileExists(atPath: destinationURL.path) {
            try fm.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        }

        let dedupRoot = destinationURL.appendingPathComponent(".dedup")
        let chunksDir = dedupRoot.appendingPathComponent("chunks")
        let packsDir = dedupRoot.appendingPathComponent("packs")
        let manifestsDir = dedupRoot.appendingPathComponent("manifests")

        if !options.dryRun {
            try fm.createDirectory(at: chunksDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: packsDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: manifestsDir, withIntermediateDirectories: true)
        }

        return DestinationDirectories(
            chunksDir: chunksDir,
            packsDir: packsDir,
            manifestsDir: manifestsDir
        )
    }

    func loadAllKnownChunkHashes(
        chunksDir: URL,
        linkDestURL: URL?
    ) -> Set<String> {
        var knownChunkHashes = Set<String>()
        loadExistingChunkHashes(from: chunksDir, into: &knownChunkHashes)
        if let linkDestURL {
            let linkChunksDir = linkDestURL.appendingPathComponent(".dedup/chunks")
            loadExistingChunkHashes(from: linkChunksDir, into: &knownChunkHashes)
        }
        return knownChunkHashes
    }

    private func loadExistingChunkHashes(from chunksDir: URL, into set: inout Set<String>) {
        let entries = FastDirectoryScanner.scanEntries(in: chunksDir.path, skipping: [])
        for entry in entries where !entry.isDirectory && entry.name.hasSuffix(".chunk") {
            let hash = String(entry.name.dropLast(".chunk".count))
            set.insert(hash)
        }
    }

    @_optimize(none)
    func scanAndPartitionSource(
        sourceURL: URL,
        excludes: [String]
    ) throws -> PartitionedFiles {
        let files = try scanSourceDirectory(sourceURL: sourceURL, excludes: excludes)
        let totalOriginalBytes = files.reduce(0) { $0 + $1.size }

        var smallFiles: [ScannedFile] = []
        var largeFiles: [ScannedFile] = []
        for file in files {
            if file.size < Int64(smallFileThreshold) {
                smallFiles.append(file)
            } else {
                largeFiles.append(file)
            }
        }

        return PartitionedFiles(
            all: files,
            small: smallFiles,
            large: largeFiles,
            totalBytes: totalOriginalBytes
        )
    }

    @_optimize(none)
    private func scanSourceDirectory(
        sourceURL: URL,
        excludes: [String]
    ) throws -> [ScannedFile] {
        let fm = FileManager.default
        let resolvedSourceURL = sourceURL.resolvingSymlinksInPath()

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: resolvedSourceURL.path, isDirectory: &isDir) else {
            return []
        }

        if !isDir.boolValue {
            return scanSingleFile(resolvedSourceURL: resolvedSourceURL, excludes: excludes, fileManager: fm)
        }

        return scanDirectoryContents(resolvedSourceURL: resolvedSourceURL, excludes: excludes, fileManager: fm)
    }

    private func scanSingleFile(resolvedSourceURL: URL, excludes: [String], fileManager fm: FileManager) -> [ScannedFile] {
        let fileName = resolvedSourceURL.lastPathComponent
        guard !isExcluded(relativePath: fileName, excludes: excludes) else { return [] }
        let size = (try? fm.attributesOfItem(atPath: resolvedSourceURL.path)[.size] as? Int64) ?? 0
        let mtime = (try? fm.attributesOfItem(atPath: resolvedSourceURL.path)[.modificationDate] as? Date) ?? Date()
        let permsNum = (try? fm.attributesOfItem(atPath: resolvedSourceURL.path)[.posixPermissions] as? NSNumber)?.uint16Value
        return [ScannedFile(
            relativePath: fileName,
            fullURL: resolvedSourceURL,
            size: size,
            posixPermissions: permsNum ?? 0o644,
            modifiedDate: mtime
        )]
    }

    @_optimize(none)
    private func scanDirectoryContents(resolvedSourceURL: URL, excludes: [String], fileManager fm: FileManager) -> [ScannedFile] {
        let sourcePath = resolvedSourceURL.path
        guard let enumerator = fm.enumerator(
            at: resolvedSourceURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [ScannedFile] = []
        for case let fileURL as URL in enumerator {
            let resolvedFileURL = fileURL.resolvingSymlinksInPath()
            let path = resolvedFileURL.path
            guard path.hasPrefix(sourcePath) else { continue }

            let suffix = path.dropFirst(sourcePath.count)
            let relativePath = String(suffix).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            ) else { continue }

            if values.isDirectory ?? false {
                if isExcluded(relativePath: relativePath, excludes: excludes) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard !(isExcluded(relativePath: relativePath, excludes: excludes)) else { continue }
            guard values.isRegularFile ?? false else { continue }

            let size = Int64(values.fileSize ?? 0)
            let mtime = values.contentModificationDate ?? Date()
            let permsNum = (try? fm.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber)?.uint16Value

            result.append(ScannedFile(
                relativePath: relativePath,
                fullURL: fileURL,
                size: size,
                posixPermissions: permsNum ?? 0o644,
                modifiedDate: mtime
            ))
        }
        return result
    }

    private func isExcluded(relativePath: String, excludes: [String]) -> Bool {
        for pattern in excludes {
            if relativePath.contains(pattern) {
                return true
            }
            let range = NSRange(location: 0, length: relativePath.utf16.count)
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                if regex.firstMatch(in: relativePath, range: range) != nil {
                    return true
                }
            } catch {
                _ = error
            }
        }
        return false
    }

    @_optimize(none)
    func processLargeFiles(
        _ largeFiles: [ScannedFile],
        destinationChunksDir: URL,
        knownHashes: Set<String>,
        options: BackupTransportOptions,
        state: TransportStateTracker,
        progressHandler: (@Sendable (BackupProgressUpdate) -> Void)?
    ) async throws {
        guard !largeFiles.isEmpty else { return }

        let chunker = self.chunker
        let algo = self.algorithm
        let isDryRun = options.dryRun
        let workerCount = self.maxConcurrentWorkers

        try await withThrowingTaskGroup(of: ChunkTransferStats.self) { group in
            var submitted = 0
            for file in largeFiles {
                if submitted >= workerCount, let result = try await group.next() {
                    await state.recordLargeFileResult(
                        originalBytes: result.totalBytes,
                        transferredBytes: result.transferredBytes,
                        totalChunks: result.totalChunks,
                        uniqueChunks: result.uniqueChunks
                    )
                }

                group.addTask {
                    try await Self.processLargeFile(
                        file: file,
                        chunker: chunker,
                        algorithm: algo,
                        destinationChunksDir: destinationChunksDir,
                        dryRun: isDryRun,
                        knownHashes: knownHashes,
                        progressCallback: nil
                    )
                }
                submitted += 1
            }

            while let result = try await group.next() {
                await state.recordLargeFileResult(
                    originalBytes: result.totalBytes,
                    transferredBytes: result.transferredBytes,
                    totalChunks: result.totalChunks,
                    uniqueChunks: result.uniqueChunks
                )
            }
        }
    }

    @_optimize(none)
    private static func processLargeFile(
        file: ScannedFile,
        chunker: FastCDCChunker,
        algorithm: HashAlgorithm,
        destinationChunksDir: URL,
        dryRun: Bool,
        knownHashes: Set<String>,
        progressCallback: (@Sendable (Int64) -> Void)?
    ) async throws -> ChunkTransferStats {
        let chunks: [Chunk]
        do {
            chunks = try chunker.chunk(fileURL: file.fullURL, algorithm: algorithm, includeData: !dryRun)
        } catch {
            return ChunkTransferStats(
                totalBytes: file.size,
                transferredBytes: 0,
                totalChunks: 0,
                uniqueChunks: 0
            )
        }
        var transferredBytes: Int64 = 0
        var uniqueChunks = 0

        for chunk in chunks {
            let isNew = !knownHashes.contains(chunk.hash)
            if isNew {
                uniqueChunks += 1
                transferredBytes += Int64(chunk.length)

                if !dryRun, let payload = chunk.data {
                    writeChunkPayloadIfMissing(
                        payload: payload,
                        hash: chunk.hash,
                        destinationChunksDir: destinationChunksDir
                    )
                }
            }
            progressCallback?(Int64(chunk.length))
        }

        return ChunkTransferStats(
            totalBytes: file.size,
            transferredBytes: transferredBytes,
            totalChunks: chunks.count,
            uniqueChunks: uniqueChunks
        )
    }

    /// Resolves the 2-level sharded chunk relative path: {hash[0..2]}/{hash[2..4]}/{hash}.chunk
    public static func chunkRelativePath(for hash: String) -> String {
        guard hash.count >= 4 else {
            return "\(hash).chunk"
        }
        let p1 = String(hash.prefix(2))
        let p2 = String(hash.dropFirst(2).prefix(2))
        return "\(p1)/\(p2)/\(hash).chunk"
    }

    /// Resolves the 2-level sharded chunk file URL in the given chunks directory.
    public static func chunkURL(in chunksDir: URL, for hash: String) -> URL {
        guard hash.count >= 4 else {
            return chunksDir.appendingPathComponent("\(hash).chunk")
        }
        let p1 = String(hash.prefix(2))
        let p2 = String(hash.dropFirst(2).prefix(2))
        return chunksDir
            .appendingPathComponent(p1, isDirectory: true)
            .appendingPathComponent(p2, isDirectory: true)
            .appendingPathComponent("\(hash).chunk")
    }

    private static func writeChunkPayloadIfMissing(
        payload: Data,
        hash: String,
        destinationChunksDir: URL
    ) {
        let chunkFile = chunkURL(in: destinationChunksDir, for: hash)
        let subDir = chunkFile.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: chunkFile.path) {
                try payload.write(to: chunkFile, options: .atomic)
            }
        } catch let writeError {
            _ = writeError
        }
    }

    @_optimize(none)
    func processSmallFiles(
        _ smallFiles: [ScannedFile],
        packsDir: URL,
        options: BackupTransportOptions,
        state: TransportStateTracker,
        progressHandler: (@Sendable (BackupProgressUpdate) -> Void)?
    ) async throws -> SmallFilesResult {
        guard !smallFiles.isEmpty else {
            return SmallFilesResult(packfileCount: 0, packfilesWrittenBytes: 0)
        }

        var packfileCount = 0
        var packfilesWrittenBytes: Int64 = 0

        let aggregator = PackfileAggregator(
            targetPackfileSize: self.targetPackfileSize,
            smallFileThreshold: self.smallFileThreshold,
            algorithm: self.algorithm
        )

        for file in smallFiles {
            let data: Data
            do {
                data = try Data(contentsOf: file.fullURL)
            } catch {
                continue
            }
            let maybePackfile = try await aggregator.add(
                relativePath: file.relativePath,
                data: data,
                posixPermissions: file.posixPermissions,
                modifiedDate: file.modifiedDate
            )
            let persisted = try persistPackfileIfNeeded(
                maybePackfile,
                packsDir: packsDir,
                dryRun: options.dryRun
            )
            packfileCount += persisted.count
            packfilesWrittenBytes += persisted.bytes

            let snap = await state.recordSmallFile(
                bytes: Int64(data.count),
                currentFile: file.relativePath
            )
            progressHandler?(snap)
        }

        let lastPackfile = try await aggregator.flush()
        let flushed = try persistPackfileIfNeeded(
            lastPackfile,
            packsDir: packsDir,
            dryRun: options.dryRun
        )
        packfileCount += flushed.count
        packfilesWrittenBytes += flushed.bytes

        return SmallFilesResult(
            packfileCount: packfileCount,
            packfilesWrittenBytes: packfilesWrittenBytes
        )
    }

    private func persistPackfileIfNeeded(
        _ packfile: Packfile?,
        packsDir: URL,
        dryRun: Bool
    ) throws -> (count: Int, bytes: Int64) {
        guard let packfile else { return (0, 0) }
        if !dryRun {
            let packURL = packsDir.appendingPathComponent("\(packfile.id).pack")
            try packfile.data.write(to: packURL, options: .atomic)
        }
        return (1, Int64(packfile.data.count))
    }

    @_optimize(none)
    func buildResult(
        startTime: Date,
        totalOriginalBytes: Int64,
        totalFilesCount: Int,
        smallFilesCount: Int,
        largeFilesCount: Int,
        packfileCount: Int,
        packfilesWrittenBytes: Int64,
        state: TransportStateTracker
    ) async -> BackupTransportResult {
        let duration = Date().timeIntervalSince(startTime)
        let totalTransferred = await state.totalTransferredBytes + packfilesWrittenBytes
        let totalChunks = await state.totalChunksCount
        let uniqueChunks = await state.uniqueChunksCount

        let metrics = DeduplicationMetrics(
            totalInputBytes: totalOriginalBytes,
            uniqueBytes: totalTransferred,
            totalChunksCount: totalChunks,
            uniqueChunksCount: uniqueChunks
        )

        let stdout = """
        [ModernChunkDedupTransport] Backup completed successfully.
        - Total Files: \(totalFilesCount) (\(smallFilesCount) small, \(largeFilesCount) large)
        - Packfiles Created: \(packfileCount) (target: \(targetPackfileSize / 1024 / 1024)MB)
        - Total Input Bytes: \(totalOriginalBytes) bytes (\(String(format: "%.2f", Double(totalOriginalBytes) / 1_048_576.0)) MB)
        - Transferred / Stored Bytes: \(totalTransferred) bytes (\(String(format: "%.2f", Double(totalTransferred) / 1_048_576.0)) MB)
        - Saved Bytes: \(metrics.savedBytes) bytes (\(String(format: "%.2f", Double(metrics.savedBytes) / 1_048_576.0)) MB)
        - Deduplication Ratio: \(String(format: "%.2f", metrics.deduplicationRatio))x (\(String(format: "%.1f", metrics.savingsPercentage))% savings)
        - Duration: \(String(format: "%.3f", duration)) seconds
        - Worker Concurrency: \(self.maxConcurrentWorkers) threads
        """

        return BackupTransportResult(
            stdout: stdout,
            stderr: "",
            exitCode: 0,
            durationSeconds: duration,
            totalFiles: totalFilesCount,
            totalBytes: totalOriginalBytes,
            transferredBytes: totalTransferred,
            isPartial: false
        )
    }
}
