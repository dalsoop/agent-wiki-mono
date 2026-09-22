import XCTest
@testable import LocalizationKit

/// 설치본에 `.lproj` 를 가진 번들이 둘 이상일 때 **앱 번들을 집어야 한다**.
///
/// 실측(2026-07-27, databaseviewer-swift): `/Applications/DatabaseViewer.app` 안에
/// `DatabaseViewer_DatabaseViewer.bundle` 과 `swiftkit_VPNKit.bundle` 이 둘 다 `.lproj` 를
/// 갖고 있었다. 나열 순서대로 집으면 VPNKit 이 걸리고, 거기엔 앱 키가 없어 홈 화면이
/// `home.subtitle` 같은 **키 그대로** 노출됐다.
final class ResourceBundlePriorityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("resbundle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeBundle(_ name: String) throws -> URL {
        let b = root.appendingPathComponent("\(name).bundle", isDirectory: true)
        try FileManager.default.createDirectory(
            at: b.appendingPathComponent("ko.lproj", isDirectory: true),
            withIntermediateDirectories: true)
        // Bundle(url:) 이 실제로 열리도록 Info.plist 를 심는다.
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>CFBundleIdentifier</key><string>test.\(name)</string></dict></plist>
        """
        try plist.write(to: b.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        return b
    }

    func testAppBundleWinsOverSwiftkitBundle() throws {
        _ = try makeBundle("swiftkit_VPNKit")
        let app = try makeBundle("DatabaseViewer_DatabaseViewer")

        let resolved = ResourceBundle.resolveLocalization(
            preferredName: nil, roots: [root], appName: "DatabaseViewer")

        XCTAssertEqual(resolved?.bundleURL.standardizedFileURL, app.standardizedFileURL,
                       "swiftkit 의존성 번들이 앱 번들을 이겼다 — 전 키가 raw 로 샌다")
    }

    /// 앱 번들이 없으면 기존 동작(있는 걸 씀)이 그대로여야 한다.
    func testFallsBackToDependencyBundleWhenAppBundleAbsent() throws {
        let dep = try makeBundle("swiftkit_VPNKit")
        let resolved = ResourceBundle.resolveLocalization(
            preferredName: nil, roots: [root], appName: "Whatever")
        XCTAssertEqual(resolved?.bundleURL.standardizedFileURL, dep.standardizedFileURL)
    }

    /// 실측(2026-07-27): ScreenshotSwift·WindowSnap 은 `KeyboardShortcuts_` 번들이 **먼저**
    /// 나열된다. swiftkit_ 만 걸러선 못 막는다 — 앱 이름과 맞는 번들을 집어야 한다.
    func testAppBundleWinsOverThirdPartySPMBundle() throws {
        _ = try makeBundle("KeyboardShortcuts_KeyboardShortcuts")
        let app = try makeBundle("ScreenshotSwift_ScreenshotL10n")

        let resolved = ResourceBundle.resolveLocalization(
            preferredName: nil, roots: [root], appName: "ScreenshotSwift")

        XCTAssertEqual(resolved?.bundleURL.standardizedFileURL, app.standardizedFileURL,
                       "KeyboardShortcuts 번들이 앱 번들을 이겼다 — 전 키가 raw 로 샌다")
    }

    /// 실행 파일 이름에 공백이 있어도(예: "Database Viewer") 번들 접두사와 맞춰야 한다.
    func testMatchesAppNameWithSpaces() throws {
        _ = try makeBundle("KeyboardShortcuts_KeyboardShortcuts")
        let app = try makeBundle("DatabaseViewer_DatabaseViewer")

        let resolved = ResourceBundle.resolveLocalization(
            preferredName: nil, roots: [root], appName: "Database Viewer")

        XCTAssertEqual(resolved?.bundleURL.standardizedFileURL, app.standardizedFileURL)
    }

    func testDependencyKitDetection() {
        XCTAssertTrue(ResourceBundle.isDependencyKitBundle(URL(fileURLWithPath: "/x/swiftkit_VPNKit.bundle")))
        XCTAssertTrue(ResourceBundle.isDependencyKitBundle(URL(fileURLWithPath: "/x/swiftkit-sparkle_SparkleUpdateKit.bundle")))
        XCTAssertTrue(ResourceBundle.isDependencyKitBundle(URL(fileURLWithPath: "/x/swiftkit-appscaffold_AppScaffoldKit.bundle")))
        XCTAssertFalse(ResourceBundle.isDependencyKitBundle(URL(fileURLWithPath: "/x/DatabaseViewer_DatabaseViewer.bundle")))
    }

    /// swiftkit-sparkle 의 번들은 자체 lproj 를 가져 앱 번들과 rank 동률로 경합한다 —
    /// appName 이 없는 컨텍스트(swift test)에서도 앱 번들이 이겨야 한다(2026-08-22 실측).
    func testSparkleKitBundleWithLprojLosesToAppBundle() throws {
        _ = try makeBundle("swiftkit-sparkle_SparkleUpdateKit")
        let app = try makeBundle("VSCodeExtensionRunawayMonitor_VSCodeExtensionRunawayMonitor")

        let resolved = ResourceBundle.resolveLocalization(
            preferredName: nil, roots: [root], appName: "xctest")

        XCTAssertEqual(resolved?.bundleURL.standardizedFileURL, app.standardizedFileURL,
                       "swiftkit-sparkle 번들이 앱 번들을 이겼다 — 전 키가 raw 로 샌다")
    }
}
