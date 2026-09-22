import SwiftUI
import Testing

@testable import AppScaffoldKit

/// 스캐폴드가 "채택만 하면 표준을 갖춘다"는 계약.
///
/// 이 함대는 횡단 관심사를 앱마다 복붙해 왔고, 그래서 채택률이 흩어졌다
/// (2026-08-04 실측: dual-entry 200 · 라이선스 175 · 단일인스턴스 145 · About 63).
/// 스캐폴드의 존재 이유가 그 드리프트를 구조적으로 막는 것이므로,
/// **기본값이 비어 있지 않다**는 것 자체가 계약이다.
@MainActor
@Suite struct RanodeAppScaffoldTests {
    private struct SampleApp: RanodeApp {
        static let service = "net.ranode.sample"
        static let productName = "Sample"
        var root: some View { Text("root") }
    }

    @Test func defaultsAreProvided() {
        // 앱이 안 적어도 창 식별자·최소 크기가 정해진다.
        #expect(SampleApp.windowID == "main")
        // 크기 제약은 **기본이 없다**. 기본값을 주면 원래 없던 최소 크기가 생겨
        // 작은 설정 창이 강제로 커진다(2026-08-04 실측 사고 — 감사 에이전트가 잡음).
        #expect(SampleApp.minSize == nil)
        #expect(SampleApp.defaultSize == nil)
        // 창 제목 기본값은 제품명이지만, 원래 제목이 다르면 앱이 선언해야 한다.
        #expect(SampleApp.windowTitle == SampleApp.productName)
    }

    @Test func identityComesFromTheApp() {
        #expect(SampleApp.service == "net.ranode.sample")
        #expect(SampleApp.productName == "Sample")
    }

    /// 설정 업데이트 UI 는 앱이 아니라 스캐폴드 `Settings` 씬이 붙인다.
    @Test func settingsSceneUsesSharedUpdateHost() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AppScaffoldKit")
        let files = [
            "RanodeApp.swift",
            "RanodeWindowGroupApp.swift",
            "RanodeMenuBarApp.swift",
            "RanodeMenuBarWindowGroupApp.swift",
            "RanodeMenuBarExtraApp.swift",
        ]
        for name in files {
            let source = try String(contentsOf: url.appendingPathComponent(name), encoding: .utf8)
            #expect(source.contains("RanodeSettingsHost.wrap(settingsView)"), "\(name) must wrap Settings")
        }
        let host = try String(
            contentsOf: url.appendingPathComponent("RanodeSettingsHost.swift"),
            encoding: .utf8
        )
        #expect(host.contains("withFleetUpdateSettings"))
        let extra = try String(
            contentsOf: url.appendingPathComponent("RanodeMenuBarExtraApp.swift"), encoding: .utf8)
        #expect(extra.contains("SparkleCommands"))
        #expect(extra.contains("RanodeSettingsHost.wrap"))
        #expect(extra.contains("RanodeMenuBarPopover"))
        #expect(extra.contains("gujoManaged()"), "Extra has no window shell — gate lives on the popover")
        #expect(extra.contains("ExtraKeepAlive.install()"), "Extra body must keep-alive before the popover exists")
        #expect(extra.contains("disableAutomaticTermination"), "LSUIElement Extra is auto-terminated without this")
        #expect(extra.contains("FleetManagedAppBootstrap.runOnce()"), "Sparkle start must not wait for a popover click")
        let menuBar = try String(
            contentsOf: url.appendingPathComponent("RanodeMenuBarApp.swift"), encoding: .utf8)
        #expect(menuBar.contains("RanodeMenuBarPopover"))
        #expect(menuBar.contains("RanodeSettingsHost.wrap"))
        let bootstrap = try String(contentsOf: url.appendingPathComponent("RanodeApp.swift"), encoding: .utf8)
        #expect(bootstrap.contains("PermissionBootstrap.isRequested"))
        #expect(bootstrap.contains("skipSingleInstance"))
        #expect(bootstrap.contains("SparkleUpdaterHost.shared.start()"))
        #expect(host.contains("TenantStateRootEntry.applyIfNeeded()"))
        #expect(extra.contains("TenantStateRootEntry.applyIfNeeded()"))
        let entry = try String(
            contentsOf: url.appendingPathComponent("TenantStateRootEntry.swift"), encoding: .utf8)
        #expect(entry.contains("public static func applyIfNeeded()"))
        let gujo = try String(
            contentsOf: url.appendingPathComponent("GujoManaged.swift"), encoding: .utf8)
        #expect(!gujo.contains("TenantStateRootBootstrap.apply()"))
        #expect(!bootstrap.contains("TenantStateRootBootstrap.apply()"))
    }

    /// 기동 가드는 프로세스에 한 번만 돈다. SwiftUI 는 scene body 를 여러 번 평가할 수
    /// 있는데, 가드가 매번 돌면 `exit()` 판정을 반복 수행하게 된다.
    @Test func bootstrapRunsOnlyOnce() {
        RanodeAppBootstrap.runOnce()
        RanodeAppBootstrap.runOnce()  // 두 번째는 아무 일도 없어야 한다(크래시·종료 없음)
    }
}

/// 메뉴바 스캐폴드 계약.
///
/// MenuBarExtra 앱 87개 중 78개가 메인 창도 함께 갖는다(2026-08-04 실측).
/// `SceneBuilder` 가 조건부 scene 을 지원하지 않아 "창 있음/없음"을 한 프로토콜의
/// 분기로 못 만들므로, 다수형(창 있음)만 이 프로토콜이 다룬다.
@MainActor
@Suite struct RanodeMenuBarScaffoldTests {
    private struct SampleMenuBarApp: RanodeMenuBarApp {
        static let service = "net.ranode.sample-menubar"
        static let productName = "Sample MenuBar"
        var menuContent: some View { Text("menu") }
        var menuLabel: some View { Image(systemName: "gear") }
        var root: some View { Text("window") }
    }

    @Test func defaultsAreProvided() {
        #expect(SampleMenuBarApp.windowID == "main")
        #expect(SampleMenuBarApp.minSize == nil)
        #expect(SampleMenuBarApp.defaultSize == nil)
        #expect(SampleMenuBarApp.windowTitle == SampleMenuBarApp.productName)
    }

    @Test func identityComesFromTheApp() {
        #expect(SampleMenuBarApp.service == "net.ranode.sample-menubar")
        #expect(SampleMenuBarApp.productName == "Sample MenuBar")
    }
}
