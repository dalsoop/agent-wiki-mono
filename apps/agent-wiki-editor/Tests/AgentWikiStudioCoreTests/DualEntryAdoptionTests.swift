import XCTest
@testable import AgentWikiStudioCore

final class DualEntryAdoptionTests: XCTestCase {
    func testIsSafeCLIRejectsMacOSGUIPath() {
        XCTAssertFalse(
            DualEntryAdoption.isSafeCLIExecutable(
                "/Applications/Agent Wiki.app/Contents/MacOS/KnowledgeBaseWiki"
            )
        )
    }

    func testIsSafeCLIRejectsMissing() {
        XCTAssertFalse(DualEntryAdoption.isSafeCLIExecutable("/tmp/no-such-agent-wiki-\(UUID().uuidString)"))
    }

    func testStatusChecklistKeysPresent() {
        let st = DualEntryAdoption.status()
        XCTAssertTrue(st.checklist.keys.contains("studio_app_present"))
        XCTAssertTrue(st.checklist.keys.contains("adopt_source_safe"))
        XCTAssertTrue(st.checklist.keys.contains("monlith_helper_safe"))
        XCTAssertTrue(st.checklist.keys.contains("studio_helper_agent_wiki"))
        XCTAssertTrue(st.checklist.keys.contains("path_agent_wiki_safe"))
        XCTAssertTrue(st.checklist.keys.contains("path_points_to_studio"))
    }

    func testAdoptDryRunWithoutAppsDoesNotCrash() {
        let empty = DualEntryAdoption.Paths(
            monlithHelper: nil,
            studioHelper: nil,
            pathCLI: nil,
            studioApp: nil,
            monlithApp: nil,
            adoptSource: nil
        )
        let r = DualEntryAdoption.adopt(dryRun: true, runPathInstall: false, paths: empty)
        XCTAssertFalse(r.ok)
        XCTAssertTrue(r.message.contains("원본") || r.message.contains("full CLI") || r.message.contains("agent-wiki"))
    }

    func testAdoptDryRunWithSyntheticPaths() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-entry-adopt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let monlithApp = tmp.appendingPathComponent("Agent Wiki.app")
        let studioApp = tmp.appendingPathComponent("AgentWikiStudio.app")
        let monHelper = monlithApp.appendingPathComponent("Contents/Helpers/agent-wiki")
        try FileManager.default.createDirectory(
            at: monHelper.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: studioApp.appendingPathComponent("Contents/Helpers"),
            withIntermediateDirectories: true
        )
        // small fake CLI binary (shell script executable)
        let script = "#!/bin/sh\necho fake\n"
        try script.write(to: monHelper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: monHelper.path)

        let paths = DualEntryAdoption.Paths(
            monlithHelper: monHelper.path,
            studioHelper: nil,
            pathCLI: nil,
            studioApp: studioApp.path,
            monlithApp: monlithApp.path,
            adoptSource: monHelper.path
        )
        let dry = DualEntryAdoption.adopt(dryRun: true, runPathInstall: false, paths: paths)
        XCTAssertTrue(dry.ok)
        XCTAssertTrue(dry.message.contains("dry-run"))

        let real = DualEntryAdoption.adopt(dryRun: false, runPathInstall: false, paths: paths)
        XCTAssertTrue(real.ok, real.message)
        let dest = studioApp.appendingPathComponent("Contents/Helpers/agent-wiki")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: dest.path))
        XCTAssertTrue(DualEntryAdoption.isSafeCLIExecutable(dest.path))
    }
}
