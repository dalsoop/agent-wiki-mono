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

    /// 실측(2026-10-04, /Applications/AgentWikiStudio.app): 패키지 이름(`GujoAgentWikiEditor`)이
    /// 앱 이름과 달라 앞 칸 규칙이 빈손이었고, 화면 모듈 묶음이 먼저 집혀 메뉴가 키 그대로 샜다.
    /// 타깃 이름(=실행 파일 이름)으로 **끝나는** 묶음도 앱 묶음이다.
    func testAppBundleMatchedBySuffixWinsOverUIModuleBundle() throws {
        _ = try makeBundle("AgentWikiUI_KnowledgeBaseWikiUI")
        _ = try makeBundle("swiftkit-sparkle_SparkleUpdateKit")
        _ = try makeBundle("swiftkit_SettingsUIKit")
        let app = try makeBundle("GujoAgentWikiEditor_AgentWikiStudio")

        let resolved = ResourceBundle.resolveLocalization(
            preferredName: nil, roots: [root],
            appNames: ["agent-wiki-editor", "AgentWikiStudio"])

        XCTAssertEqual(resolved?.bundleURL.standardizedFileURL, app.standardizedFileURL,
                       "화면 모듈 묶음이 앱 묶음을 이겼다 — 메뉴가 키 그대로 샌다")
    }

    /// 실측(2026-10-04, /Applications/AgentWikiGlobal.app): 실행 파일은 `AgentWikiGlobal` 이지만
    /// 지금 타깃은 `AgentWikiSynchronizer` 다. Resources 에 옛 타깃 이름의 묶음
    /// `…_AgentWikiGlobal`(키 94개, 옛 빌드 잔재)과 지금 묶음 `…_AgentWikiSynchronizer`(키 99개)가
    /// 함께 있다. 번들 식별자 마지막 칸(`agent-wiki-synchronizer`)이 실행 파일 이름보다 강해야 한다.
    func testBundleIdentifierTailBeatsExecutableNameForStaleBundle() throws {
        _ = try makeBundle("GujoAgentWikiSynchronizer_AgentWikiGlobal")
        _ = try makeBundle("swiftkit_SettingsUIKit")
        let current = try makeBundle("GujoAgentWikiSynchronizer_AgentWikiSynchronizer")

        let resolved = ResourceBundle.resolveLocalization(
            preferredName: nil, roots: [root],
            appNames: ["agent-wiki-synchronizer", "AgentWikiGlobal"])

        XCTAssertEqual(resolved?.bundleURL.standardizedFileURL, current.standardizedFileURL,
                       "옛 타깃 이름 묶음이 지금 묶음을 이겼다")
        XCTAssertEqual(
            ResourceBundle.resolveLocalizationRoot(
                preferredName: nil, roots: [root],
                appNames: ["agent-wiki-synchronizer", "AgentWikiGlobal"])?.standardizedFileURL,
            current.standardizedFileURL)
    }

    /// 다른 agent-wiki 앱: 실행 파일 이름(`AgentWikiGraph`, `AgentWikiLocal`)이 타깃과 달라도
    /// 번들 식별자 마지막 칸으로 앱 묶음을 고른다.
    func testBundleIdentifierTailMatchesTargetWhenExecutableDiffers() throws {
        _ = try makeBundle("swiftkit_OnboardingUIKit")
        _ = try makeBundle("swiftkit-sparkle_SparkleUpdateKit")
        let app = try makeBundle("GujoAgentWikiGrapher_AgentWikiGrapher")

        let resolved = ResourceBundle.resolveLocalization(
            preferredName: nil, roots: [root],
            appNames: ["agent-wiki-grapher", "AgentWikiGraph"])
        XCTAssertEqual(resolved?.bundleURL.standardizedFileURL, app.standardizedFileURL)
    }

    func testBundleNameMatchRules() {
        XCTAssertTrue(ResourceBundle.bundleNameMatchesApp("Mounter_Mounter", app: "Mounter"))
        XCTAssertTrue(ResourceBundle.bundleNameMatchesApp("GujoAgentWikiEditor_AgentWikiStudio", app: "AgentWikiStudio"))
        XCTAssertTrue(ResourceBundle.bundleNameMatchesApp("GujoAgentWikiIndexer_AgentWikiIndexer", app: "agent-wiki-indexer"))
        XCTAssertFalse(ResourceBundle.bundleNameMatchesApp("AgentWikiUI_KnowledgeBaseWikiUI", app: "AgentWikiStudio"))
        // 이름 일부만 겹치는 것은 맞지 않는다(구분자 `_` 경계).
        XCTAssertFalse(ResourceBundle.bundleNameMatchesApp("Pkg_XAgentWikiStudio", app: "AgentWikiStudio"))
        XCTAssertFalse(ResourceBundle.bundleNameMatchesApp("Pkg_Target", app: ""))
    }

    func testMainAppNamesPutsBundleIdentifierTailFirst() throws {
        let app = root.appendingPathComponent("Demo.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(
            at: contents.appendingPathComponent("MacOS", isDirectory: true), withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>CFBundleIdentifier</key><string>net.example.demo-target</string>
        <key>CFBundleExecutable</key><string>DemoProduct</string>
        </dict></plist>
        """
        try plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
        let exec = contents.appendingPathComponent("MacOS/DemoProduct")
        try Data().write(to: exec)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exec.path)
        let bundle = try XCTUnwrap(Bundle(url: app))
        XCTAssertEqual(ResourceBundle.mainAppNames(main: bundle), ["demo-target", "DemoProduct"])
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
