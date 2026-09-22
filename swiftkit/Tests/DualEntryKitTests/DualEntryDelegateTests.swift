import XCTest
@testable import DualEntryKit

/// `dual_entry=helpers` 앱의 PATH CLI 가 앱 본체의 argv 명령을 넘겨받는 규칙.
///
/// 배경(2026-07-27 실측): helpers 계약상 PATH 에 GUI 를 링크할 수 없어 CLI 는 스텁인데,
/// 실제 명령은 GUI 타깃의 argv 디스패치가 소유한다. 그 결과 `app-build-manager ship …`
/// 처럼 **문서화된 사용법이 PATH 에서 죽어 있었다**(ADM·quality-auditor·swift-app-store 셋 다).
final class DualEntryDelegateTests: XCTestCase {
    private var root: URL!

    private func profile(gui: String = "MyApp") -> DualEntryProfile {
        DualEntryProfile(
            mode: .helpers,
            guiExecutableName: gui,
            cliProductName: "my-app",
            stampHomeRelativeDir: ".my-app"
        )
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("dual-entry-delegate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// 번들 안에 실행 가능한 GUI 를 만들고 그 앱 디렉터리 경로를 돌려준다.
    @discardableResult
    private func makeApp(named bundle: String, gui: String, executable: Bool = true) throws -> String {
        let macos = root.appendingPathComponent("\(bundle).app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let bin = macos.appendingPathComponent(gui)
        try "#!/bin/sh\n".write(to: bin, atomically: true, encoding: .utf8)
        if executable {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)
        }
        return bin.path
    }

    // MARK: - 위임 판정

    func testDelegatesUnknownCommands() {
        let local: Set<String> = ["help", "version", "open"]
        XCTAssertTrue(DualEntryDelegate.shouldDelegate("ship", handledLocally: local))
        XCTAssertTrue(DualEntryDelegate.shouldDelegate("status", handledLocally: local))
    }

    func testDoesNotDelegateLocallyHandledCommands() {
        let local: Set<String> = ["help", "version", "open"]
        for c in local {
            XCTAssertFalse(DualEntryDelegate.shouldDelegate(c, handledLocally: local), c)
        }
    }

    /// 인자 없이 부르면 스텁의 usage 가 나와야 한다 — 빈 위임은 GUI 를 띄울 수 있다.
    func testDoesNotDelegateEmptyInvocation() {
        XCTAssertFalse(DualEntryDelegate.shouldDelegate(nil, handledLocally: []))
        XCTAssertFalse(DualEntryDelegate.shouldDelegate("", handledLocally: []))
    }

    /// `-V` 같은 플래그 선행 호출은 스텁이 답한다(앱 본체를 깨우지 않는다).
    func testDoesNotDelegateLeadingFlags() {
        XCTAssertFalse(DualEntryDelegate.shouldDelegate("--version", handledLocally: []))
        XCTAssertFalse(DualEntryDelegate.shouldDelegate("-h", handledLocally: []))
    }

    // MARK: - 앱 본체 찾기

    func testLocatesGUIExecutableInsideBundle() throws {
        let expected = try makeApp(named: "MyApp", gui: "MyApp")
        XCTAssertEqual(
            DualEntryDelegate.locateGUIExecutable(profile: profile(), roots: [root.path]),
            expected
        )
    }

    /// 번들 파일명이 표시명(공백 포함)일 수 있다 — 이름을 추측하지 말고 훑어야 한다.
    func testLocatesGUIInsideBundleWithSpacedName() throws {
        let expected = try makeApp(named: "My Great App", gui: "MyApp")
        XCTAssertEqual(
            DualEntryDelegate.locateGUIExecutable(profile: profile(), roots: [root.path]),
            expected
        )
    }

    func testReturnsNilWhenNotInstalled() {
        XCTAssertNil(DualEntryDelegate.locateGUIExecutable(profile: profile(), roots: [root.path]))
    }

    /// 실행 권한이 없는 파일은 후보가 아니다(빈 껍데기 번들 오탐 방지).
    func testIgnoresNonExecutableCandidate() throws {
        try makeApp(named: "MyApp", gui: "MyApp", executable: false)
        XCTAssertNil(DualEntryDelegate.locateGUIExecutable(profile: profile(), roots: [root.path]))
    }

    func testIgnoresBundleWithDifferentGUIName() throws {
        try makeApp(named: "MyApp", gui: "SomethingElse")
        XCTAssertNil(DualEntryDelegate.locateGUIExecutable(profile: profile(), roots: [root.path]))
    }

    func testSearchesRootsInOrder() throws {
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let macos = second.appendingPathComponent("MyApp.app/Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let bin = macos.appendingPathComponent("MyApp")
        try "#!/bin/sh\n".write(to: bin, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bin.path)

        let first = try makeApp(named: "MyApp", gui: "MyApp")
        XCTAssertEqual(
            DualEntryDelegate.locateGUIExecutable(profile: profile(), roots: [root.path, second.path]),
            first,
            "앞선 루트가 우선이어야 한다"
        )
    }

    // MARK: - 실패 경로

    func testExecReturnsFalseWhenAppMissing() {
        XCTAssertFalse(
            DualEntryDelegate.exec(arguments: ["ship"], profile: profile(), roots: [root.path])
        )
    }

    func testUnavailableMessageNamesTheApp() {
        XCTAssertTrue(DualEntryDelegate.unavailableMessage(profile: profile()).contains("MyApp"))
    }

    func testDefaultRootsCoverBothApplicationsFolders() {
        let roots = DualEntryDelegate.candidateRoots(home: "/Users/x")
        XCTAssertEqual(roots, ["/Applications", "/Users/x/Applications"])
    }
}
