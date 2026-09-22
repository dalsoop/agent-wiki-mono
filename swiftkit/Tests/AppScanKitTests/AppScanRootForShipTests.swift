import XCTest
@testable import AppScanKit

/// `monorepoRootForShip` 의 후보 우선순위 회귀.
///
/// 배경(백로그 44949B35): `~/.zshenv` 가 `SWIFT_APP_MONO=<mono>/main` 을 항상 export 하는데
/// 이 값이 cwd 보다 앞이라, 어떤 worktree 에서 ship 해도 `main/` 으로 끌려갔다.
final class AppScanRootForShipTests: XCTestCase {
    /// 임시로 `apps/<name>/Package.swift` 를 갖춘 가짜 monorepo 를 만든다.
    private func makeFakeMonorepo(_ label: String) throws -> String {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("appscan-\(label)-\(UUID().uuidString)")
        let app = base.appendingPathComponent("apps/probe-app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try "// swift-tools-version:5.9\n".write(
            to: app.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        return base.path
    }

    private func cleanup(_ paths: String...) {
        for p in paths { try? FileManager.default.removeItem(atPath: p) }
    }

    /// cwd 가 유효한 monorepo 면 셸 전역 `SWIFT_APP_MONO` 를 이긴다.
    func testCwdBeatsBareSwiftAppMonoEnv() throws {
        let worktree = try makeFakeMonorepo("worktree")
        let canonicalMain = try makeFakeMonorepo("main")
        defer { cleanup(worktree, canonicalMain) }

        let root = AppScan.monorepoRootForShip(
            cwd: worktree,
            environment: ["SWIFT_APP_MONO": canonicalMain]
        )
        XCTAssertEqual(root.map { ($0 as NSString).standardizingPath },
                       (worktree as NSString).standardizingPath)
    }

    /// 명시 오버라이드 `SWIFT_APP_MONO_ROOT` 는 여전히 cwd 를 이긴다.
    func testExplicitRootEnvBeatsCwd() throws {
        let worktree = try makeFakeMonorepo("worktree")
        let override = try makeFakeMonorepo("override")
        defer { cleanup(worktree, override) }

        let root = AppScan.monorepoRootForShip(
            cwd: worktree,
            environment: ["SWIFT_APP_MONO_ROOT": override]
        )
        XCTAssertEqual(root.map { ($0 as NSString).standardizingPath },
                       (override as NSString).standardizingPath)
    }

    /// `--root` 인자는 env·cwd 전부를 이긴다.
    func testExplicitRootArgumentWinsOverAll() throws {
        let worktree = try makeFakeMonorepo("worktree")
        let override = try makeFakeMonorepo("override")
        let explicit = try makeFakeMonorepo("explicit")
        defer { cleanup(worktree, override, explicit) }

        let root = AppScan.monorepoRootForShip(
            explicitRoot: explicit,
            cwd: worktree,
            environment: ["SWIFT_APP_MONO_ROOT": override, "SWIFT_APP_MONO": worktree]
        )
        XCTAssertEqual(root.map { ($0 as NSString).standardizingPath },
                       (explicit as NSString).standardizingPath)
    }

    /// cwd 가 monorepo 가 아니면 `SWIFT_APP_MONO` 가 fallback 으로 살아난다.
    func testBareEnvStillUsedWhenCwdIsNotMonorepo() throws {
        let canonicalMain = try makeFakeMonorepo("main")
        let elsewhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("appscan-plain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        defer { cleanup(canonicalMain, elsewhere.path) }

        let root = AppScan.monorepoRootForShip(
            cwd: elsewhere.path,
            environment: ["SWIFT_APP_MONO": canonicalMain]
        )
        XCTAssertEqual(root.map { ($0 as NSString).standardizingPath },
                       (canonicalMain as NSString).standardizingPath)
    }
}

final class AppScanBundleValidationTests: XCTestCase {
    private var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("appscan-validation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    @discardableResult
    private func createFakeBundle(
        name: String,
        in directory: URL,
        executableName: String? = nil,
        createExecutable: Bool = true,
        createPlist: Bool = true
    ) throws -> URL {
        let bundleURL = directory.appendingPathComponent("\(name).app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        try FileManager.default.createDirectory(at: macosURL, withIntermediateDirectories: true)

        let exe = executableName ?? name
        if createPlist {
            let plistURL = contentsURL.appendingPathComponent("Info.plist")
            var dict: [String: Any] = [:]
            if !exe.isEmpty {
                dict["CFBundleExecutable"] = exe
            }
            let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try data.write(to: plistURL)
        }

        if createExecutable && !exe.isEmpty {
            let exeURL = macosURL.appendingPathComponent(exe)
            try "#!/bin/sh\nexit 0\n".write(to: exeURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exeURL.path)
        }

        return bundleURL
    }

    func testIsValidBundleWithValidApp() throws {
        let bundleURL = try createFakeBundle(name: "ValidApp", in: tempDir)
        XCTAssertTrue(AppScan.isValidBundle(at: bundleURL.path))
    }

    func testIsValidBundleWithEmptyDirectory() throws {
        let emptyApp = tempDir.appendingPathComponent("Empty.app")
        try FileManager.default.createDirectory(at: emptyApp, withIntermediateDirectories: true)
        XCTAssertFalse(AppScan.isValidBundle(at: emptyApp.path))
    }

    func testIsValidBundleWithoutPlist() throws {
        let bundleURL = try createFakeBundle(name: "NoPlistApp", in: tempDir, createPlist: false)
        XCTAssertFalse(AppScan.isValidBundle(at: bundleURL.path))
    }

    func testIsValidBundleWithoutExecutableInPlist() throws {
        let bundleURL = try createFakeBundle(name: "NoExeInPlistApp", in: tempDir, executableName: "")
        XCTAssertFalse(AppScan.isValidBundle(at: bundleURL.path))
    }

    func testIsValidBundleWithoutExecutableBinary() throws {
        let bundleURL = try createFakeBundle(name: "NoBinaryApp", in: tempDir, createExecutable: false)
        XCTAssertFalse(AppScan.isValidBundle(at: bundleURL.path))
    }

    func testIsValidBundleWithSymlinkToValidApp() throws {
        let realApp = try createFakeBundle(name: "RealApp", in: tempDir)
        let linkApp = tempDir.appendingPathComponent("LinkApp.app")
        try FileManager.default.createSymbolicLink(at: linkApp, withDestinationURL: realApp)
        XCTAssertTrue(AppScan.isValidBundle(at: linkApp.path))
    }

    func testIsValidBundleWithDanglingSymlink() throws {
        let nonExistent = tempDir.appendingPathComponent("Ghost.app")
        let linkApp = tempDir.appendingPathComponent("DanglingLink.app")
        try FileManager.default.createSymbolicLink(at: linkApp, withDestinationURL: nonExistent)
        XCTAssertFalse(AppScan.isValidBundle(at: linkApp.path))
    }

    func testInstallSearchRootsIncludesSystemApplications() {
        XCTAssertTrue(AppScan.installSearchRoots.contains("/System/Applications"))
        XCTAssertTrue(AppScan.installSearchRoots.contains("/Applications"))
    }
}

