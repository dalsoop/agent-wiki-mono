#if os(macOS)
import SwiftUI
#if SelfUpdating
import SparkleUpdateKit
#endif

/// 메뉴바 상주 + **다중 창(WindowGroup)** 앱의 스캐폴드.
///
/// `RanodeMenuBarApp`(단일 Window)과 나뉘는 이유는 창 의미가 다르기 때문이다.
/// 하나로 합치면 사용자가 쓰던 "새 창"이 사라진다(SceneBuilder 가 조건부 scene 을
/// 지원하지 않아 분기로는 못 만든다). 실측 14앱.
///
/// ```swift
/// @main
/// struct SomeApp: RanodeMenuBarWindowGroupApp {
///     static let service = "net.ranode.agent-approval-hook-watch"
///     static let productName = "Agent Approval Hook Watch"
///
///     @State private var vm = ViewModel()
///     var menuContent: some View { RootView(vm: vm).frame(width: 620, height: 420) }
///     var menuLabel: some View { Image(systemName: "antenna.radiowaves.left.and.right") }
///     var root: some View { RootView(vm: vm) }
/// }
/// ```
///
/// ## 왜 별도 프로토콜인가
///
/// 실측(2026-08-04, `apps/*`): MenuBarExtra 앱 **87개** 중 **78개가 메인 창도 함께** 갖는다
/// (스타일은 `.window` 75 · `.menu` 2 · 미지정 10). `SceneBuilder` 가 조건부 scene 을
/// 지원하지 않아 "창이 있는 앱/없는 앱"을 한 프로토콜의 분기로 못 만든다 —
/// 창 없는 9개까지 이걸 쓰면 없던 창이 생긴다. 그래서 다수형(창 있음)을 여기서 다루고,
/// 창 없는 형태는 별도로 둔다.
///
/// ## 라이선스 게이트 위치
///
/// **메인 창 내용에만** 건다. 기존 앱들이 그렇게 하고 있고(메뉴바 팝오버는 게이트 없음),
/// 좁은 팝오버에 활성화 화면을 띄우면 쓸 수 없다. 전환의 목적은 기능 보존이다.
@MainActor
public protocol FleetManagedMenuBarWindowGroupApp: App {
    associatedtype MenuContent: View
    associatedtype MenuLabel: View
    associatedtype Root: View
    associatedtype SettingsBody: View

    /// Keychain/지갑 product service id. 보통 번들 id.
    static var service: String { get }
    /// 창 제목·라이선스 화면에 쓸 제품 이름.
    static var productName: String { get }
    static var windowID: String { get }
    /// 창 제목. 기본은 제품 이름 — 원래 제목이 다르면 반드시 선언한다(실측 사고).
    static var windowTitle: String { get }
    /// nil 이면 제약 없음 — 기본값을 주면 원래 없던 최소 크기가 생긴다(실측 사고).
    static var minSize: CGSize? { get }
    static var defaultSize: CGSize? { get }
    static var windowResizability: WindowResizability { get }
    /// 메뉴바 팝오버 내용.
    @ViewBuilder @MainActor var menuContent: MenuContent { get }
    /// 메뉴바 아이콘·배지. 상태에 따라 바뀌는 앱이 많아 뷰로 받는다.
    @ViewBuilder @MainActor var menuLabel: MenuLabel { get }
    /// 메인 창 내용. 라이선스 게이트가 여기에 걸린다.
    @ViewBuilder @MainActor var root: Root { get }
    /// 설정 창 전체. 기본은 표준 폼.
    @ViewBuilder @MainActor var settingsView: SettingsBody { get }
}

extension FleetManagedMenuBarWindowGroupApp {
    public static var windowID: String { "main" }
    public static var windowTitle: String { productName }
    public static var minSize: CGSize? { nil }
    public static var defaultSize: CGSize? { nil }
    public static var windowResizability: WindowResizability { .contentMinSize }

    // opaque 반환은 앱이 재정의 안 할 때 링커 심볼이 없다(RanodeApp 쪽 주석 참고).
    @MainActor public var settingsView: StandardSettingsForm<EmptyView> {
        StandardSettingsForm(
            language: Binding(
                get: { FleetManagedAppLocalization.shared.language },
                set: { FleetManagedAppLocalization.shared.setLanguage($0) })
        ) { EmptyView() }
    }

    /// 반환 타입을 **구체적으로** 못박는다. `some Scene`(opaque)로 두면 앱이 재정의하지
    /// 않았을 때 모듈 경계에서 opaque 타입 심볼이 안 만들어져 링크가 깨진다
    /// (실측: Undefined symbols … PAAE4bodyQrvpQO — 4개 앱).
    public var body: some Scene {
        scaffoldBody
    }

    @SceneBuilder private var scaffoldBody: some Scene {
        // 스타일이 scene 타입을 바꾸므로 분기 대신 두 스타일을 각각 선언한다
        // (SceneBuilder 는 if/else 를 지원하지 않는다).
        menuBarScene

        WindowGroup(Self.windowTitle, id: Self.windowID) {
            FleetManagedAppShell(
                service: Self.service,
                productName: Self.productName,
                minSize: Self.minSize,
                defaultSize: Self.defaultSize
            ) { root }
        }
        .windowResizability(Self.windowResizability)
        .commands {
            EmptyCommands()
            #if SelfUpdating
            SparkleCommands()
            #endif
        }

        Settings { RanodeSettingsHost.wrap(settingsView) }
    }

    @SceneBuilder private var menuBarScene: some Scene {
        MenuBarExtra {
            RanodeMenuBarPopover(productName: Self.productName) { menuContent }
        } label: {
            menuLabel
        }
        // `.window` 고정. `menuBarExtraStyle` 은 스타일마다 타입이 달라 값으로
        // 못 고른다(제네릭). 실측 87개 중 `.window` 75 · `.menu` 2 이므로
        // 다수를 여기서 다루고 `.menu` 2개는 이 프로토콜을 쓰지 않는다.
        .menuBarExtraStyle(.window)
    }
}

@available(*, deprecated, renamed: "FleetManagedMenuBarWindowGroupApp")
public typealias RanodeMenuBarWindowGroupApp = FleetManagedMenuBarWindowGroupApp

#endif
