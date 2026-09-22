#if os(macOS)
import SwiftUI
#if SelfUpdating
import SparkleUpdateKit
#endif

/// `WindowGroup` 을 쓰는 앱(창을 여러 개 열 수 있는 형태)의 스캐폴드.
///
/// ## 왜 `RanodeApp` 과 나뉘나
///
/// `Window` 는 단일 창, `WindowGroup` 은 다중 창으로 **의미가 다르다**. 전환하면서
/// 조용히 바꾸면 사용자가 쓰던 "새 창" 이 사라진다. `SceneBuilder` 가 조건부 scene 을
/// 지원하지 않아 한 프로토콜의 분기로는 못 만들므로, 형태별로 프로토콜을 나눈다.
/// 실측(2026-08-04): `WindowGroup` 단일 씬 앱 52개.
@MainActor
public protocol FleetManagedWindowGroupApp: App {
    associatedtype Root: View
    associatedtype SettingsBody: View
    associatedtype MenuCommands: Commands

    static var service: String { get }
    static var productName: String { get }
    static var windowID: String { get }
    /// 창 제목. 기본은 제품 이름 — 원래 제목이 다르면 반드시 선언한다(실측 사고).
    static var windowTitle: String { get }
    /// nil 이면 제약 없음 — 기본값을 주면 원래 없던 최소 크기가 생긴다(실측 사고).
    static var minSize: CGSize? { get }
    static var defaultSize: CGSize? { get }
    static var windowResizability: WindowResizability { get }

    @ViewBuilder @MainActor var root: Root { get }
    @ViewBuilder @MainActor var settingsView: SettingsBody { get }
    @CommandsBuilder @MainActor var appCommands: MenuCommands { get }
}

extension FleetManagedWindowGroupApp {
    public static var windowID: String { "main" }
    public static var windowTitle: String { productName }
    public static var minSize: CGSize? { nil }
    public static var defaultSize: CGSize? { nil }
    public static var windowResizability: WindowResizability { .contentMinSize }

    public var appCommands: some Commands { EmptyCommands() }

    /// 반환 타입을 구체적으로 둔다 — opaque 로 두면 앱이 재정의하지 않았을 때
    /// 모듈 경계에서 링커 심볼이 없다(RanodeApp 쪽 주석 참고).
    @MainActor public var settingsView: StandardSettingsForm<EmptyView> {
        StandardSettingsForm(
            language: Binding(
                get: { FleetManagedAppLocalization.shared.language },
                set: { FleetManagedAppLocalization.shared.setLanguage($0) })
        ) { EmptyView() }
    }

    @SceneBuilder public var body: some Scene {
        WindowGroup(Self.windowTitle, id: Self.windowID) {
            FleetManagedAppShell(
                service: Self.service,
                productName: Self.productName,
                minSize: Self.minSize,
                defaultSize: Self.defaultSize,
                autosaveName: Self.windowID
            ) { root }
        }
        .windowResizability(Self.windowResizability)
        .commands {
            appCommands
            #if SelfUpdating
            SparkleCommands()
            #endif
        }

        Settings { RanodeSettingsHost.wrap(settingsView) }
    }
}

@available(*, deprecated, renamed: "FleetManagedWindowGroupApp")
public typealias RanodeWindowGroupApp = FleetManagedWindowGroupApp

#endif
