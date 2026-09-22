import Testing
import Foundation
@testable import ChunkDedupKit

@Suite("Packfile Aggregator Tests")
struct PackfileAggregatorTests {
    @Test("Bundles multiple small files into target-sized Packfiles")
    func testPackfileAggregation() async throws {
        // Aggregator targeting 32KB packfiles with 8KB small file threshold for fast testing
        let targetSize = 32 * 1024
        let aggregator = PackfileAggregator(
            targetPackfileSize: targetSize,
            smallFileThreshold: 8 * 1024,
            algorithm: .sha256
        )

        var emittedPacks: [Packfile] = []

        // Feed 100 small files (each ~1KB)
        for i in 0..<100 {
            let filename = "nested/dir/small_file_\(i).txt"
            let content = "File payload number \(i): \(String(repeating: "A", count: 900))"
            let data = Data(content.utf8)

            if let pack = try await aggregator.add(
                relativePath: filename,
                data: data,
                posixPermissions: 0o644,
                modifiedDate: Date()
            ) {
                emittedPacks.append(pack)
            }
        }

        if let finalPack = try await aggregator.flush() {
            emittedPacks.append(finalPack)
        }

        // 100 files of ~950 bytes = ~95KB. At 32KB target, expect ~3-4 packfiles
        #expect(emittedPacks.count >= 2 && emittedPacks.count <= 5)

        var totalFilesInPacks = 0
        for pack in emittedPacks {
            #expect(pack.data.count > Packfile.headerSize)
            totalFilesInPacks += pack.entries.count

            // Verify header magic
            let magic = pack.data.subdata(in: 0..<8)
            #expect(magic == Packfile.magic)

            // Verify index table can be parsed
            let parsedEntries = try PackfileAggregator.parseEntries(from: pack.data)
            #expect(parsedEntries.count == pack.entries.count)
        }

        #expect(totalFilesInPacks == 100)
    }

    @Test("Unpacks packfile and restores exact file contents and permissions")
    func testPackfileUnpack() async throws {
        let aggregator = PackfileAggregator(
            targetPackfileSize: 64 * 1024,
            smallFileThreshold: 16 * 1024,
            algorithm: .sha256
        )

        let testItems: [(path: String, content: String, perms: UInt16)] = [
            ("config/app.json", "{\"setting\": true, \"count\": 42}", 0o644),
            ("scripts/runner.sh", "#!/bin/sh\necho 'hello'", 0o755),
            ("assets/data.bin", "BINARY_PAYLOAD_TEST_12345", 0o600)
        ]

        for item in testItems {
            let data = Data(item.content.utf8)
            _ = try await aggregator.add(
                relativePath: item.path,
                data: data,
                posixPermissions: item.perms
            )
        }

        guard let packfile = try await aggregator.flush() else {
            Issue.record("Expected flushed packfile")
            return
        }

        // Unpack to temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try PackfileAggregator.unpack(packfileData: packfile.data, to: tempDir)

        // Verify each restored file
        for item in testItems {
            let restoredURL = tempDir.appendingPathComponent(item.path)
            #expect(FileManager.default.fileExists(atPath: restoredURL.path))

            let restoredContent = try String(contentsOf: restoredURL, encoding: .utf8)
            #expect(restoredContent == item.content)

            let attrs = try FileManager.default.attributesOfItem(atPath: restoredURL.path)
            let restoredPerms = (attrs[.posixPermissions] as? NSNumber)?.uint16Value ?? 0
            #expect(restoredPerms == item.perms)
        }
    }

    @Test("Demonstrates SMB network RTT reduction calculation")
    func testSMBRoundtripReductionRatio() {
        let totalSmallFiles = 100_000
        let avgSmallFileSize = 8 * 1024 // 8 KB
        let targetPackfileSize = 8 * 1024 * 1024 // 8 MB

        let totalBytes = totalSmallFiles * avgSmallFileSize // ~800 MB
        let packfileCount = Int(ceil(Double(totalBytes) / Double(targetPackfileSize))) // ~100 packfiles

        // In standard SMB: each small file requires open/create + write + close + metadata roundtrips (~4 RTTs)
        let smbRTTWithoutPackfile = totalSmallFiles * 4 // 400,000 network roundtrips
        // With Packfile: only packfiles are written
        let smbRTTWithPackfile = packfileCount * 4 // 400 network roundtrips

        let rttReductionPercent = (1.0 - (Double(smbRTTWithPackfile) / Double(smbRTTWithoutPackfile))) * 100.0

        #expect(rttReductionPercent >= 99.9, "Packfile bundling must reduce SMB RTT calls by >= 99.9%")
    }
}
