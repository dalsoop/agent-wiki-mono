import Foundation
import XCTest
@testable import DoctorKit

/// WindowVisibilityDoctorProvider 판정 로직 5분기.
final class WindowVisibilityProviderTests: XCTestCase {

    private func provider(
        subjects: [String] = ["DemoApp"],
        apps: [WindowVisibilityApp] = [],
        windows: [WindowVisibilityWindow] = [],
        ax: Bool = true,
        lsui: Bool = false
    ) -> WindowVisibilityDoctorProvider {
        WindowVisibilityDoctorProvider(
            subjects: subjects,
            listRunning: { apps },
            listWindows: { windows },
            isAXTrusted: { ax },
            readLSUIElement: { _ in lsui }
        )
    }

    // 1) 프로세스 없음 → fail
    func testNotRunningIsFail() async {
        let findings = await provider(apps: [], ax: true).run()
        XCTAssertEqual(findings.count, 1)
        let f = findings[0]
        XCTAssertEqual(f.severity, .fail)
        XCTAssertEqual(f.category, .runtime)
        XCTAssertEqual(f.title, "실행 안 됨 (크래시 확인)")
        XCTAssertEqual(f.payload["verdict"], "not-running")
        XCTAssertEqual(f.source, "window-visibility")
    }

    // 2) 프로세스 O + LSUIElement=true → ok 메뉴바
    func testMenubarAppIsOkEvenWithoutWindows() async {
        let apps = [WindowVisibilityApp(name: "DemoApp", pid: 42, bundlePath: "/Apps/DemoApp.app")]
        let findings = await provider(apps: apps, windows: [], ax: true, lsui: true).run()
        XCTAssertEqual(findings.count, 1)
        let f = findings[0]
        XCTAssertEqual(f.severity, .ok)
        XCTAssertEqual(f.title, "메뉴바 앱 (창 없는 게 정상)")
        XCTAssertEqual(f.payload["verdict"], "menubar")
        XCTAssertEqual(f.payload["pid"], "42")
    }

    // 3) 프로세스 O + 창 O → ok 정상
    func testProcessWithWindowIsOk() async {
        let apps = [WindowVisibilityApp(name: "DemoApp", pid: 7, bundlePath: "/Apps/DemoApp.app")]
        let windows = [WindowVisibilityWindow(ownerPID: 7, ownerName: "DemoApp", layer: 0)]
        let findings = await provider(apps: apps, windows: windows, ax: false, lsui: false).run()
        XCTAssertEqual(findings.count, 1)
        let f = findings[0]
        XCTAssertEqual(f.severity, .ok)
        XCTAssertEqual(f.title, "정상")
        XCTAssertEqual(f.payload["verdict"], "visible")
        XCTAssertEqual(f.payload["windowCount"], "1")
        // CG 경로라 AX 없어도 ok
        XCTAssertEqual(f.payload["axTrusted"], "false")
    }

    // 4) 프로세스 O + 창 X + AX O → fail 앱 버그
    func testNoWindowWithAXIsFail() async {
        let apps = [WindowVisibilityApp(name: "DemoApp", pid: 99, bundlePath: "/Apps/DemoApp.app")]
        let findings = await provider(apps: apps, windows: [], ax: true, lsui: false).run()
        XCTAssertEqual(findings.count, 1)
        let f = findings[0]
        XCTAssertEqual(f.severity, .fail)
        XCTAssertEqual(f.title, "창이 안 뜬다 — 앱 버그")
        XCTAssertEqual(f.payload["verdict"], "no-window")
        XCTAssertNotNil(f.remedy)
    }

    // 5) 프로세스 O + 창 X + AX X → warn 판정 불가
    func testNoWindowWithoutAXIsWarn() async {
        let apps = [WindowVisibilityApp(name: "DemoApp", pid: 11, bundlePath: "/Apps/DemoApp.app")]
        let findings = await provider(apps: apps, windows: [], ax: false, lsui: false).run()
        XCTAssertEqual(findings.count, 1)
        let f = findings[0]
        XCTAssertEqual(f.severity, .warn)
        XCTAssertEqual(f.title, "판정 불가 — 접근성 권한 필요")
        XCTAssertEqual(f.payload["verdict"], "needs-ax")
        XCTAssertNotNil(f.remedy)
    }

    /// layer > 0 (status item 등) 만 있으면 일반 창 없음으로 본다.
    func testNonZeroLayerWindowsDoNotCount() async {
        let apps = [WindowVisibilityApp(name: "DemoApp", pid: 5, bundlePath: nil)]
        let windows = [WindowVisibilityWindow(ownerPID: 5, ownerName: "DemoApp", layer: 25)]
        let findings = await provider(apps: apps, windows: windows, ax: true, lsui: false).run()
        XCTAssertEqual(findings[0].severity, .fail)
        XCTAssertEqual(findings[0].payload["verdict"], "no-window")
    }

    /// 다른 PID 창은 대상 앱 창으로 치지 않는다.
    func testForeignWindowsDoNotCount() async {
        let apps = [WindowVisibilityApp(name: "DemoApp", pid: 1, bundlePath: nil)]
        let windows = [WindowVisibilityWindow(ownerPID: 2, ownerName: "Other", layer: 0)]
        let findings = await provider(apps: apps, windows: windows, ax: true, lsui: false).run()
        XCTAssertEqual(findings[0].severity, .fail)
    }

    /// 이름 정규화: 공백·하이픈·대소문자 무시.
    func testSubjectMatchingNormalizesName() {
        let app = WindowVisibilityApp(
            name: "App Build Manager",
            pid: 1,
            bundlePath: "/Applications/AppBuildManager.app"
        )
        XCTAssertTrue(WindowVisibilityDoctorProvider.matches(subject: "AppBuildManager", app: app))
        XCTAssertTrue(WindowVisibilityDoctorProvider.matches(subject: "app-build-manager", app: app))
        XCTAssertTrue(WindowVisibilityDoctorProvider.matches(subject: "App Build Manager", app: app))
        XCTAssertFalse(WindowVisibilityDoctorProvider.matches(subject: "Unrelated", app: app))
    }

    func testLSUIElementTruthyParsing() {
        XCTAssertTrue(WindowVisibilityDoctorProvider.isTruthyLSUIElement(true))
        XCTAssertTrue(WindowVisibilityDoctorProvider.isTruthyLSUIElement(NSNumber(value: 1)))
        XCTAssertTrue(WindowVisibilityDoctorProvider.isTruthyLSUIElement("1"))
        XCTAssertTrue(WindowVisibilityDoctorProvider.isTruthyLSUIElement("true"))
        XCTAssertFalse(WindowVisibilityDoctorProvider.isTruthyLSUIElement(false))
        XCTAssertFalse(WindowVisibilityDoctorProvider.isTruthyLSUIElement("0"))
        XCTAssertFalse(WindowVisibilityDoctorProvider.isTruthyLSUIElement(nil as Any?))
    }

    func testEmptySubjectsYieldNoFindings() async {
        let findings = await provider(subjects: []).run()
        XCTAssertTrue(findings.isEmpty)
    }

    func testProviderId() {
        XCTAssertEqual(provider().id, "window-visibility")
    }
}
