#if canImport(AppKit)
import AppKit

/// 창 앱이 "메뉴만 남는" 상태로 빠지는 걸 막는 공용 앱 델리게이트.
///
/// SwiftUI 창 앱(`WindowGroup`/`Window`)은 마지막 창을 닫아도 프로세스가 종료되지 않는다
/// (macOS 기본). 그 뒤 dock 클릭이나 `open -a` 로 다시 켜도, 재실행 프로세스는
/// `SingleInstance.exitIfAlreadyRunning()` 로 즉시 종료되고 기존(창 없는) 인스턴스에는
/// 창을 되살릴 경로가 없다 → 앱이 살아있는데 상단 앱 메뉴만 보여 "메뉴바 앱"처럼 오인된다.
///
/// 이 델리게이트는 reopen 이벤트에서 숨은 일반 창 하나만 앞으로 꺼내고 AppKit 의 추가 창
/// 생성을 막는다. 복구할 창이 전혀 없을 때만 기본 처리를 허용해 새 창 하나를 띄운다.
///
/// 사용:
/// ```swift
/// @NSApplicationDelegateAdaptor(WindowReopenDelegate.self) private var delegate
/// ```
/// 이미 자체 델리게이트가 있으면 이 클래스를 상속해 `applicationShouldHandleReopen` 을 물려받는다.
struct WindowReopenCandidate: Equatable, Sendable {
    let isVisible: Bool
    let isKey: Bool
    let isMain: Bool
    let isNormal: Bool
}

enum WindowReopenDecision: Equatable, Sendable {
    case activateExisting
    case restore(index: Int)
    case allowDefault
}

enum WindowReopenPolicy {
    static func decide(
        hasVisibleWindows: Bool,
        windows: [WindowReopenCandidate]
    ) -> WindowReopenDecision {
        if hasVisibleWindows || windows.contains(where: { $0.isVisible && $0.isNormal }) {
            return .activateExisting
        }

        let hiddenNormal = windows.indices.filter {
            !windows[$0].isVisible && windows[$0].isNormal
        }
        guard !hiddenNormal.isEmpty else { return .allowDefault }

        let selected = hiddenNormal.first(where: { windows[$0].isKey })
            ?? hiddenNormal.first(where: { windows[$0].isMain })
            ?? hiddenNormal[0]
        return .restore(index: selected)
    }
}

open class WindowReopenDelegate: NSObject, NSApplicationDelegate {
    public override init() { super.init() }

    /// 마지막 창이 닫혔을 때 프로세스 자동 종료 여부 (기본값: true).
    /// 일반 윈도우 앱이 마지막 창을 닫은 뒤 백그라운드 좀비 프로세스로 남아
    /// CPU, 메모리, 배터리를 갉아먹는 유령 프로세스 결함을 방지한다.
    /// 메뉴바 상주형이나 백그라운드 상주 앱의 경우 서브클래스에서 `terminatesAfterLastWindowClosed`를 `false`로 재정의한다.
    open var terminatesAfterLastWindowClosed: Bool {
        true
    }

    open func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        terminatesAfterLastWindowClosed
    }

    open func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        let windows = sender.windows
        let candidates = windows.map {
            WindowReopenCandidate(
                isVisible: $0.isVisible,
                isKey: $0.isKeyWindow,
                isMain: $0.isMainWindow,
                isNormal: !($0 is NSPanel) && $0.level == .normal
            )
        }

        switch WindowReopenPolicy.decide(hasVisibleWindows: flag, windows: candidates) {
        case .activateExisting:
            sender.activate(ignoringOtherApps: true)
            return false
        case .restore(let index):
            windows[index].makeKeyAndOrderFront(nil)
            sender.activate(ignoringOtherApps: true)
            return false
        case .allowDefault:
            return true
        }
    }
}
#endif
