#if os(macOS)
import SwiftUI
#if SelfUpdating
import SparkleUpdateKit
#endif

/// 메뉴바만 있는 앱의 스캐폴드 — **메인 Window 를 만들지 않는다.**
///
/// 본문 창이 필요하면 이 프로토콜에 Window 를 얹지 마라. 같은 패키지의
/// `RanodeMenuBarApp` 이 그 형태다(`SceneBuilder` 는 창을 조건으로 못 뺀다).
///
/// Sparkle 수신 SSOT 는 앱마다 버튼을 붙이지 않는다.
/// `Settings` → `RanodeSettingsHost.wrap` + `SparkleCommands` + bootstrap `start()`.
/// 팝오버에서 설정을 열려면 `RanodeSettingsLink.open()` — Window id settings 가 없다.
/// Cloud Apps 게이트도 여기다. Extra 는 메인 창이 없어 `RanodeAppShell` 을 안 탄다.
///
/// 기동 가드는 팝오버 `init` 만 믿으면 안 된다. Extra 내용 뷰는 클릭 전까지
/// 안 만들어지고, 노치에 아이콘이 가려지면 영원히 안 열린다. 그 사이
/// LSUIElement 앱은 창이 없다고 자동 종료된다(실측 ~20–40초). `body` 평가에서
/// bootstrap + `disableAutomaticTermination` 을 먼저 건다.
@MainActor
public protocol FleetManagedMenuBarExtraApp: App {
    associatedtype MenuContent: View
    associatedtype MenuLabel: View
    associatedtype SettingsBody: View

    static var service: String { get }
    static var productName: String { get }
    @ViewBuilder @MainActor var menuContent: MenuContent { get }
    @ViewBuilder @MainActor var menuLabel: MenuLabel { get }
    @ViewBuilder @MainActor var settingsView: SettingsBody { get }
    /// Extra 팝오버는 클릭 전까지 안 만들어진다. 로그인 기동에서 할 일은 여기.
    @MainActor func extraDidBecomeAlive()
}

extension FleetManagedMenuBarExtraApp {
    @MainActor public var settingsView: StandardSettingsForm<EmptyView> {
        StandardSettingsForm(
            language: Binding(
                get: { FleetManagedAppLocalization.shared.language },
                set: { FleetManagedAppLocalization.shared.setLanguage($0) })
        ) { EmptyView() }
    }

    @MainActor public func extraDidBecomeAlive() {}

    public var body: some Scene {
        ExtraKeepAlive.install()
        extraDidBecomeAlive()
        return scaffoldBody
    }

    @SceneBuilder private var scaffoldBody: some Scene {
        MenuBarExtra {
            gatedPopover
        } label: {
            menuLabel
        }
        .menuBarExtraStyle(.window)
        .commands {
            EmptyCommands()
            #if SelfUpdating
            SparkleCommands()
            #endif
        }

        Settings {
            gatedSettings
        }
    }

    /// Extra 앱은 메인 창이 없다. 팝오버가 제품 화면이라 게이트를 여기 둔다.
    /// `RanodeMenuBarApp` 은 창의 `RanodeAppShell` 이 대신 건다.
    @ViewBuilder private var gatedPopover: some View {
        let popover = RanodeMenuBarPopover(productName: Self.productName) { menuContent }
        #if GujoManaged
        popover.gujoManaged()
        #else
        popover
        #endif
    }

    @ViewBuilder private var gatedSettings: some View {
        let settings = RanodeSettingsHost.wrap(settingsView)
        #if GujoManaged
        settings.gujoManaged()
        #else
        settings
        #endif
    }
}

/// Extra 는 Window 가 없다. 팝오버가 아직 없어도 프로세스 수명과 Sparkle 기동을 연다.
enum ExtraKeepAlive {
    @MainActor
    static func install() {
        TenantStateRootEntry.applyIfNeeded()
        FleetManagedAppBootstrap.runOnce()
        ProcessInfo.processInfo.disableAutomaticTermination("RanodeMenuBarExtraApp")
    }
}

@available(*, deprecated, renamed: "FleetManagedMenuBarExtraApp")
public typealias RanodeMenuBarExtraApp = FleetManagedMenuBarExtraApp

#endif
