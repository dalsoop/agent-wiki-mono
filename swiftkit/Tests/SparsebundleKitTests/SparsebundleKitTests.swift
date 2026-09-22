import Testing
import Foundation
@testable import SparsebundleKit

@Suite("SparsebundleKit Core Tests")
struct SparsebundleKitTests {

    @Test("Resolve bundle URL ensures .sparsebundle extension")
    func testResolveBundleURL() {
        let adapter = SparsebundleAdapter()
        let url1 = URL(fileURLWithPath: "/Volumes/backup/my-mac")
        let resolved1 = adapter.resolveBundleURL(from: url1)
        #expect(resolved1.lastPathComponent == "my-mac.sparsebundle")

        let url2 = URL(fileURLWithPath: "/Volumes/backup/my-mac.sparsebundle")
        let resolved2 = adapter.resolveBundleURL(from: url2)
        #expect(resolved2.lastPathComponent == "my-mac.sparsebundle")
    }

    @Test("Self-healer detects and clears stale token")
    func testSelfHealerTokenRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let bundleURL = tempDir.appendingPathComponent("test.sparsebundle")
        try FileManager.default.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let tokenURL = bundleURL.appendingPathComponent("token")
        try "stale-process-lock-data".write(to: tokenURL, atomically: true, encoding: .utf8)

        // Mock executor so hdiutil attach fails without breaking unit test
        let mockExecutor: SparsebundleAdapter.CommandExecution = { exec, args in
            return (1, "", "Mock attach failure")
        }

        let healer = SparsebundleSelfHealer(executor: mockExecutor)
        let result = try healer.checkAndHeal(bundleURL: bundleURL, staleThresholdSeconds: 0)
        #expect(result.tokenRemoved)

        // Token must now be 0 bytes anchor
        let attrs = try FileManager.default.attributesOfItem(atPath: tokenURL.path)
        let size = attrs[.size] as? Int64 ?? -1
        #expect(size == 0)
    }

    @Test("StorageLifecycleManager tests hard link support")
    func testStorageLifecycleManagerHardLinks() {
        let manager = StorageLifecycleManager()
        let localURL = FileManager.default.temporaryDirectory
        #expect(manager.supportsHardLinks(at: localURL))
    }
}
