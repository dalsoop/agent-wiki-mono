import Foundation
import XCTest
@testable import PackageIdentityKit

final class PackageIdentityKitTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PackageIdentityKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
    }

    // 1. Helpers 두 단계 위 1건
    func testHelpersTwoLevelsUpLoadsContentsPlist() throws {
        let appBundle = tempDir.appendingPathComponent("Demo.app")
        let contents = appBundle.appendingPathComponent("Contents")
        let helpers = contents.appendingPathComponent("Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)

        let plistData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>kr.gujo.demo</string>
            <key>CFBundleShortVersionString</key>
            <string>1.2.3</string>
            <key>CFBundleName</key>
            <string>Demo</string>
            <key>CFBundleDisplayName</key>
            <string>Demo App</string>
            <key>AgentAppPurpose</key>
            <string>A test app for verification</string>
            <key>AgentAppStateRootEnv</key>
            <string>SWIFT_APP_STATE_ROOT</string>
        </dict>
        </plist>
        """.data(using: .utf8)!
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        let exeURL = helpers.appendingPathComponent("demo-cli")
        try Data("exe".utf8).write(to: exeURL)

        let identity = AppIdentityLocator.locate(executable: exeURL)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity?.bundleIdentifier, "kr.gujo.demo")
        XCTAssertEqual(identity?.version, "1.2.3")
        XCTAssertEqual(identity?.shortVersion, "1.2.3")
        XCTAssertEqual(identity?.display, "Demo App")
        XCTAssertEqual(identity?.displayName, "Demo App")
        XCTAssertEqual(identity?.purpose, "A test app for verification")
        XCTAssertEqual(identity?.stateRootEnv, "SWIFT_APP_STATE_ROOT")
    }

    // 2. 심링크 1건
    func testSymlinkResolvesToHelpersPlist() throws {
        let appBundle = tempDir.appendingPathComponent("Demo.app")
        let contents = appBundle.appendingPathComponent("Contents")
        let helpers = contents.appendingPathComponent("Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)

        let plistData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>kr.gujo.symlink</string>
            <key>CFBundleShortVersionString</key>
            <string>2.0.0</string>
            <key>AgentAppPurpose</key>
            <string>Symlink resolved purpose</string>
            <key>AgentAppStateRootEnv</key>
            <string>SWIFT_APP_STATE_ROOT</string>
        </dict>
        </plist>
        """.data(using: .utf8)!
        try plistData.write(to: contents.appendingPathComponent("Info.plist"))

        let realExe = helpers.appendingPathComponent("demo-cli")
        try Data("exe".utf8).write(to: realExe)

        let binDir = tempDir.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        let symlinkURL = binDir.appendingPathComponent("demo-link")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: realExe)

        let identity = AppIdentityLocator.locate(executable: symlinkURL)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity?.bundleIdentifier, "kr.gujo.symlink")
        XCTAssertEqual(identity?.version, "2.0.0")
        XCTAssertEqual(identity?.purpose, "Symlink resolved purpose")
        XCTAssertEqual(identity?.stateRootEnv, "SWIFT_APP_STATE_ROOT")
    }

    // 3. 개발 빌드 .build 위로 올라가기 1건
    func testDevBuildWalksUpToPackageIdentity() throws {
        let appRoot = tempDir.appendingPathComponent("demo-app")
        let devBuildDir = appRoot.appendingPathComponent(".build/arm64-apple-macosx/debug")
        let packagingDir = appRoot.appendingPathComponent("Packaging")
        try FileManager.default.createDirectory(at: devBuildDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packagingDir, withIntermediateDirectories: true)

        let identityJSON = """
        {
            "schema_version": 1,
            "object": "DemoApp",
            "display": "Demo App Display",
            "cli": "demo-cli",
            "cli_product": "demo-cli",
            "purpose": "Dev build purpose",
            "state_root_env": "SWIFT_APP_STATE_ROOT",
            "former_cli_names": ["old-demo", "legacy-demo"]
        }
        """.data(using: .utf8)!
        try identityJSON.write(to: packagingDir.appendingPathComponent("package-identity.json"))

        let plistData = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>kr.gujo.dev</string>
            <key>CFBundleShortVersionString</key>
            <string>3.0.0-dev</string>
        </dict>
        </plist>
        """.data(using: .utf8)!
        try plistData.write(to: packagingDir.appendingPathComponent("Info.plist"))

        let exeURL = devBuildDir.appendingPathComponent("demo-cli")
        try Data("exe".utf8).write(to: exeURL)

        let identity = AppIdentityLocator.locate(executable: exeURL)
        XCTAssertNotNil(identity)
        XCTAssertEqual(identity?.purpose, "Dev build purpose")
        XCTAssertEqual(identity?.stateRootEnv, "SWIFT_APP_STATE_ROOT")
        XCTAssertEqual(identity?.cli, "demo-cli")
        XCTAssertEqual(identity?.display, "Demo App Display")
        XCTAssertEqual(identity?.formerCLINames, ["old-demo", "legacy-demo"])
        XCTAssertEqual(identity?.version, "3.0.0-dev")
        XCTAssertEqual(identity?.bundleIdentifier, "kr.gujo.dev")
    }

    // 4. 없음 → nil 1건
    func testMissingIdentityReturnsNil() throws {
        let orphanDir = tempDir.appendingPathComponent("orphan/bin")
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        let exeURL = orphanDir.appendingPathComponent("orphan-cli")
        try Data("exe".utf8).write(to: exeURL)

        XCTAssertNil(AppIdentityLocator.locate(executable: exeURL))
        XCTAssertNil(AppIdentityLocator.locate(executable: nil))
    }

    func testWhitespaceOnlyStringsTreatedAsNil() throws {
        let json: [String: Any] = [
            "purpose": "   ",
            "state_root_env": "  \n\t  ",
            "display": "   ",
        ]
        let identity = AppIdentity(json: json)
        XCTAssertNil(identity.purpose)
        XCTAssertNil(identity.stateRootEnv)
        XCTAssertNil(identity.display)
    }
}
