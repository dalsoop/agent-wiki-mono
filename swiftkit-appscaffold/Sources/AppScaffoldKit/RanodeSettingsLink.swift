#if os(macOS)
import AppKit

/// 스캐폴드 `Settings` 씬을 연다. ExtraApp·MenuBarApp·WindowGroupApp 이 같이 쓴다.
/// `openWindow(id: "settings")` 는 Window id 가 있을 때만 되고, 설정 씬과는 별개다.
public enum RanodeSettingsLink {
    @MainActor
    public static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
#endif
