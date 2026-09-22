import XCTest
@testable import InteropKit

/// 번들 ID 축의 계약. 상수를 다시 적어 비교하지 않고 **행위**를 잰다.
final class CapabilitiesBundleIdTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cap-bundleid-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeApp(bundleId: String) throws -> URL {
        let helpers = root.appendingPathComponent("Demo.app/Contents/Helpers", isDirectory: true)
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        let plist = ["CFBundleIdentifier": bundleId]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: helpers.deletingLastPathComponent().appendingPathComponent("Info.plist"))
        return helpers.appendingPathComponent("demo-cli")
    }

    private func caps(bundleId: String) -> Capabilities {
        Capabilities(
            name: "demo-app",
            bundleId: bundleId,
            version: "1",
            cli: "/usr/local/bin/demo-app",
            commands: [],
            state: [],
            health: .init(command: "demo-app capabilities", freshness: "")
        )
    }

    func testBundleIdComesFromEnclosingApp() throws {
        let exe = try makeApp(bundleId: "net.ranode.demo")
        XCTAssertEqual(CapabilitiesIdentity.bundleId(executablePath: exe.path), "net.ranode.demo")
    }

    /// `.app` 밖의 맨 실행 파일은 번들이 없다 — 빈 문자열이지 크래시가 아니다.
    func testBareExecutableHasNoBundleId() throws {
        let loose = root.appendingPathComponent("loose-cli")
        FileManager.default.createFile(atPath: loose.path, contents: Data())
        XCTAssertEqual(CapabilitiesIdentity.bundleId(executablePath: loose.path), "")
    }

    func testBundleIdSurvivesEncodeDecode() throws {
        let data = try JSONEncoder().encode(caps(bundleId: "net.ranode.demo"))
        let back = try JSONDecoder().decode(Capabilities.self, from: data)
        XCTAssertEqual(back.bundleId, "net.ranode.demo")
    }

    /// 하위호환: 축이 없던 스냅샷도 디코드가 살아야 한다. 292개가 그 상태다.
    func testLegacyPayloadWithoutBundleIdStillDecodes() throws {
        let json = #"{"name":"x","version":"1","cli":"/bin/x","commands":[],"state":[],"health":{"command":"x","freshness":""}}"#
        let caps = try JSONDecoder().decode(Capabilities.self, from: Data(json.utf8))
        XCTAssertEqual(caps.bundleId, "")
    }

    /// 이 테스트가 이 MR 의 핵심 함정을 막는다.
    ///
    /// `normalizedForRegistry()` 는 새 `Capabilities` 를 짓는다. 거기서 `bundleId` 를
    /// 다시 안 실으면 **기본 인자가 켜져 upsert 를 부른 쪽(ship 훅)의 번들 ID** 가
    /// 박힌다 — 앱마다 다른 값이 하나로 뭉개지고, 아무도 눈치채지 못한다.
    /// `purpose` 가 정확히 이 방식으로 한 번 증발했었다(2026-08-10).
    func testNormalizeKeepsBundleIdInsteadOfStampingTheCaller() throws {
        let normalized = caps(bundleId: "net.ranode.demo").normalizedForRegistry()
        XCTAssertEqual(normalized.bundleId, "net.ranode.demo")
    }
}
