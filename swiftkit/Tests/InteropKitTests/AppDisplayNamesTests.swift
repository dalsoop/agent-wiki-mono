import XCTest
@testable import InteropKit

/// 표시명 축의 계약 — 설치 번들의 Info.plist·ko.lproj 에서 읽고, 레지스트리에 실린다.
final class AppDisplayNamesTests: XCTestCase {
    private var root = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("app-display-names-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// `Demo.app` 을 만들고 Helpers CLI 경로를 돌려준다.
    @discardableResult
    private func makeApp(
        info: [String: String],
        infoPlistKo: String? = nil,
        localizableKo: String? = nil
    ) throws -> URL {
        let fm = FileManager.default
        let contents = root.appendingPathComponent("Demo.app/Contents", isDirectory: true)
        let helpers = contents.appendingPathComponent("Helpers", isDirectory: true)
        let ko = contents.appendingPathComponent("Resources/ko.lproj", isDirectory: true)
        try fm.createDirectory(at: helpers, withIntermediateDirectories: true)
        try fm.createDirectory(at: ko, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        if let infoPlistKo {
            try infoPlistKo.write(to: ko.appendingPathComponent("InfoPlist.strings"), atomically: true, encoding: .utf8)
        }
        if let localizableKo {
            try localizableKo.write(to: ko.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        let cli = helpers.appendingPathComponent("demo-cli")
        // 실행 가능해야 upsert 정규화(`resolveAbsoluteCLI`)가 이 경로를 그대로 둔다.
        fm.createFile(atPath: cli.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        return cli
    }

    private var bundlePath: String { root.appendingPathComponent("Demo.app").path }

    func testReadsEnglishAndKoreanFromInfoPlistStrings() throws {
        try makeApp(
            info: ["CFBundleName": "Demo", "CFBundleDisplayName": "Demo Manager"],
            infoPlistKo: "\"CFBundleDisplayName\" = \"데모 관리자\";\n"
        )
        let names = AppDisplayNames.read(bundlePath: bundlePath)
        XCTAssertEqual(names.displayName, "Demo Manager")
        XCTAssertEqual(names.displayNameKo, "데모 관리자")
    }

    func testFallsBackToLocalizableAppNameOnlyWhenHangul() throws {
        try makeApp(
            info: ["CFBundleName": "Demo"],
            localizableKo: "\"app.name\" = \"데모\";\n"
        )
        let names = AppDisplayNames.read(bundlePath: bundlePath)
        XCTAssertEqual(names.displayName, "Demo")
        XCTAssertEqual(names.displayNameKo, "데모")
    }

    func testUntranslatedLocalizableValueIsNotAKoreanName() throws {
        try makeApp(
            info: ["CFBundleName": "Demo"],
            localizableKo: "\"app.name\" = \"demo-cli\";\n"
        )
        XCTAssertNil(AppDisplayNames.read(bundlePath: bundlePath).displayNameKo)
    }

    func testResolveFollowsHelpersSymlink() throws {
        let cli = try makeApp(
            info: ["CFBundleDisplayName": "Demo Manager"],
            infoPlistKo: "\"CFBundleDisplayName\" = \"데모 관리자\";\n"
        )
        let link = root.appendingPathComponent("bin-demo-cli")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: cli)
        let names = AppDisplayNames.resolve(bundleId: "", cli: link.path, applicationDirectories: [])
        XCTAssertEqual(names, AppDisplayNames(displayName: "Demo Manager", displayNameKo: "데모 관리자"))
    }

    func testResolveFindsBundleByIdentifier() throws {
        try makeApp(info: ["CFBundleIdentifier": "net.ranode.demo", "CFBundleName": "Demo"])
        let names = AppDisplayNames.resolve(
            bundleId: "net.ranode.demo", cli: "/nonexistent/demo-cli", applicationDirectories: [root.path]
        )
        XCTAssertEqual(names.displayName, "Demo")
    }

    func testRegistryUpsertStoresDisplayNamesAndOldEntriesStillDecode() throws {
        let cli = try makeApp(
            info: ["CFBundleDisplayName": "Demo Manager"],
            infoPlistKo: "\"CFBundleDisplayName\" = \"데모 관리자\";\n"
        )
        let store = RegistryStore(fileURL: root.appendingPathComponent("apps.json"))
        let caps = Capabilities(
            name: "demo-cli",
            bundleId: "",
            version: "1",
            cli: cli.path,
            commands: [],
            state: [],
            health: .init(command: "", freshness: "")
        )
        let registry = try store.upsert(caps)
        XCTAssertEqual(registry.apps["demo-cli"]?.displayName, "Demo Manager")
        XCTAssertEqual(registry.apps["demo-cli"]?.displayNameKo, "데모 관리자")

        // 표시명이 없는 옛 항목은 키 없이 인코딩되고 nil 로 디코드된다.
        let plain = try JSONEncoder().encode(caps)
        let json = try XCTUnwrap(String(data: plain, encoding: .utf8))
        XCTAssertFalse(json.contains("displayName"))
        XCTAssertNil(try JSONDecoder().decode(Capabilities.self, from: plain).displayName)
    }

    func testSearchMatchesKoreanDisplayName() throws {
        let cli = try makeApp(
            info: ["CFBundleDisplayName": "Demo Manager"],
            infoPlistKo: "\"CFBundleDisplayName\" = \"데모 관리자\";\n"
        )
        let store = RegistryStore(fileURL: root.appendingPathComponent("apps.json"))
        try store.upsert(Capabilities(
            name: "demo-cli",
            bundleId: "",
            version: "1",
            cli: cli.path,
            commands: [],
            state: [],
            health: .init(command: "", freshness: "")
        ))
        let searcher = CapabilitySearcher(store: store)
        let entry = searcher.catalogEntries().first { $0.name == "demo-cli" }
        XCTAssertEqual(entry?.displayNames, ["Demo Manager", "데모 관리자"])
    }
}
