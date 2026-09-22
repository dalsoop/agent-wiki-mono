import Foundation
import Testing
@testable import DualEntryKit

@Suite struct DualEntryRulesTests {
    let profile = DualEntryProfile(
        mode: .helpers,
        guiExecutableName: "FakeGUI",
        cliProductName: "fake-cli",
        cliAliases: ["fake-alias"],
        cliSubcommands: ["version", "list", "dual-entry"],
        stampHomeRelativeDir: ".dual-entry-kit-test-\(UUID().uuidString.prefix(8))",
        stampFileName: "cli-install-version",
        maxSafeCLIBytes: 5_000_000
    )

    @Test func misusedWhenArgv0IsCLIName() {
        #expect(DualEntryRules.isMisusedAsCLI(
            profile: profile,
            arguments: ["/opt/homebrew/bin/fake-cli", "version"]
        ))
        #expect(DualEntryRules.isMisusedAsCLI(
            profile: profile,
            arguments: ["/opt/homebrew/bin/fake-alias", "list"]
        ))
    }

    @Test func misusedWhenSubcommandOnGUIName() {
        #expect(DualEntryRules.isMisusedAsCLI(
            profile: profile,
            arguments: ["/Applications/X.app/Contents/MacOS/FakeGUI", "version"]
        ))
    }

    @Test func permissionBootstrapIsAllowedForGUIInternalLaunch() {
        #expect(!DualEntryRules.isMisusedAsCLI(
            profile: profile,
            arguments: ["/Applications/X.app/Contents/MacOS/FakeGUI", "--permission-bootstrap=accessibility"]
        ))
    }

    @Test func notMisusedForNormalGUILaunch() {
        #expect(!DualEntryRules.isMisusedAsCLI(
            profile: profile,
            arguments: ["/Applications/X.app/Contents/MacOS/FakeGUI"]
        ))
        #expect(!DualEntryRules.isMisusedAsCLI(
            profile: profile,
            arguments: [
                "/Applications/X.app/Contents/MacOS/FakeGUI",
                "-NSDocumentRevisionsDebugMode", "YES",
            ]
        ))
    }

    @Test func guiMacOSPathIsUnsafe() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("de-kit-\(UUID().uuidString)")
        let macos = dir.appendingPathComponent("Fake.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let gui = macos.appendingPathComponent("FakeGUI")
        try Data([0xCA, 0xFE]).write(to: gui)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gui.path)
        #expect(DualEntryRules.isGUIMasquerading(at: gui.path, profile: profile))
        #expect(!DualEntryRules.isSafeCLIExecutable(gui.path, profile: profile))
    }

    @Test func helpersPathIsSafe() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("de-kit-h-\(UUID().uuidString)")
        let helpers = dir.appendingPathComponent("Fake.app/Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cli = helpers.appendingPathComponent("fake-cli")
        try "#!/bin/sh\necho ok\n".write(to: cli, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        #expect(DualEntryRules.isSafeCLIExecutable(cli.path, profile: profile))
    }

    @Test func largeHelpersCLIIsNotMasquerade() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("de-kit-hfat-\(UUID().uuidString)")
        let helpers = dir.appendingPathComponent("Fake.app/Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cli = helpers.appendingPathComponent("fake-cli")
        try Data(repeating: 0x41, count: Int(profile.maxSafeCLIBytes) + 1).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
        #expect(!DualEntryRules.isGUIMasquerading(at: cli.path, profile: profile))
        #expect(DualEntryRules.isSafeCLIExecutable(cli.path, profile: profile))
    }

    @Test func stampRoundTrip() throws {
        let url = DualEntryRules.installStampURL(profile: profile)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try DualEntryRules.writeInstallStamp(profile: profile, version: "1.2.3")
        #expect(DualEntryRules.readInstallStamp(profile: profile) == "1.2.3")
        #expect(
            DualEntryRules.installedCLIVersion(
                profile: profile, expected: "1.2.3", allowProcessProbe: false
            ) == "1.2.3"
        )
    }

    @Test func argvModeDoesNotTreatCLINameAsMisuse() {
        let argvProfile = DualEntryProfile(
            mode: .argv,
            guiExecutableName: "FakeGUI",
            cliProductName: "fake-cli",
            stampHomeRelativeDir: ".dual-entry-argv-test"
        )
        #expect(!DualEntryRules.isMisusedAsCLI(
            profile: argvProfile,
            arguments: ["/opt/homebrew/bin/fake-cli", "version"]
        ))
    }

    @Test func loadProfileFromIdentityJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("de-id-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("package-identity.json")
        try """
        {"cli":"my-cli","gui_product":"MyGUI","dual_entry":"helpers","cli_aliases":["myctl"]}
        """.write(to: url, atomically: true, encoding: .utf8)
        let p = DualEntryProfile.load(from: url)
        #expect(p?.cliProductName == "my-cli")
        #expect(p?.guiExecutableName == "MyGUI")
        #expect(p?.mode == .helpers)
        #expect(p?.cliAliases == ["myctl"])
    }

    @Test func diagnoseFlagsGUI() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("de-kit-d-\(UUID().uuidString)")
        let macos = dir.appendingPathComponent("Fake.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let gui = macos.appendingPathComponent("FakeGUI")
        try Data([0xCA, 0xFE]).write(to: gui)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gui.path)
        let diag = DualEntryRules.diagnose(profile: profile, candidates: [gui.path])
        #expect(!diag.ok)
        #expect(diag.issues.contains { $0.contains("GUI masquerade") })
    }
}
