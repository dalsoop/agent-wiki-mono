#if os(macOS)
#if canImport(AppKit)
import AppKit
#endif
import DualEntryKit
import LocalizationKit
import StateMirrorKit
#if canImport(PermissionKit)
import PermissionKit
#endif
#if SelfUpdating
import SparkleUpdateKit
#endif
#if Telemetry
import TelemetryKit
#endif
// 앱이 기본 설정 폼(`StandardSettingsForm`)을 직접 쓰므로 재수출한다 —
// 스캐폴드를 채택하면 kit import 를 앱이 따로 챙기지 않아도 되게.
@_exported import SettingsUIKit
// 앱이 창 재열기 델리게이트(`WindowReopenDelegate`)를 쓰므로 재수출한다 —
// 스캐폴드를 채택하면 kit import 를 앱이 따로 챙기지 않아도 되게.
@_exported import SingleInstanceKit
import SwiftUI

/// 이 함대의 macOS 앱이 공통으로 갖춰야 하는 것을 **한 곳에** 모은 스캐폴드.
///
/// ```swift
/// @main
/// struct AgentAppRegistryApp: FleetManagedApp {
///     static let service = "net.ranode.agent-app-registry"
///     static let productName = "Agent App Registry"
///
///     @State private var model = RegistryModel()
///     var root: some View { ContentView(model: model) }
/// }
/// ```
///
/// ## 왜 필요한가
///
/// 횡단 관심사가 앱마다 복붙이라 채택률이 제각각으로 흩어졌다 (2026-08-04 실측, `apps/*` 249개):
///
/// | 관심사 | 채택 |
/// |---|---|
/// | dual-entry 오용 가드 | 200 |
/// | 라이선스 게이트 | 175 |
/// | 단일 인스턴스 가드 | 145 |
/// | About 설정 화면 | 63 |
///
/// "아직 안 했다"가 아니라 **구조가 드리프트를 만든다**. 새 관심사가 생길 때마다
/// 249번 붙여야 하고, 그때마다 몇 개는 빠진다. 스캐폴드는 그 반복을 끝낸다 —
/// 다음 횡단 관심사는 이 파일 한 곳만 고치면 전 앱에 적용된다.
///
/// ## 게이트는 설정이 정한다
///
/// 게이트는 `GujoManaged` trait 이 켜진 빌드에서만 활성화된다.
/// **의존성은 전 앱 통일, 판매 여부는 Info.plist 가 정한다.**
@MainActor
public protocol FleetManagedApp: App {
    associatedtype Root: View

    /// Keychain/지갑 product service id. 보통 번들 id (`net.ranode.myapp`).
    static var service: String { get }
    /// 라이선스 화면에 쓸 **제품 이름**. 창 제목이 아니다.
    static var productName: String { get }
    /// 창 제목. 기본은 제품 이름이지만 **원래 제목이 다르면 반드시 선언한다** —
    /// 실측 사고: 한글 제목("승인 훅 배달 감시")이 영문 제품명으로 바뀌고,
    /// 레포 슬러그("fdroid-repository-manager-swift")가 창 제목에 노출됐다.
    static var windowTitle: String { get }
    /// 주 창 식별자. 기본 `"main"`.
    static var windowID: String { get }
    /// 주 창 최소 크기. **nil 이면 제약을 걸지 않는다** —
    /// 기본값을 주면 원래 없던 최소 크기가 생겨 작은 설정 창이 커진다(실측 사고).
    static var minSize: CGSize? { get }
    /// 주 창 기본 크기. nil 이면 SwiftUI 가 내용 크기로 정한다.
    /// scene `.defaultSize` 는 조건부로 못 걸어서 **content 의 idealSize** 로 표현한다.
    static var defaultSize: CGSize? { get }
    /// 창 크기 조절 정책.
    static var windowResizability: WindowResizability { get }

    /// 앱의 내용. 스캐폴드가 가드·게이트로 감싼다.
    @ViewBuilder @MainActor var root: Root { get }

    /// 설정 창의 앱 전용 **`Section` 들**. 표준 폼(버전·언어·로그인시실행) 안에 들어간다.
    associatedtype SettingsSections: View
    @ViewBuilder @MainActor var settingsSections: SettingsSections { get }

    /// 설정 창 **전체**. 앱이 이미 자체 `Form` 을 가진 `SettingsView` 를 쓰면 이걸 재정의한다 —
    /// 표준 폼 안에 넣으면 Form 이 중첩돼 레이아웃이 깨진다
    /// (실측 2026-08-04: `SettingsView.swift` 123개 중 **56개**가 자체 Form 보유).
    /// 기본 구현은 표준 폼 + `settingsSections`.
    associatedtype SettingsBody: View
    @ViewBuilder @MainActor var settingsView: SettingsBody { get }

    /// 앱 메뉴 커맨드. 기본 없음.
    associatedtype MenuCommands: Commands
    @CommandsBuilder @MainActor var appCommands: MenuCommands { get }

    /// 상태 미러 스냅샷. 주면 스캐폴드가 주기 발행을 돌린다.
    ///
    /// 이것만은 스캐폴드가 대신 만들 수 없다 — 무엇을 미러링할지는 앱의 모델이 안다.
    /// 그래서 기본 nil 인 **선택 훅**이다(기본값을 억지로 만들면 빈 스냅샷이 발행된다).
    @MainActor var stateMirrorSnapshot: (() -> Any?)? { get }
}

extension FleetManagedApp {
    public static var windowID: String { "main" }
    public static var windowTitle: String { productName }
    public static var minSize: CGSize? { nil }
    public static var defaultSize: CGSize? { nil }
    public static var windowResizability: WindowResizability { .contentMinSize }

    public var appCommands: some Commands { EmptyCommands() }

    public var stateMirrorSnapshot: (() -> Any?)? { nil }

    /// 앱 전용 설정 섹션이 없으면 표준 항목만 보여준다.
    /// `StandardAboutSettingsView` 를 앱마다 따로 정의하던 복붙(2026-08-04 기준 63곳)을 대체한다.
    @MainActor public var settingsSections: EmptyView { EmptyView() }

    // 반환 타입을 구체적으로 둔다. opaque(`some View`)로 두면 앱이 재정의하지 않았을 때
    // 연관 타입이 모듈 경계에서 해소되지 않아 **링커 심볼이 없다**
    // (실측: sound-source-inspector 가 Undefined symbols 로 링크 실패).
    @MainActor public var settingsView: StandardSettingsForm<SettingsSections> {
        // 언어 피커도 스캐폴드가 준다 — 앱마다 복붙하던 것(2026-08-04 기준 119/249).
        StandardSettingsForm(
            language: Binding(
                get: { FleetManagedAppLocalization.shared.language },
                set: { FleetManagedAppLocalization.shared.setLanguage($0) })
        ) { settingsSections }
    }

    /// 주 창의 뼈대. `defaultSize` 분기는 아래에서 한다 —
    /// result builder 안에서는 `let` + 분기를 같이 못 쓴다.
    private var baseWindow: some Scene {
        Window(Self.windowTitle, id: Self.windowID) {
            FleetManagedAppShell(
                service: Self.service,
                productName: Self.productName,
                minSize: Self.minSize,
                defaultSize: Self.defaultSize,
                autosaveName: Self.windowID,
                stateMirrorSnapshot: stateMirrorSnapshot
            ) { root }
        }
        .windowResizability(Self.windowResizability)
        .commands {
            appCommands
            #if SelfUpdating
            SparkleCommands()
            #endif
        }
    }

    @SceneBuilder public var body: some Scene {
        baseWindow

        Settings { RanodeSettingsHost.wrap(settingsView) }
    }
}

/// 스캐폴드의 실체. 가드는 창이 뜨기 전에 한 번만 돈다.
/// 메뉴바 스캐폴드도 같은 껍데기를 쓰므로 internal 이다.
@MainActor
struct FleetManagedAppShell<Content: View>: View {
    private let service: String
    private let productName: String
    private let minSize: CGSize?
    private let defaultSize: CGSize?
    private let autosaveName: String?
    private let content: Content
    private let stateMirrorSnapshot: (() -> Any?)?

    init(
        service: String, productName: String, minSize: CGSize?,
        defaultSize: CGSize? = nil,
        autosaveName: String? = nil,
        stateMirrorSnapshot: (() -> Any?)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.service = service
        self.productName = productName
        self.minSize = minSize
        self.defaultSize = defaultSize
        self.autosaveName = autosaveName
        self.stateMirrorSnapshot = stateMirrorSnapshot
        self.content = content()
        FleetManagedAppBootstrap.runOnce()
        #if canImport(PermissionKit)
        _ = PermissionBootstrap.runIfRequested(appName: productName)
        #endif
    }

    var body: some View {
        #if canImport(PermissionKit)
        if PermissionBootstrap.isRequested {
            Color.clear.frame(width: 1, height: 1)
        } else {
            managed
                .task {
                    if let stateMirrorSnapshot {
                        FleetManagedAppBootstrap.startStateMirror(
                            app: productName, snapshot: stateMirrorSnapshot)
                    }
                }
        }
        #else
        managed
            .task {
                if let stateMirrorSnapshot {
                    FleetManagedAppBootstrap.startStateMirror(
                        app: productName, snapshot: stateMirrorSnapshot)
                }
            }
        #endif
    }

    /// 스캐폴드를 쓰는 앱은 **여기서** 게이트를 받는다 — 앱마다 한 줄을 붙이지 않는다.
    ///
    /// 예전엔 `.task` 안에서 판정하고 `handOff` 만 했다. 그건 구버전 `adopt()` 의
    /// fire-and-forget 동작이라 **넘기기만 하고 화면은 그대로 보여줬다** — 즉 게이트가
    /// 아니었다. 실측(2026-08-05): 이 스캐폴드를 쓰는 앱 40개가 trait 를 켠 채로
    /// 판정을 안 받고 있었고, 컴파일이 안 깨져 아무도 몰랐다.
    ///
    /// `.gujoManaged()` 로 바꾸면 그 40개와 **앞으로 스캐폴드를 채택하는 모든 앱**이
    /// 한 곳에서 닫힌다. 앱마다 붙이면 그게 곧 249개 복제다.
    @ViewBuilder private var managed: some View {
        #if GujoManaged
        gated.gujoManaged()
        #else
        gated
        #endif
    }

    /// 자동 업데이트는 `SelfUpdating` trait 를 켠 빌드에만 들어간다.
    /// 끄면 SparkleUpdateKit 이 아예 빌드되지 않는다(실측: 모듈 0 · 심볼 0).
    @ViewBuilder private var gated: some View {
        #if SelfUpdating
        framedContent.sparkleUpdates()
        #else
        framedContent
        #endif
    }

    /// 선언된 제약만 건다. 기본값을 주면 원래 없던 크기 제약이 생긴다(실측 사고).
    private var framedContent: some View {
        content
            .frame(
                minWidth: minSize?.width, idealWidth: defaultSize?.width,
                minHeight: minSize?.height, idealHeight: defaultSize?.height)
            .background(shellWindowBackground)
    }

    @ViewBuilder private var shellWindowBackground: some View {
        #if canImport(AppKit)
        FleetManagedShellWindowConfigurator(
            minSize: minSize,
            defaultSize: defaultSize,
            autosaveName: autosaveName
        )
        #endif
    }
}

#if canImport(AppKit)
/// WindowGroup autosave 가 0×0 을 복원해도 `contentMinSize` 와 default 프레임이 이긴다.
private final class FleetManagedShellWindowAccess: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var handled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !handled, let window else { return }
        handled = true
        onWindow?(window)
    }
}

private struct FleetManagedShellWindowConfigurator: NSViewRepresentable {
    var minSize: CGSize?
    var defaultSize: CGSize?
    var autosaveName: String?

    func makeNSView(context: Context) -> NSView {
        let view = FleetManagedShellWindowAccess()
        view.onWindow = { window in
            Task { @MainActor in
                configure(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func configure(_ window: NSWindow) {
        if let floor = minSize ?? defaultSize {
            window.contentMinSize = NSSize(width: floor.width, height: floor.height)
        }
        applyDefaultIfCollapsed(window)
    }

    private func applyDefaultIfCollapsed(_ window: NSWindow) {
        guard let defaultSize, defaultSize.width > 100, defaultSize.height > 100 else { return }
        guard !shouldKeepAutosavedFrame(window) else { return }
        var frame = window.frame
        frame.size = NSSize(width: defaultSize.width, height: defaultSize.height)
        frame.origin = centeredOrigin(for: frame.size, window: window)
        window.setFrame(frame, display: true)
    }

    private func shouldKeepAutosavedFrame(_ window: NSWindow) -> Bool {
        guard let autosaveName, !autosaveName.isEmpty else { return false }
        guard window.setFrameUsingName(autosaveName) else { return false }
        return window.frame.width >= 200
    }

    private func centeredOrigin(for size: NSSize, window: NSWindow) -> NSPoint {
        guard let visible = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return window.frame.origin
        }
        return NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
    }
}
#endif

/// 앱 언어 정본. 앱마다 `LocalizationManager` 를 따로 만들던 것을 한 곳으로.
@MainActor
public enum FleetManagedAppLocalization {
    public static let shared = LocalizationManager(baseBundle: .main)
}

/// 프로세스에 한 번만 도는 기동 가드.
///
/// 두 가드 모두 조건에 걸리면 `exit()` 한다 — 그래서 창을 그리기 전에 돌아야 하고,
/// 두 번 돌 이유가 없다(SwiftUI 는 scene body 를 여러 번 평가할 수 있다).
@MainActor
public enum FleetManagedAppBootstrap {
    private static var didRun = false

    /// 앱이 기동 때 추가로 해야 하는 일. 가드 **뒤에** 한 번 돈다.
    ///
    /// 실측(2026-08-04, 미전환 앱의 커스텀 `init()` 잔여 로직): `setActivationPolicy` 14 ·
    /// `activate(ignoringOtherApps:)` 12 · `CLI.runIfInvoked` 12 · `PermissionBootstrap` 14.
    /// 이 반복이 앱마다 손으로 복붙돼 있어 70개가 전환에 막혀 있었다.
    nonisolated(unsafe) public static var extraBootstrap: (@MainActor () -> Void)?

    /// 다중 인스턴스가 설계인 앱(DAL 등)은 `App.init` 에서 true 로 둔다.
    /// 기본은 단일 인스턴스. 권한 등록 전용 실행은 이것과 별개로 항상 가드를 건너뛴다.
    nonisolated(unsafe) public static var skipSingleInstance = false

    public static func runOnce() {
        guard !didRun else { return }
        didRun = true
        DualEntryRules.exitIfMisusedFromIdentity()
        #if canImport(PermissionKit)
        let skipInstance = skipSingleInstance || PermissionBootstrap.isRequested
        #else
        let skipInstance = skipSingleInstance
        #endif
        if !skipInstance {
            SingleInstance.exitIfAlreadyRunning()
        }
        extraBootstrap?()
        applyFleetDeskPolicy()
        #if SelfUpdating
        // 메뉴바만 켜고 설정 창을 안 연 경로에서도 피드 확인이 돌아야 한다.
        SparkleUpdaterHost.shared.start()
        #endif
        startTelemetryIfAvailable()
    }

    private static func startTelemetryIfAvailable() {
        #if Telemetry
        // non-fatal: DSN 없으면 TelemetryKit.start()가 내부에서 no-op.
        // catch: 기동 경로에서 절대 crash/hang 하지 않는다.
        do {
            let appName = Bundle.main.bundleIdentifier?
                .split(separator: ".").last.map(String.init)
                ?? ProcessInfo.processInfo.processName
            TelemetryKit.start(app: appName)
        } catch {
            // 기동은 막지 않되 조용히 삼키지도 않는다 — 원인은 로그에 남긴다.
            FileHandle.standardError.write(
                Data("[AppScaffoldKit] telemetry 시작 실패: \(error) — 기동은 계속한다\n".utf8))
        }
        #endif
    }

    /// 창을 띄우는 일반 앱의 표준 기동 — 액세서리가 아니라 정식 앱으로 올린다.
    /// `setActivationPolicy(.regular)` + `activate` 복붙(합계 26곳)을 대체한다.
    /// Agent Apps Bar 책상이 켜져 있으면 함대는 accessory 로 남겨 Dock에 안 붙는다.
    @MainActor public static func activateAsRegularApp() {
        #if canImport(AppKit)
        FleetDeskMode.applyActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        #endif
    }

    @MainActor public static func applyFleetDeskPolicy() {
        #if canImport(AppKit)
        let id = Bundle.main.bundleIdentifier ?? ""
        if FleetDeskMode.shouldHideDockIcon(bundleId: id) {
            FleetDeskMode.applyActivationPolicy(.accessory)
        }
        #endif
    }

    private static var ticker: Any?

    /// 상태 미러 티커를 한 번만 띄운다. 참조를 붙잡지 않으면 티커가 즉시 사라진다.
    public static func startStateMirror(app: String, snapshot: @escaping () -> Any?) {
        guard ticker == nil else { return }
        ticker = StateMirrorAutoTicker(app: app, snapshot: snapshot)
    }
}

// MARK: - Deprecated aliases

@available(*, deprecated, renamed: "FleetManagedApp")
public typealias RanodeApp = FleetManagedApp

@available(*, deprecated, renamed: "FleetManagedAppLocalization")
public typealias RanodeAppLocalization = FleetManagedAppLocalization

@available(*, deprecated, renamed: "FleetManagedAppBootstrap")
public typealias RanodeAppBootstrap = FleetManagedAppBootstrap

#endif
