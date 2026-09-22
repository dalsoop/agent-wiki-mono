import Testing
import Foundation
@testable import ChunkDedupKit

@Suite("Modern Chunk Deduplication Transport Tests")
struct ModernChunkDedupTransportTests {
    @Test("Full backup transport execution with mixed small files and large files")
    func testFullTransportExecution() async throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("dedup_test_\(UUID().uuidString)")
        let sourceDir = baseDir.appendingPathComponent("source")
        let destDir = baseDir.appendingPathComponent("destination")

        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: baseDir) }

        // Create 20 small files (<32KB)
        for i in 0..<20 {
            let smallFileURL = sourceDir.appendingPathComponent("small_\(i).txt")
            let content = "Small file \(i) content: " + String(repeating: "Z", count: 500)
            try content.write(to: smallFileURL, atomically: true, encoding: .utf8)
        }

        // Create 2 large files (>64KB)
        let largeFile1URL = sourceDir.appendingPathComponent("large_1.bin")
        var large1Data = Data(count: 120 * 1024)
        for i in 0..<large1Data.count { large1Data[i] = UInt8((i * 17) & 0xFF) }
        try large1Data.write(to: largeFile1URL)

        let largeFile2URL = sourceDir.appendingPathComponent("large_2.bin")
        var large2Data = Data(count: 150 * 1024)
        for i in 0..<large2Data.count { large2Data[i] = UInt8((i * 29) & 0xFF) }
        try large2Data.write(to: largeFile2URL)

        // Setup transport with small threshold: 32KB smallFileThreshold, 16KB min chunk, 32KB avg, 64KB max
        let chunker = FastCDCChunker(
            minChunkSize: 16 * 1024,
            avgChunkSize: 32 * 1024,
            maxChunkSize: 64 * 1024,
            algorithm: .sha256
        )

        let transport = ModernChunkDedupTransport(
            chunker: chunker,
            smallFileThreshold: 32 * 1024,
            targetPackfileSize: 64 * 1024,
            maxConcurrentWorkers: 4,
            materializeFiles: true,
            algorithm: .sha256
        )

        // Progress updates capture
        let progressCapture = ProgressCapture()

        let options = BackupTransportOptions(dryRun: false, canHardLink: false)
        let result = try await transport.execute(
            sourceURL: sourceDir,
            destinationURL: destDir,
            linkDestURL: nil,
            excludes: [],
            options: options,
            progressHandler: { update in
                Task {
                    await progressCapture.add(update)
                }
            }
        )

        #expect(result.exitCode == 0)
        #expect(result.totalFiles == 22) // 20 small + 2 large
        #expect(result.totalBytes > 0)
        #expect(result.durationSeconds >= 0)

        // Check that .dedup/packs and .dedup/chunks were created
        let packsDir = destDir.appendingPathComponent(".dedup/packs")
        let chunksDir = destDir.appendingPathComponent(".dedup/chunks")
        #expect(fm.fileExists(atPath: packsDir.path))
        #expect(fm.fileExists(atPath: chunksDir.path))

        // Check materialized destination files
        #expect(fm.fileExists(atPath: destDir.appendingPathComponent("small_0.txt").path))
        #expect(fm.fileExists(atPath: destDir.appendingPathComponent("large_1.bin").path))
        #expect(fm.fileExists(atPath: destDir.appendingPathComponent("large_2.bin").path))

        // Verify progress updates occurred
        let updatesCount = await progressCapture.updates.count
        #expect(updatesCount > 0)
    }

    @Test("Incremental backup skips existing chunks when 1 byte is modified")
    func testIncrementalDeduplication() async throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("dedup_incr_\(UUID().uuidString)")
        let sourceDir = baseDir.appendingPathComponent("source")
        let destDir = baseDir.appendingPathComponent("destination")

        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: baseDir) }

        // Create a 200KB file
        let fileURL = sourceDir.appendingPathComponent("dataset.bin")
        var data = Data(count: 200 * 1024)
        for i in 0..<data.count { data[i] = UInt8((i * 31) & 0xFF) }
        try data.write(to: fileURL)

        let chunker = FastCDCChunker(
            minChunkSize: 16 * 1024,
            avgChunkSize: 32 * 1024,
            maxChunkSize: 64 * 1024,
            algorithm: .sha256
        )

        let transport = ModernChunkDedupTransport(
            chunker: chunker,
            smallFileThreshold: 8 * 1024,
            maxConcurrentWorkers: 4,
            materializeFiles: true,
            algorithm: .sha256
        )

        // 1st Backup (Full)
        let firstResult = try await transport.execute(
            sourceURL: sourceDir,
            destinationURL: destDir,
            linkDestURL: nil,
            excludes: [],
            options: BackupTransportOptions(),
            progressHandler: nil
        )

        #expect(firstResult.exitCode == 0)
        let initialTransferred = firstResult.transferredBytes
        #expect(initialTransferred > 0)

        // Modify only 1 byte in the first chunk
        data[100] ^= 0xAA
        try data.write(to: fileURL)

        // 2nd Backup (Incremental with block deduplication)
        let secondResult = try await transport.execute(
            sourceURL: sourceDir,
            destinationURL: destDir,
            linkDestURL: nil,
            excludes: [],
            options: BackupTransportOptions(),
            progressHandler: nil
        )

        #expect(secondResult.exitCode == 0)
        // Only the modified chunk should be transferred; untouched chunks skipped!
        #expect(secondResult.transferredBytes < initialTransferred)
        #expect(secondResult.stdout.contains("Saved Bytes"))
    }

    @Test("Dry run performs calculations without modifying destination directory")
    func testDryRun() async throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("dedup_dry_\(UUID().uuidString)")
        let sourceDir = baseDir.appendingPathComponent("source")
        let destDir = baseDir.appendingPathComponent("destination")

        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: baseDir) }

        let fileURL = sourceDir.appendingPathComponent("test.txt")
        try "Test dry run content".write(to: fileURL, atomically: true, encoding: .utf8)

        let transport = ModernChunkDedupTransport()
        let result = try await transport.execute(
            sourceURL: sourceDir,
            destinationURL: destDir,
            linkDestURL: nil,
            excludes: [],
            options: BackupTransportOptions(dryRun: true),
            progressHandler: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.totalFiles == 1)
        #expect(!fm.fileExists(atPath: destDir.path))
    }

    @Test("Pure CAS mode skips flat-file tree materialization while storing chunks and manifest")
    func testPureCASModeWithoutMaterialization() async throws {
        let fm = FileManager.default
        let baseDir = fm.temporaryDirectory.appendingPathComponent("dedup_pure_cas_\(UUID().uuidString)")
        let sourceDir = baseDir.appendingPathComponent("source")
        let destDir = baseDir.appendingPathComponent("destination")

        try fm.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: baseDir) }

        let subDir = sourceDir.appendingPathComponent("sub/deep/folder")
        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
        let fileURL = subDir.appendingPathComponent("data.bin")
        let testData = Data(repeating: 0x42, count: 64 * 1024)
        try testData.write(to: fileURL)

        let transport = ModernChunkDedupTransport(
            smallFileThreshold: 16 * 1024,
            materializeFiles: false
        )

        let result = try await transport.execute(
            sourceURL: sourceDir,
            destinationURL: destDir,
            linkDestURL: nil,
            excludes: [],
            options: BackupTransportOptions(dryRun: false, materializeFiles: false),
            progressHandler: nil
        )

        #expect(result.exitCode == 0)
        #expect(result.totalFiles == 1)

        // Chunks and manifests must exist
        let chunksDir = destDir.appendingPathComponent(".dedup/chunks")
        let manifestsDir = destDir.appendingPathComponent(".dedup/manifests")
        #expect(fm.fileExists(atPath: chunksDir.path))
        #expect(fm.fileExists(atPath: manifestsDir.path))
        #expect(fm.fileExists(atPath: manifestsDir.appendingPathComponent("latest.manifest.json").path))

        // Flat files and empty directory trees must NOT be materialized
        let flatFile = destDir.appendingPathComponent("sub/deep/folder/data.bin")
        #expect(!fm.fileExists(atPath: flatFile.path))
    }
}

private actor ProgressCapture {
    private(set) var updates: [BackupProgressUpdate] = []

    func add(_ update: BackupProgressUpdate) {
        updates.append(update)
    }
}
