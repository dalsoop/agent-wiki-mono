import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite struct DualEntryTests {
    @Test func misusedWhenArgv0IsCLIName() {
        #expect(DualEntry.isMisusedAsCLI(arguments: ["/opt/homebrew/bin/agent-wiki", "version"]))
        #expect(DualEntry.isMisusedAsCLI(arguments: ["/opt/homebrew/bin/knowledge-base-wiki", "list"]))
        #expect(DualEntry.isMisusedAsCLI(arguments: ["/opt/homebrew/bin/memo-citation-ledger", "show"]))
    }

    @Test func publicCLIPrimaryIsAgentWiki() {
        #expect(DualEntry.cliProductName == "agent-wiki")
        #expect(DualEntry.cliNames.contains("agent-wiki"))
        #expect(DualEntry.cliNames.contains("knowledge-base-wiki"))
        #expect(DualEntry.cliNames.contains("memo-citation-ledger"))
        #expect(DualEntry.cliAliasName == "knowledge-base-wiki")
    }

    @Test func misusedWhenSubcommandEvenIfGUIName() {
        #expect(DualEntry.isMisusedAsCLI(arguments: [
            "/Applications/Agent Wiki.app/Contents/MacOS/KnowledgeBaseWiki",
            "version",
        ]))
        #expect(DualEntry.isMisusedAsCLI(arguments: [
            "/Applications/X.app/Contents/MacOS/KnowledgeBaseWiki",
            "tick", "checkpoint",
        ]))
        #expect(DualEntry.isMisusedAsCLI(arguments: [
            "/Applications/X.app/Contents/MacOS/KnowledgeBaseWiki",
            "--help",
        ]))
    }

    @Test func publicRepositoryAndPromotionRoutesAreCLICommands() {
        #expect(DualEntry.cliSubcommands.contains("repository"))
        #expect(DualEntry.cliSubcommands.contains("promotion"))
        #expect(DualEntry.cliSubcommands.contains("help"))
        #expect(DualEntry.cliSubcommands.contains("--help"))
    }

    @Test func notMisusedForNormalGUILaunch() {
        #expect(!DualEntry.isMisusedAsCLI(arguments: [
            "/Applications/Agent Wiki.app/Contents/MacOS/KnowledgeBaseWiki",
        ]))
        #expect(!DualEntry.isMisusedAsCLI(arguments: [
            "/Applications/Agent Wiki.app/Contents/MacOS/KnowledgeBaseWiki",
            "-NSDocumentRevisionsDebugMode", "YES",
        ]))
    }

    @Test func guiMacOSPathIsUnsafeCLI() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-entry-\(UUID().uuidString)")
        let macos = dir.appendingPathComponent("Fake.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let gui = macos.appendingPathComponent("KnowledgeBaseWiki")
        try Data([0xCA, 0xFE]).write(to: gui)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gui.path)
        #expect(!DualEntry.isSafeCLIExecutable(gui.path))
    }

    @Test func helpersPathIsSafeCLI() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-entry-h-\(UUID().uuidString)")
        let helpers = dir.appendingPathComponent("Fake.app/Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let cli = helpers.appendingPathComponent("agent-wiki")
        // minimal executable shell script
        try "#!/bin/sh\necho ok\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        #expect(DualEntry.isSafeCLIExecutable(cli.path))
    }

    @Test func installStampRoundTrip() throws {
        // 테스트 중 홈 스탬프를 건드리지 않도록 — write/read 가 같은 URL 을 쓰므로
        // 기존 값이 있어도 덮어쓴 뒤 검증하고, 가능하면 복구.
        let previous = try? String(contentsOf: DualEntry.installStampURL, encoding: .utf8)
        defer {
            if let previous {
                do { try previous.write(to: DualEntry.installStampURL, atomically: true, encoding: .utf8) } catch { _ = error }
            } else {
                try? FileManager.default.removeItem(at: DualEntry.installStampURL)
            }
        }
        try DualEntry.writeInstallStamp(version: "test.stamp.1")
        #expect(DualEntry.readInstallStamp() == "test.stamp.1")
        #expect(DualEntry.installedCLIVersion(expected: "test.stamp.1", allowProcessProbe: false) == "test.stamp.1")
    }

    @Test func oversizedBinaryIsGUIMasquerade() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-entry-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fat = dir.appendingPathComponent("agent-wiki")
        // > maxSafeCLIBytes → GUI 가장
        let blob = Data(repeating: 0x41, count: Int(DualEntry.maxSafeCLIBytes) + 1)
        try blob.write(to: fat)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fat.path)
        #expect(DualEntry.isGUIMasquerading(at: fat.path))
        #expect(!DualEntry.isSafeCLIExecutable(fat.path))
    }

    @Test func releaseSizedCLIIsSafe() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-entry-release-size-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cli = dir.appendingPathComponent("agent-wiki")
        // Studio full CLI ~11.2 MB (2026-08-20). Keep above that, below typical GUI.
        let blob = Data(repeating: 0x41, count: 11_500_000)
        try blob.write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        #expect(DualEntry.isSafeCLIExecutable(cli.path))
    }

    @Test func diagnoseFlagsGUICandidate() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-entry-diag-\(UUID().uuidString)", isDirectory: true)
        let macos = dir.appendingPathComponent("Fake.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let gui = macos.appendingPathComponent("KnowledgeBaseWiki")
        try Data([0xCA, 0xFE]).write(to: gui)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gui.path)
        let diag = DualEntry.diagnose(candidates: [gui.path])
        #expect(!diag.ok)
        #expect(diag.issues.contains { $0.contains("GUI masquerade") })
    }
}
