import XCTest
@testable import InteropKit

final class CapabilitiesIdentityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-identity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testHelpersPlistWinsOverIdentity() throws {
        let helpers = root.appendingPathComponent("Demo.app/Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let plist: [String: String] = [
            CapabilitiesIdentity.purposePlistKey: "from-plist",
            CapabilitiesIdentity.stateRootEnvPlistKey: "PLIST_ENV",
        ]
        let plistURL = helpers.deletingLastPathComponent().appendingPathComponent("Info.plist")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: plistURL)
        let packaging = root.appendingPathComponent("Packaging")
        try FileManager.default.createDirectory(at: packaging, withIntermediateDirectories: true)
        try identityJSON(purpose: "from-identity", env: "IDENTITY_ENV")
            .write(to: packaging.appendingPathComponent("package-identity.json"))
        let exe = helpers.appendingPathComponent("demo-cli").path
        FileManager.default.createFile(atPath: exe, contents: Data())

        XCTAssertEqual(CapabilitiesIdentity.purpose(executablePath: exe), "from-plist")
        XCTAssertEqual(CapabilitiesIdentity.stateRoot(executablePath: exe)?.env, "PLIST_ENV")
    }

    func testDevBuildWalksUpToPackageIdentity() throws {
        let bin = root.appendingPathComponent(".build/arm64-apple-macosx/debug")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let packaging = root.appendingPathComponent("Packaging")
        try FileManager.default.createDirectory(at: packaging, withIntermediateDirectories: true)
        try identityJSON(purpose: "dev-purpose", env: "SWIFT_APP_STATE_ROOT")
            .write(to: packaging.appendingPathComponent("package-identity.json"))
        let exe = bin.appendingPathComponent("demo-cli").path
        FileManager.default.createFile(atPath: exe, contents: Data())

        XCTAssertEqual(CapabilitiesIdentity.purpose(executablePath: exe), "dev-purpose")
        XCTAssertEqual(
            CapabilitiesIdentity.stateRoot(executablePath: exe)?.env,
            "SWIFT_APP_STATE_ROOT"
        )
    }

    func testPATHSymlinkResolvesToRealHelper() throws {
        let helpers = root.appendingPathComponent("Demo.app/Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let plist: [String: String] = [CapabilitiesIdentity.purposePlistKey: "linked-purpose"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: helpers.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        let real = helpers.appendingPathComponent("demo-cli")
        FileManager.default.createFile(atPath: real.path, contents: Data("x".utf8))
        let linkDir = root.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: linkDir, withIntermediateDirectories: true)
        let link = linkDir.appendingPathComponent("demo-cli")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: real.path)

        XCTAssertEqual(CapabilitiesIdentity.purpose(executablePath: link.path), "linked-purpose")
    }

    func testMissingIdentityPurposeIsEmptyAndStateRootIsNil() throws {
        let exe = root.appendingPathComponent("orphan-cli").path
        FileManager.default.createFile(atPath: exe, contents: Data())
        XCTAssertEqual(CapabilitiesIdentity.purpose(executablePath: exe), "")
        XCTAssertNil(CapabilitiesIdentity.stateRoot(executablePath: exe))
    }

    private func identityJSON(purpose: String, env: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "purpose": purpose,
            "state_root_env": env,
        ])
    }
}

final class CapabilitiesStateRootCodecTests: XCTestCase {
    func testOldJSONWithoutStateRootDecodesNil() throws {
        let json = """
        {
          "name": "hermes",
          "purpose": "jobs",
          "version": "1.4.0",
          "cli": "/bin/hermes",
          "commands": [],
          "state": [],
          "health": {"command": "x", "freshness": ""}
        }
        """
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
        XCTAssertNil(caps.stateRoot)
        XCTAssertEqual(caps.purpose, "jobs")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(caps)) as? [String: Any]
        XCTAssertNil(encoded?["stateRoot"])
        XCTAssertEqual(encoded?["purpose"] as? String, "jobs")
    }

    func testStateRootRoundTrip() throws {
        let caps = Capabilities(
            name: "demo",
            purpose: "demo purpose",
            version: "1.0.0",
            cli: "/bin/demo",
            commands: [],
            state: [],
            health: .init(command: "x", freshness: ""),
            owned: .init(stateRoot: .init(env: "SWIFT_APP_STATE_ROOT"))
        )
        let data = try JSONEncoder().encode(caps)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let root = try XCTUnwrap(object["stateRoot"] as? [String: Any])
        XCTAssertEqual(root["env"] as? String, "SWIFT_APP_STATE_ROOT")
        let decoded = try JSONDecoder().decode(Capabilities.self, from: data)
        XCTAssertEqual(decoded, caps)
    }
}
