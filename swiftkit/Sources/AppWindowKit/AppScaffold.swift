#if canImport(AppKit)
import AppKit
@_exported import FleetDeskKit
import SwiftUI

/// 창(윈도우) 앱들이 공유하는 표준 AppDelegate.
///
/// ~60개 앱의 `*App.swift` 가 각자 반복하던 activationPolicy 설정 + 활성화 + 단일 인스턴스
/// 가드를 한 곳으로 모은다. 서브클래싱해 훅을 덧붙일 수 있다.
///
/// 사용:
/// ```swift
/// @main struct MyApp: App {
///     @NSApplicationDelegateAdaptor(StandardWindowAppDelegate.self) private var delegate
///     var body: some Scene { WindowGroup { ContentView() } }
/// }
/// ```
/// 단일 인스턴스가 필요하면 서브클래스에서 `enforcesSingleInstance = true` 로 둔다.
open class StandardWindowAppDelegate: NSObject, NSApplicationDelegate {
    /// Dock 아이콘·Cmd-Tab 노출 여부(.regular) vs 메뉴바 상주(.accessory).
    open var activationPolicy: NSApplication.ActivationPolicy { .regular }
    /// 마지막 창이 닫히면 앱을 종료할지.
    open var terminatesAfterLastWindowClosed: Bool { true }
    /// 같은 bundle id 두 번째 실행을 막을지.
    open var enforcesSingleInstance: Bool { false }

    open func applicationWillFinishLaunching(_ notification: Notification) {
        if enforcesSingleInstance, MainActor.assumeIsolated({ SingleInstanceGuard.isDuplicate() }) {
            NSApp.terminate(nil)
        }
    }

    open func applicationDidFinishLaunching(_ notification: Notification) {
        FleetDeskMode.applyActivationPolicy(activationPolicy)
        if #available(macOS 14.0, *) {
            NSApplication.shared.activate()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        // Dock 부재 시에도 각 앱이 독자 창으로 정상 활성화되는 생명주기 보장
        DispatchQueue.main.async {
            let normalWindows = NSApplication.shared.windows.filter { !($0 is NSPanel) && $0.level == .normal }
            for window in normalWindows where !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            if let firstWindow = normalWindows.first(where: \.isVisible) ?? normalWindows.first {
                firstWindow.makeKeyAndOrderFront(nil)
            }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        terminatesAfterLastWindowClosed
    }

    /// 창이 닫히거나 숨겨진 뒤 Dock 아이콘 클릭 또는 open -a 재실행 시 창을 복원할지 여부.
    open var restoresHiddenWindowsOnReopen: Bool { true }

    @MainActor
    open func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard restoresHiddenWindowsOnReopen else { return true }
        if !flag {
            let normalWindows = sender.windows.filter { !($0 is NSPanel) && $0.level == .normal }
            let hiddenWindows = normalWindows.filter { !$0.isVisible }
            let targets = hiddenWindows.isEmpty ? normalWindows : hiddenWindows
            if !targets.isEmpty {
                for window in targets {
                    window.makeKeyAndOrderFront(nil)
                }
                if #available(macOS 14.0, *) {
                    sender.activate()
                } else {
                    sender.activate(ignoringOtherApps: true)
                }
                return false
            }
        }
        return true
    }
}

public extension Scene {
    /// 표준 창 크기 정책(최소 크기 존중 + 기본 크기)을 한 번에 적용한다.
    func standardWindowSizing(defaultWidth: CGFloat, defaultHeight: CGFloat) -> some Scene {
        self
            .defaultSize(width: defaultWidth, height: defaultHeight)
            .windowResizability(.contentMinSize)
    }

    /// 단일창 앱: `File ▸ New Window`(⌘N) 명령을 제거해 창이 늘어나지 않게 한다.
    /// `WindowGroup { … }.singleWindow()` 처럼 붙인다. (완전한 단일 고유 창은 SwiftUI
    /// `Window` 씬을 쓰는 게 가장 확실하지만, 기존 `WindowGroup` 앱을 최소 변경으로 단일창화할 때 쓴다.)
    func singleWindow() -> some Scene {
        commands { CommandGroup(replacing: .newItem) {} }
    }
}
#endif
