#if canImport(AppKit) && canImport(SwiftUI)
import AppKit
import SwiftUI
@_exported import FleetDeskKit
@_exported import SingleInstanceKit

// MARK: - Superview Window Tracking Anchor

/// superview에 부착되어 NSWindow 인스턴스를 포착하고 윈도우 라이프사이클을 구성하는 앵커 뷰.
private final class StandardWindowAccessView: NSView {
    var onWindow: ((NSWindow) -> Void)?
    private var handled = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard !handled, let window else { return }
        handled = true
        onWindow?(window)
    }
}

// MARK: - Window Close Interceptor

/// 윈도우 닫기(⌘W 또는 닫기 버튼) 인터셉터.
/// `preventsClose` 가 활성화된 경우 창을 파괴하지 않고 `.orderOut(nil)` 로 숨겨 백그라운드 상주를 보장합니다.
private final class StandardWindowCloseInterceptor: NSObject, NSWindowDelegate {
    weak var originalDelegate: NSWindowDelegate?
    var preventsClose: Bool = false
    var onWindowClose: (() -> Bool)?

    init(originalDelegate: NSWindowDelegate? = nil, preventsClose: Bool = false, onWindowClose: (() -> Bool)? = nil) {
        self.originalDelegate = originalDelegate
        self.preventsClose = preventsClose
        self.onWindowClose = onWindowClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if let onWindowClose {
            return onWindowClose()
        }
        if preventsClose {
            sender.orderOut(nil)
            return false
        }
        return originalDelegate?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
            return true
        }
        return super.responds(to: aSelector) || (originalDelegate?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let originalDelegate, originalDelegate.responds(to: aSelector) {
            return originalDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

private nonisolated(unsafe) var standardWindowInterceptorKey: UInt8 = 0

// MARK: - NSViewRepresentable Configurator

/// 창 수준 설정(위치/크기 자동복원, 오프스크린 방지, 닫기 방지, 툴바 등)을 NSWindow에 적용하는 Representable.
public struct StandardWindowConfigurator: NSViewRepresentable {
    public var title: String?
    public var minSize: CGSize?
    public var defaultSize: CGSize?
    public var autosaveKey: String?
    public var preventsClose: Bool
    public var standardToolbar: Bool
    public var bringToFront: Bool
    public var onWindow: ((NSWindow) -> Void)?

    public init(
        title: String? = nil,
        minSize: CGSize? = nil,
        defaultSize: CGSize? = nil,
        autosaveKey: String? = nil,
        preventsClose: Bool = false,
        standardToolbar: Bool = false,
        bringToFront: Bool = false,
        onWindow: ((NSWindow) -> Void)? = nil
    ) {
        self.title = title
        self.minSize = minSize
        self.defaultSize = defaultSize
        self.autosaveKey = autosaveKey
        self.preventsClose = preventsClose
        self.standardToolbar = standardToolbar
        self.bringToFront = bringToFront
        self.onWindow = onWindow
    }

    public func makeNSView(context: Context) -> NSView {
        let view = StandardWindowAccessView()
        view.onWindow = { window in
            Task { @MainActor in
                configure(window)
            }
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        if let title, !title.isEmpty, window.title != title {
            window.title = title
        }
    }

    private func configure(_ window: NSWindow) {
        // 1. 타이틀
        if let title, !title.isEmpty {
            window.title = title
        }

        // 2. 최소 크기
        if let minSize {
            window.contentMinSize = NSSize(width: minSize.width, height: minSize.height)
        }

        // 3. 위치/크기 자동 복원
        if let autosaveKey, !autosaveKey.isEmpty {
            window.setFrameAutosaveName(autosaveKey)
        }

        // 4. 초기 기본 크기 적용 (저장된 프레임이 없을 경우)
        if let defaultSize, defaultSize.width > 100, defaultSize.height > 100 {
            if autosaveKey == nil || !window.setFrameUsingName(autosaveKey!) {
                var frame = window.frame
                frame.size = NSSize(width: defaultSize.width, height: defaultSize.height)
                if let screen = window.screen ?? NSScreen.main {
                    let visible = screen.visibleFrame
                    frame.origin = NSPoint(
                        x: visible.midX - frame.size.width / 2,
                        y: visible.midY - frame.size.height / 2
                    )
                }
                window.setFrame(frame, display: true)
            }
        }

        // 5. 화면 밖 이탈 복구 (모니터 분리, 해상도 변경 등 off-screen 방지)
        let visibleScreens = NSScreen.screens.map(\.visibleFrame)
        let isOnScreen = visibleScreens.contains { $0.intersects(window.frame) }
        if !isOnScreen, let main = NSScreen.main?.visibleFrame {
            let size = window.frame.size
            let origin = NSPoint(x: main.midX - size.width / 2, y: main.midY - size.height / 2)
            window.setFrame(NSRect(origin: origin, size: size), display: true)
        }

        // 6. 표준 툴바 스타일
        if standardToolbar {
            window.toolbarStyle = .unified
            window.titleVisibility = .visible
        }

        // 7. 창 닫기 방지 (닫아도 파괴되지 않고 숨김 처리)
        window.isReleasedWhenClosed = false
        if preventsClose {
            let interceptor = StandardWindowCloseInterceptor(
                originalDelegate: window.delegate,
                preventsClose: true
            )
            objc_setAssociatedObject(window, &standardWindowInterceptorKey, interceptor, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            window.delegate = interceptor
        }

        // 8. 전면 노출
        if bringToFront {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }

        onWindow?(window)
    }
}

// MARK: - View Modifier

/// 단일 뷰에 윈도우 크기, 다크모드 대응, 프레임 자동 복원 및 닫기 방지 등을 일체형으로 적용하는 모디파이어.
public struct StandardWindowModifier<Footer: View>: ViewModifier {
    public var title: String?
    public var minSize: CGSize?
    public var defaultSize: CGSize?
    public var autosaveKey: String?
    public var preventsClose: Bool
    public var standardToolbar: Bool
    public var bringToFront: Bool
    public var colorScheme: ColorScheme?
    private let footer: Footer?

    public init(
        title: String? = nil,
        minSize: CGSize? = nil,
        defaultSize: CGSize? = nil,
        autosaveKey: String? = nil,
        preventsClose: Bool = false,
        standardToolbar: Bool = false,
        bringToFront: Bool = false,
        colorScheme: ColorScheme? = nil,
        footer: Footer? = nil
    ) {
        self.title = title
        self.minSize = minSize
        self.defaultSize = defaultSize
        self.autosaveKey = autosaveKey
        self.preventsClose = preventsClose
        self.standardToolbar = standardToolbar
        self.bringToFront = bringToFront
        self.colorScheme = colorScheme
        self.footer = footer
    }

    public func body(content: Content) -> some View {
        content
            .frame(
                minWidth: minSize?.width,
                idealWidth: defaultSize?.width,
                minHeight: minSize?.height,
                idealHeight: defaultSize?.height
            )
            .modifier(StandardColorSchemeModifier(colorScheme: colorScheme))
            .modifier(StandardOptionalFooterModifier(footer: footer))
            .background(
                StandardWindowConfigurator(
                    title: title,
                    minSize: minSize,
                    defaultSize: defaultSize,
                    autosaveKey: autosaveKey,
                    preventsClose: preventsClose,
                    standardToolbar: standardToolbar,
                    bringToFront: bringToFront
                )
            )
    }
}

private struct StandardColorSchemeModifier: ViewModifier {
    let colorScheme: ColorScheme?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let colorScheme {
            content.preferredColorScheme(colorScheme)
        } else {
            content
        }
    }
}

private struct StandardOptionalFooterModifier<Footer: View>: ViewModifier {
    let footer: Footer?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let footer {
            content.scaffoldFooterBar {
                footer
            }
        } else {
            content
        }
    }
}

// MARK: - View Extensions

public extension View {
    /// 뷰를 표준 창 명세(크기, 자동복원, 닫기방지, 툴바, 다크모드)로 포장합니다.
    func standardWindow(
        title: String? = nil,
        minSize: CGSize? = nil,
        defaultSize: CGSize? = nil,
        autosaveKey: String? = nil,
        preventsClose: Bool = false,
        standardToolbar: Bool = false,
        bringToFront: Bool = false,
        colorScheme: ColorScheme? = nil
    ) -> some View {
        modifier(
            StandardWindowModifier<EmptyView>(
                title: title,
                minSize: minSize,
                defaultSize: defaultSize,
                autosaveKey: autosaveKey,
                preventsClose: preventsClose,
                standardToolbar: standardToolbar,
                bringToFront: bringToFront,
                colorScheme: colorScheme,
                footer: nil
            )
        )
    }

    /// 푸터 바가 포함된 표준 창 모디파이어.
    func standardWindow<Footer: View>(
        title: String? = nil,
        minSize: CGSize? = nil,
        defaultSize: CGSize? = nil,
        autosaveKey: String? = nil,
        preventsClose: Bool = false,
        standardToolbar: Bool = false,
        bringToFront: Bool = false,
        colorScheme: ColorScheme? = nil,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        modifier(
            StandardWindowModifier(
                title: title,
                minSize: minSize,
                defaultSize: defaultSize,
                autosaveKey: autosaveKey,
                preventsClose: preventsClose,
                standardToolbar: standardToolbar,
                bringToFront: bringToFront,
                colorScheme: colorScheme,
                footer: footer()
            )
        )
    }
}

// MARK: - StandardWindow Scene

/// 창 앱마다 100줄씩 복제되던 창 수명주기, 자동복원, 닫기방지, 툴바, 다크모드 설정을
/// 단 한 줄로 선언하는 SwiftUI Scene 래퍼.
///
/// 사용 예:
/// ```swift
/// @main
/// struct MyApp: App {
///     @NSApplicationDelegateAdaptor(StandardWindowAppDelegate.self) private var delegate
///
///     var body: some Scene {
///         StandardWindow(
///             title: "My Application",
///             minSize: CGSize(width: 800, height: 600),
///             autosaveKey: "MyAppMainWindow"
///         ) {
///             MainView()
///         }
///     }
/// }
/// ```
public struct StandardWindow<Content: View, Footer: View>: Scene {
    public let title: String
    public let id: String
    public let minSize: CGSize?
    public let defaultSize: CGSize?
    public let autosaveKey: String?
    public let preventsClose: Bool
    public let standardToolbar: Bool
    public let colorScheme: ColorScheme?
    private let content: Content
    private let footer: Footer?

    public init(
        title: String = "",
        id: String = "main",
        minSize: CGSize? = nil,
        defaultSize: CGSize? = nil,
        autosaveKey: String? = nil,
        preventsClose: Bool = false,
        standardToolbar: Bool = false,
        colorScheme: ColorScheme? = nil,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.title = title
        self.id = id
        self.minSize = minSize
        self.defaultSize = defaultSize
        self.autosaveKey = autosaveKey
        self.preventsClose = preventsClose
        self.standardToolbar = standardToolbar
        self.colorScheme = colorScheme
        self.content = content()
        self.footer = nil
    }

    public init(
        _ title: String,
        id: String = "main",
        minSize: CGSize? = nil,
        defaultSize: CGSize? = nil,
        autosaveKey: String? = nil,
        preventsClose: Bool = false,
        standardToolbar: Bool = false,
        colorScheme: ColorScheme? = nil,
        @ViewBuilder content: () -> Content
    ) where Footer == EmptyView {
        self.init(
            title: title,
            id: id,
            minSize: minSize,
            defaultSize: defaultSize,
            autosaveKey: autosaveKey,
            preventsClose: preventsClose,
            standardToolbar: standardToolbar,
            colorScheme: colorScheme,
            content: content
        )
    }

    public init(
        title: String = "",
        id: String = "main",
        minSize: CGSize? = nil,
        defaultSize: CGSize? = nil,
        autosaveKey: String? = nil,
        preventsClose: Bool = false,
        standardToolbar: Bool = false,
        colorScheme: ColorScheme? = nil,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.id = id
        self.minSize = minSize
        self.defaultSize = defaultSize
        self.autosaveKey = autosaveKey
        self.preventsClose = preventsClose
        self.standardToolbar = standardToolbar
        self.colorScheme = colorScheme
        self.footer = footer()
        self.content = content()
    }

    public init(
        _ title: String,
        id: String = "main",
        minSize: CGSize? = nil,
        defaultSize: CGSize? = nil,
        autosaveKey: String? = nil,
        preventsClose: Bool = false,
        standardToolbar: Bool = false,
        colorScheme: ColorScheme? = nil,
        @ViewBuilder footer: () -> Footer,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title: title,
            id: id,
            minSize: minSize,
            defaultSize: defaultSize,
            autosaveKey: autosaveKey,
            preventsClose: preventsClose,
            standardToolbar: standardToolbar,
            colorScheme: colorScheme,
            footer: footer,
            content: content
        )
    }

    public var body: some Scene {
        WindowGroup(title, id: id) {
            content
                .modifier(
                    StandardWindowModifier(
                        title: title,
                        minSize: minSize,
                        defaultSize: defaultSize,
                        autosaveKey: autosaveKey,
                        preventsClose: preventsClose,
                        standardToolbar: standardToolbar,
                        colorScheme: colorScheme,
                        footer: footer
                    )
                )
        }
        .windowResizability(.contentMinSize)
        .defaultSize(
            width: defaultSize?.width ?? minSize?.width ?? 600,
            height: defaultSize?.height ?? minSize?.height ?? 400
        )
    }
}
#endif
