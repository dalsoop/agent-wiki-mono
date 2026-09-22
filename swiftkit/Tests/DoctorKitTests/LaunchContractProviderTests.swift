import Foundation
import XCTest
@testable import DoctorKit

/// 빌드·서명·설치를 다 통과하고도 "아이콘을 눌러도 안 뜨는" 상태를 잡아야 한다.
final class LaunchContractProviderTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("launch-contract-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    @discardableResult
    private func makeBundle(
        name: String,
        executable: String,
        identity: [String: Any]
    ) throws -> URL {
        let bundle = root.appendingPathComponent("\(name).app", isDirectory: true)
        let resources = bundle.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resources, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: identity)
            .write(to: resources.appendingPathComponent("package-identity.json"))
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": executable], format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        return bundle
    }

    private var helpersIdentity: [String: Any] {
        ["dual_entry": "helpers", "cli": "my-tool", "program": "my-tool",
         "cli_product": "my-tool", "gui_product": "MyTool"]
    }

    func testFlagsBundleWhoseGUIExecutableIsTheCLIName() throws {
        let bundle = try makeBundle(name: "MyTool", executable: "my-tool", identity: helpersIdentity)
        let finding = try XCTUnwrap(LaunchContractProvider().finding(for: bundle))
        // 번들만으로는 가드 호출 여부를 알 수 없다 — 확정(fail)은 소스를 보는 auditor 몫.
        XCTAssertEqual(finding.severity, .warn)
        XCTAssertEqual(finding.category, .install)
        XCTAssertEqual(finding.payload["executable"], "my-tool")
        XCTAssertEqual(finding.payload["guiProduct"], "MyTool")
        XCTAssertTrue(finding.remedy?.contains("MyTool") ?? false, "고치는 법을 알려줘야 한다")
    }

    func testCorrectBundleIsNotFlagged() throws {
        let bundle = try makeBundle(name: "MyTool", executable: "MyTool", identity: helpersIdentity)
        XCTAssertNil(LaunchContractProvider().finding(for: bundle))
    }

    /// dual-entry 가 아닌 앱은 가드를 부르지 않으므로 같은 이름이어도 문제가 없다.
    func testNonDualEntryBundleIsIgnored() throws {
        var identity = helpersIdentity
        identity["dual_entry"] = "single"
        let bundle = try makeBundle(name: "MyTool", executable: "my-tool", identity: identity)
        XCTAssertNil(LaunchContractProvider().finding(for: bundle))
    }

    /// identity 선언이 없는 번들은 판단 근거가 없다 — 조용히 넘긴다(오탐 금지).
    func testBundleWithoutIdentityIsIgnored() throws {
        let bundle = root.appendingPathComponent("Bare.app", isDirectory: true)
        try fm.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": "Bare"], format: .xml, options: 0)
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        XCTAssertNil(LaunchContractProvider().finding(for: bundle))
    }

    func testScanReportsOnlyBrokenBundles() async throws {
        try makeBundle(name: "Broken", executable: "my-tool", identity: helpersIdentity)
        try makeBundle(name: "Fine", executable: "MyTool", identity: helpersIdentity)
        let findings = await LaunchContractProvider(applicationsDirectory: root).run()
        XCTAssertEqual(findings.map(\.subject), ["Broken.app"])
    }
}
