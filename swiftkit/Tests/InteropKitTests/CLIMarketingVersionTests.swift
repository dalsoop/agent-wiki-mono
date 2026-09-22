import Foundation
import XCTest
@testable import InteropKit

final class CLIMarketingVersionTests: XCTestCase {
    func testStubAndMainBundle() {
        XCTAssertTrue(CLIMarketingVersion.isStub("0.1.0"))
        XCTAssertFalse(CLIMarketingVersion.isStub("1.0.0"))
        XCTAssertEqual(
            CLIMarketingVersion.resolve(processPath: "/tmp/x", mainShortVersion: "2.0.0"),
            "2.0.0")
    }

    func testHelpersReadsHostPlist() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cli-mkt-\(UUID().uuidString)")
        let contents = root.appendingPathComponent("App.app/Contents")
        let helpers = contents.appendingPathComponent("Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleShortVersionString</key><string>1.4.0</string>
        </dict></plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        XCTAssertEqual(
            CLIMarketingVersion.resolve(
                processPath: helpers.appendingPathComponent("tool").path,
                mainShortVersion: "0.1.0"),
            "1.4.0")
        XCTAssertEqual(
            CLIMarketingVersion.resolve(
                processPath: helpers.appendingPathComponent("tool").path,
                mainShortVersion: "1.0.0"),
            "1.4.0")
        try? FileManager.default.removeItem(at: root)
    }

    func testCapabilitiesDefaultVersionMatchesCurrent() {
        let caps = Capabilities(
            name: "test-app",
            cli: HostPlatform.cliBinPath("test-app"),
            commands: [],
            state: [],
            health: .init(command: "test-app capabilities", freshness: "")
        )
        XCTAssertEqual(caps.version, CLIMarketingVersion.current())
    }
}
