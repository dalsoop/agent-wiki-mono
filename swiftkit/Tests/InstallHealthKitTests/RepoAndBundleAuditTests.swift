import Testing
@testable import InstallHealthKit

private let shimScript = """
#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
exec "$HERE/../../../scripts/install-macos-app.sh" "$HERE/.." "$@"
"""

private func legacyScript(name: String) -> String {
    """
    #!/bin/bash
    DEST_ROOT="${FOO_INSTALL_ROOT:-/Applications}"
    DEST="$DEST_ROOT/\(name).app"
    cp -R ".build/\(name).app" "$DEST"
    """
}

@Suite struct RepoAuditTests {
    private let audit = RepoAudit()

    @Test func flagsHardcodedNameDivergence() {
        let app = RepoApp(directory: "apps/foo-swift", bundleName: "Foo Bar",
                          installScript: legacyScript(name: "FooBar"), makeScript: nil)
        let issues = audit.audit(app)
        #expect(issues.map(\.kind) == [.installScriptDivergence])
        #expect(issues[0].detail.contains("FooBar"))
        #expect(issues[0].detail.contains("Foo Bar"))
    }

    @Test func legacyScriptMatchingCanonicalNameIsClean() {
        let app = RepoApp(directory: "apps/foo-swift", bundleName: "FooBar",
                          installScript: legacyScript(name: "FooBar"), makeScript: nil)
        #expect(audit.audit(app).isEmpty)
    }

    /// shim 은 이름을 Info.plist 에서 뽑으므로 불일치가 원천적으로 없다.
    @Test func shimNeverDiverges() {
        let app = RepoApp(directory: "apps/foo-swift", bundleName: "Totally Different",
                          installScript: shimScript, makeScript: nil)
        #expect(audit.audit(app).isEmpty)
    }

    /// 확장을 심는 앱이 shim 이면 확장이 조용히 빠진다 — 이번 사고(UsbIsoBurner Helper 누락)의 회귀 방지.
    @Test func flagsShimOnExtensionBearingApp() {
        let make = """
        swift build -c "$CONFIG" --product DiagramQuickLook
        APPEX="$APP/Contents/PlugIns/DiagramQuickLook.appex"
        """
        let app = RepoApp(directory: "apps/excalidraw-swift", bundleName: "ExcalidrawSwift",
                          installScript: shimScript, makeScript: make)
        #expect(audit.audit(app).map(\.kind) == [.shimDropsExtension])
    }

    @Test func customScriptOnExtensionBearingAppIsClean() {
        let make = "HELPER=\"$APP/Contents/Library/LaunchServices/FooHelper\""
        let app = RepoApp(directory: "apps/foo-swift", bundleName: "Foo",
                          installScript: legacyScript(name: "Foo"), makeScript: make)
        #expect(audit.audit(app).isEmpty)
    }

    @Test func detectsExtensionMarkers() {
        #expect(RepoAudit.buildsExtensions("cp x $APP/Contents/PlugIns/Y.appex"))
        #expect(RepoAudit.buildsExtensions("HELPER=$APP/Contents/Library/LaunchServices/H"))
        #expect(!RepoAudit.buildsExtensions("cp Packaging/AppIcon.icns $APP/Contents/Resources/"))
    }

    @Test func noInstallScriptIsClean() {
        #expect(audit.audit(RepoApp(directory: "apps/x", bundleName: "X", installScript: nil, makeScript: nil)).isEmpty)
    }
}

@Suite struct BundleAuditTests {
    private let audit = BundleAudit()

    @Test func flagsDuplicateBundleIDs() {
        let bundles = [
            InstalledBundle(path: "/Applications/Foo.app", bundleID: "net.x.foo", name: "Foo"),
            InstalledBundle(path: "/Applications/FooApp.app", bundleID: "net.x.foo", name: "FooApp"),
        ]
        let issues = audit.auditDuplicateBundleIDs(bundles)
        #expect(issues.map(\.kind) == [.duplicateBundleID])
        #expect(issues[0].detail.contains("Foo.app"))
    }

    @Test func distinctBundleIDsAreClean() {
        let bundles = [
            InstalledBundle(path: "/Applications/Foo.app", bundleID: "net.x.foo", name: "Foo"),
            InstalledBundle(path: "/Applications/Bar.app", bundleID: "net.x.bar", name: "Bar"),
        ]
        #expect(audit.auditDuplicateBundleIDs(bundles).isEmpty)
    }

    @Test func flagsDuplicateInstances() {
        let b = [InstalledBundle(path: "/Applications/Foo.app", bundleID: "net.x.foo", name: "Foo", runningInstances: 2)]
        #expect(audit.auditDuplicateInstances(b).map(\.kind) == [.duplicateInstance])
    }

    /// EnvVault 처럼 같은 바이너리가 MCP stdio 서버로 스폰되는 앱은 다중 인스턴스가 정상.
    @Test func multiInstanceByDesignIsExempt() {
        let b = [InstalledBundle(path: "/Applications/EnvVault.app", bundleID: "net.ranode.envvault", name: "EnvVault", runningInstances: 3)]
        #expect(audit.auditDuplicateInstances(b, multiInstanceByDesign: ["net.ranode.envvault"]).isEmpty)
    }

    @Test func flagsMissingExtension() {
        let b = [InstalledBundle(path: "/Applications/Usb.app", bundleID: "net.x.usb", name: "Usb", embeddedExtensions: [])]
        let want = [ExtensionExpectation(bundleID: "net.x.usb", requiredNames: ["UsbIsoBurnerHelper"])]
        let issues = audit.auditMissingExtensions(b, expectations: want)
        #expect(issues.map(\.kind) == [.missingExtension])
        #expect(issues[0].detail.contains("UsbIsoBurnerHelper"))
    }

    @Test func presentExtensionIsClean() {
        let b = [InstalledBundle(path: "/Applications/E.app", bundleID: "net.x.e", name: "E",
                                 embeddedExtensions: ["/Applications/E.app/Contents/PlugIns/Q.appex"])]
        let want = [ExtensionExpectation(bundleID: "net.x.e", requiredNames: ["Q.appex"])]
        #expect(audit.auditMissingExtensions(b, expectations: want).isEmpty)
    }
}

@Suite struct ShimDetectionTests {
    /// 커스텀 스크립트가 "공용 install-macos-app.sh 로 위임하지 않는다" 고 주석에 적는 건 정상 —
    /// 이걸 shim 으로 오인하면 확장 보유 앱이 매번 오탐으로 뜬다(실측 오탐의 회귀 방지).
    @Test func commentMentionIsNotShim() {
        let custom = """
        #!/bin/bash
        # QuickLook .appex 를 심어야 해서 공용 install-macos-app.sh 로 위임하지 않는다.
        DEST="$DEST_ROOT/Foo.app"
        ./scripts/make-app.sh "$CONFIG"
        """
        #expect(!RepoAudit.isShim(custom))
    }

    @Test func execLineIsShim() {
        #expect(RepoAudit.isShim("exec \"$HERE/../../../scripts/install-macos-app.sh\" \"$HERE/..\" \"$@\""))
    }

    @Test func trailingCommentOnCodeLineStillCounts() {
        #expect(RepoAudit.isShim("exec ../../scripts/install-macos-app.sh \"$@\"   # 공용 위임"))
    }
}


/// 이름만 내보내면 **같은 이름의 남의 앱과 구분되지 않는다.**
///
/// 실측(2026-08-05): `net.ranode.wireguard` 중복 경고가 "VPNWireGuard.app, WireGuard.app"
/// 으로 떴는데 `/Applications/WireGuard.app` 은 공식 WireGuard(`com.wireguard.macos`)였고,
/// 우리 것은 `~/Applications/swift-app-mono-icons/WireGuard.app` 이었다.
/// 이름만 보고 지웠으면 남의 앱을 날린다.
@Suite("중복 번들 경고는 경로를 밝힌다")
struct DuplicateBundlePathTests {
    @Test("경고 본문에 전체 경로가 들어간다")
    func detailCarriesPaths() throws {
        let bundles = [
            InstalledBundle(path: "/Applications/VPNWireGuard.app",
                            bundleID: "net.ranode.wireguard", name: "VPNWireGuard"),
            InstalledBundle(path: "/Users/x/Applications/icons/WireGuard.app",
                            bundleID: "net.ranode.wireguard", name: "WireGuard"),
        ]
        let issue = try #require(BundleAudit().auditDuplicateBundleIDs(bundles).first)
        #expect(issue.detail.contains("/Applications/VPNWireGuard.app"))
        #expect(issue.detail.contains("/Users/x/Applications/icons/WireGuard.app"))
        // 어느 쪽이 정본인지 기계가 못 정한다 — 자동 수리 금지.
        #expect(!issue.isAutoFixable)
    }
}

@Suite struct LaunchProbeAuditTests {
    private let audit = LaunchProbeAudit()

    private func probe(
        bundleID: String = "net.test.app",
        name: String = "App",
        skipped: Bool = false,
        exitedEarly: Bool = true,
        exitCode: Int32? = 1,
        stderr: String = ""
    ) -> LaunchProbe {
        LaunchProbe(bundleID: bundleID, name: name, path: "/Applications/App.app",
                    skipped: skipped, exitedEarly: exitedEarly, exitCode: exitCode, stderr: stderr)
    }

    @Test func flagsMissingResourceBundle() {
        let stderr = """
        KeyboardShortcuts/resource_bundle_accessor.swift:12: Fatal error: could not load resource bundle: \
        from /Applications/App.app/Foo_Foo.bundle or /tmp/Foo_Foo.bundle
        """
        let issues = audit.audit([probe(stderr: stderr)])
        #expect(issues.map(\.kind) == [.fatalLaunchCrash])
        #expect(issues[0].detail.contains("Foo_Foo.bundle"))
    }

    @Test func flagsMissingFramework() {
        let stderr = """
        dyld[123]: Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
          Referenced from: /Applications/App.app/Contents/MacOS/App
        """
        let issues = audit.audit([probe(stderr: stderr)])
        #expect(issues.count == 1)
        #expect(issues[0].detail.contains("Sparkle.framework"))
    }

    /// rc=0 으로 조용히 일찍 끝난 건(단일 인스턴스 가드 등) 크래시가 아니다 — 거짓 양성 금지.
    @Test func ignoresGracefulEarlyExit() {
        #expect(audit.audit([probe(exitCode: 0, stderr: "")]).isEmpty)
        #expect(audit.audit([probe(skipped: true)]).isEmpty)
        #expect(audit.audit([probe(exitedEarly: false, exitCode: nil)]).isEmpty)
    }

    /// 매칭되는 패턴 없이 exit≠0 만 있으면 잡음으로 무시(알려진 치명 패턴만 신뢰).
    @Test func ignoresUnknownNonZeroExit() {
        #expect(audit.audit([probe(exitCode: 1, stderr: "some random log")]).isEmpty)
    }
}
