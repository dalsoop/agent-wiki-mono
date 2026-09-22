import AppKit
import Foundation

/// 메뉴바 앱(LSUIElement)이 **자기** 설정 창을 여는 표준 경로.
///
/// ## 왜 필요한가 — 메뉴바가 꽉 차면 앱에 손이 닿지 않는다
///
/// LSUIElement 앱의 유일한 진입점은 메뉴바 상태 아이콘인데, 메뉴바가 과밀하면 macOS 가 아이콘을
/// 화면 밖으로 밀어낸다(실측: 상태 아이템이 x=-18 에 놓여 클릭 불가). 그러면 설정·권한 안내에
/// 영영 도달할 수 없다. `open -a` 재실행으로 설정 창을 여는 탈출구가 반드시 필요하다.
///
/// ## 왜 URL 을 쓰나
///
/// SwiftUI 의 `Window(id:)` 는 View 밖(앱 델리게이트 등)에서 열 방법이 마땅치 않다. 공식 경로는
/// `handlesExternalEvents(matching:)` + URL 이다. Scene 쪽에 이렇게 걸어둔다:
///
/// ```swift
/// Window("설정", id: "settings") { SettingsView() }
///     .handlesExternalEvents(matching: ["settings"])
/// ```
///
/// ## 함정 — NSWorkspace.open(url) 은 "나 자신" 을 열지 않는다
///
/// `NSWorkspace.open(url)` 은 **스킴만 보고** 앱을 고른다. 같은 스킴을 등록한 번들이 둘 이상이면
/// (설치본 + `.dev` 개발 빌드) 엉뚱한 쪽이 뜬다 — 실제로 개발 번들에서 연 URL 이 /Applications
/// 설치본을 실행했다. 그래서 `withApplicationAt:` 로 현재 번들을 못 박는다.
///
/// 스킴은 Info.plist 에서 읽는다(하드코딩 금지) — 빌드 스크립트가 개발 빌드 스킴에 `-dev` 를
/// 붙여 정본 스킴 경쟁에서 빼므로, 하드코딩하면 개발 빌드에서 창이 안 열린다.
@MainActor
public enum SettingsWindowOpener {

    /// 번들이 등록한 첫 URL 스킴(없으면 nil).
    public static func registeredScheme(in bundle: Bundle = .main) -> String? {
        guard let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        else { return nil }
        for t in types {
            if let schemes = t["CFBundleURLSchemes"] as? [String], let first = schemes.first {
                return first
            }
        }
        return nil
    }

    /// `<등록스킴>://<event>` 를 **현재 번들에** 전달해 창을 연다.
    /// - Parameter event: `handlesExternalEvents(matching:)` 에 건 문자열(기본 "settings").
    public static func open(event: String = "settings") {
        guard let scheme = registeredScheme(),
              let url = URL(string: "\(scheme)://\(event)") else { return }
        NSApp.activate(ignoringOtherApps: true)
        // withApplicationAt: 이 이 함수의 존재 이유 — 스킴이 겹쳐도 남의 앱을 깨우지 않는다.
        NSWorkspace.shared.open([url], withApplicationAt: Bundle.main.bundleURL,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    /// 창이 화면 밖(디스플레이 분리·이전 프레임 복원 등)에 열렸으면 현재 화면 중앙으로 되돌린다.
    public static func ensureOnScreen(titled title: String) {
        guard let win = NSApp.windows.first(where: { $0.title == title && $0.isVisible })
        else { return }
        let visible = (win.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        if visible.intersection(win.frame).isEmpty || win.frame.minY > visible.maxY {
            win.center()
        }
    }
}
