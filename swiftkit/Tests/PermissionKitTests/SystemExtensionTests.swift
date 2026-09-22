import XCTest
@testable import PermissionKit

final class SystemExtensionTests: XCTestCase {
    let ext = SystemExtension(bundleID: "net.ranode.wireguard.network-extension", displayName: "VPNWireGuard")

    func testWaitingForApproval() {
        let out = "\t*\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1)\tVPNWireGuard\t[activated waiting for user]"
        XCTAssertEqual(ext.status(runner: { _, _ in out }), .waitingForApproval)
    }
    func testEnabled() {
        let out = "\t*\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1)\tVPNWireGuard\t[activated enabled]"
        let s = ext.status(runner: { _, _ in out })
        XCTAssertEqual(s, .enabled); XCTAssertTrue(s.isReady)
    }
    func testNotInstalled() {
        XCTAssertEqual(ext.status(runner: { _, _ in "0 extension(s)\n" }), .notInstalled)
    }

    func testUnprobedIsNotReadyAndNotOnboarding() {
        let s = SystemExtension.ApprovalState.unprobed
        XCTAssertFalse(s.isReady)
        XCTAssertFalse(s.isProbed)
        XCTAssertFalse(s.showsOnboarding)
        XCTAssertTrue(SystemExtension.ApprovalState.notInstalled.showsOnboarding)
        XCTAssertFalse(SystemExtension.ApprovalState.enabled.showsOnboarding)
    }
    func testCopyKorean() {
        let c = ext.copy(language: .korean)
        XCTAssertTrue(c.title.contains("시스템 확장"))
        XCTAssertTrue(c.body.contains("VPNWireGuard"))
    }

    /// 딥링크는 **깊은 화면 먼저** 시도하고, 안 열리면 얕은 화면으로 물러난다.
    /// 하나만 쓰면 macOS 버전에 따라 아무 화면도 안 뜨거나, 목록 없는 상위 화면에 떨어진다.
    func testSettingsCandidatesGoDeepestFirst() {
        let candidates = SystemExtension.settingsURLCandidates
        XCTAssertTrue(candidates.count >= 2, "폴백이 있어야 한다")
        XCTAssertTrue(candidates[0].contains("extensionPointIdentifier"),
                      "첫 후보는 네트워크 확장 목록까지 가야 한다: \(candidates[0])")
        XCTAssertTrue(candidates.last?.contains("preference.security") == true
                      || candidates.last?.contains("LoginItems-Settings") == true,
                      "마지막은 항상 열리는 얕은 화면")
    }

    /// 전부 실패하면 nil 을 돌려 호출측이 수동 경로를 안내할 수 있어야 한다(조용한 실패 금지).
    @MainActor
    func testOpenSettingsReportsFailure() {
        XCTAssertNil(ext.openSettings(open: { _ in false }))
        XCTAssertEqual(ext.openSettings(open: { _ in true }), SystemExtension.settingsURLCandidates.first)
        XCTAssertTrue(ext.manualNavigationHint(language: .korean).contains("네트워크 확장"))
    }

    /// 여러 줄이 쌓인 실제 출력에서 **enabled 줄**을 골라야 한다. 첫 줄(옛 terminated 항목)을
    /// 읽으면 확장이 살아 있는데도 "승인 필요" 온보딩이 떠서 사용자가 아무것도 못 한다(실측 2026-08-10).
    func testStatusPrefersEnabledLineAmongStaleEntries() {
        let out = """
        \t\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1785522053)\tX\t[terminated waiting to uninstall on reboot]
        \t\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1786365447)\tX\t[terminated waiting to uninstall on reboot]
        *\t*\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1786370544)\tX\t[activated enabled]
        """
        XCTAssertEqual(ext.status(runner: { _, _ in out }), .enabled)
    }

    /// 전부 terminated 면 살아 있는 확장이 없다 = 재활성화가 필요하다(미설치와 같게 다룬다).
    func testStatusIsNotInstalledWhenAllEntriesTerminated() {
        let out = "\t\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1)\tX\t[terminated waiting to uninstall on reboot]"
        XCTAssertEqual(ext.status(runner: { _, _ in out }), .notInstalled)
    }

    /// 활성 버전은 **enabled 줄에서만** 읽어야 한다. 재부팅 대기(terminated) 줄을 읽으면
    /// "이미 새 버전이 돈다" 고 오판해, 고쳤는데도 옛 코드가 도는 상태를 못 알린다(실측 2026-08-10).
    func testActivatedVersionReadsOnlyEnabledLine() {
        let out = """
        \t\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1786400000)\tX\t[terminated waiting to uninstall on reboot]
        *\t*\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1786369741)\tX\t[activated enabled]
        """
        XCTAssertEqual(ext.activatedVersion(runner: { _, _ in out }), "1786369741")
    }

    /// 관측은 세 갈래로 갈라진다 — 버전 읽음 / 목록에 없음 / 줄은 있는데 못 읽음.
    /// 마지막 상태를 absent 와 구분하지 않으면 포맷 변화를 "미설치"로 위장한다.
    func testActivatedProbeDistinguishesAbsentFromUnreadable() {
        let enabled = "*\t*\tV2Z46YY386\tnet.ranode.wireguard.network-extension (0.1.0/1786369741)\tX\t[activated enabled]"
        XCTAssertEqual(ext.activatedProbe(runner: { _, _ in enabled }), .version("1786369741"))
        XCTAssertEqual(ext.activatedProbe(runner: { _, _ in "0 extension(s)\n" }), .absent)
        // 괄호가 사라진 포맷 변화 — 토큰 폴백으로 버전을 살린다.
        let parenless = "*\t*\tV2Z46YY386\tnet.ranode.wireguard.network-extension 0.1.0/1786369741\tX\t[activated enabled]"
        XCTAssertEqual(ext.activatedProbe(runner: { _, _ in parenless }), .version("1786369741"))
        // 빌드 번호 자체가 없으면 unreadable — 조용한 nil 이 아니라 사실을 말한다.
        let alien = "*\t*\tV2Z46YY386\tnet.ranode.wireguard.network-extension\tX\t[activated enabled]"
        XCTAssertEqual(ext.activatedProbe(runner: { _, _ in alien }), .unreadable)
        XCTAssertNil(ext.activatedVersion(runner: { _, _ in alien }))
    }

    func testReplacementPendingWhenBundledDiffersFromActivated() {
        XCTAssertTrue(SystemExtension.VersionState(bundled: "2", activated: "1").replacementPending)
        XCTAssertFalse(SystemExtension.VersionState(bundled: "1", activated: "1").replacementPending)
        // 한쪽을 못 읽으면 판단하지 않는다 — 근거 없는 경고는 노이즈다.
        XCTAssertFalse(SystemExtension.VersionState(bundled: nil, activated: "1").replacementPending)
        XCTAssertFalse(SystemExtension.VersionState(bundled: "2", activated: nil).replacementPending)
    }

    func testBundledVersionReadsExtensionInfoPlist() throws {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("SX-\(UUID().uuidString).app")
        let plistPath = app
            .appendingPathComponent("Contents/Library/SystemExtensions/net.ranode.wireguard.network-extension.systemextension/Contents/Info.plist")
        try FileManager.default.createDirectory(at: plistPath.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleVersion": "1786400000"], format: .xml, options: 0)
        try data.write(to: plistPath)
        XCTAssertEqual(ext.bundledVersion(appBundlePath: app.path), "1786400000")
        XCTAssertNil(ext.bundledVersion(appBundlePath: "/nope"))
    }

    /// 온보딩 단계·토글 미리보기 라벨은 공용 copy 가 정본이다(앱이 하드코딩하지 않게).
    func testCopyCarriesStepsAndMockRow() {
        let c = ext.copy(language: .korean)
        XCTAssertEqual(c.steps.count, 3)
        XCTAssertTrue(c.steps[1].contains("VPNWireGuard"))
        XCTAssertEqual(c.mockRowLabel, "VPNWireGuard")
        XCTAssertEqual(ext.copy(language: .english).steps.count, 3)
    }
}

/// 딥링크 후보 순서·폴백 — 백로그 800CD2C1("한 단 부족").
final class SystemExtensionSettingsReachTests: XCTestCase {
    private let ext = SystemExtension(bundleID: "net.example.ext", displayName: "예시")

    /// 첫 후보가 가장 깊다 — 네트워크 확장 목록까지 바로 간다.
    func testFirstCandidateTargetsNetworkExtensions() {
        let first = SystemExtension.settingsURLCandidates[0]
        XCTAssertTrue(first.contains("extensionPointIdentifier=com.apple.system_extension.network_extension"), first)
    }

    /// 마지막 후보는 반드시 열리는 얕은 화면 — 아무 화면도 안 뜨는 회귀 방지.
    func testLastCandidateIsAShallowFallback() {
        XCTAssertFalse(SystemExtension.settingsURLCandidates.last!.contains("extensionPointIdentifier"))
    }

    func testAllCandidatesAreValidURLs() {
        for candidate in SystemExtension.settingsURLCandidates {
            XCTAssertNotNil(URL(string: candidate), candidate)
        }
    }

    /// 앞 후보가 실패하면 다음으로 물러난다.
    @MainActor func testFallsBackToNextCandidateWhenOpenFails() {
        var attempted: [String] = []
        let opened = ext.openSettings { url in
            attempted.append(url.absoluteString)
            return attempted.count == 2   // 두 번째만 성공
        }
        XCTAssertEqual(opened, SystemExtension.settingsURLCandidates[1])
        XCTAssertEqual(attempted.count, 2)
    }

    /// 전부 실패하면 nil — 호출측이 폴백 안내를 띄울 수 있어야 한다(조용한 실패 금지).
    @MainActor func testReturnsNilWhenNothingOpens() {
        XCTAssertNil(ext.openSettings { _ in false })
    }

    func testManualHintNamesTheExactSettingsPath() {
        let korean = ext.manualNavigationHint(language: .korean)
        XCTAssertTrue(korean.contains("네트워크 확장"), korean)
        XCTAssertTrue(korean.contains("예시"), korean)
        XCTAssertTrue(ext.manualNavigationHint(language: .english).contains("Network Extensions"))
    }
}

/// 안내 문구 단일화 — 백로그 45873825(앱 안에 같은 안내가 3벌).
final class SystemExtensionCopyStepsTests: XCTestCase {
    private let ext = SystemExtension(bundleID: "net.example.ext", displayName: "VPNWireGuard")

    /// 3단계가 비어 있으면 배너 한 줄만 남아 "어디서 무엇을 켜나"에 답이 안 된다.
    func testKoreanStepsNameTheExactPlaceAndAuth() {
        let steps = ext.copy(language: .korean).steps
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps.contains { $0.contains("네트워크 확장") }, "\(steps)")
        XCTAssertTrue(steps.contains { $0.contains("Touch ID") }, "\(steps)")
    }

    func testEnglishStepsMirrorKorean() {
        let steps = ext.copy(language: .english).steps
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps.contains { $0.contains("Network Extensions") }, "\(steps)")
        XCTAssertTrue(steps.contains { $0.contains("Touch ID") }, "\(steps)")
    }

    /// 앱 이름이 문구에 박혀야 사용자가 목록에서 뭘 찾는지 안다.
    func testStepsNameTheApp() {
        XCTAssertTrue(ext.copy(language: .korean).steps.contains { $0.contains("VPNWireGuard") })
        XCTAssertTrue(ext.copy(language: .english).steps.contains { $0.contains("VPNWireGuard") })
    }
}
