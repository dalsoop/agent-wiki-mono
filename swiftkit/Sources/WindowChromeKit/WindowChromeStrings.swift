import Foundation
import LocalizationKit

/// 카탈로그 칸의 KR/EN 표시 이름. 원장 id(`sidebar` 등)는 영어로 두고, 사람·VoiceOver 만 번역한다.
///
/// 앱 언어는 `LocalizationManager` 와 같은 `app.language` 키를 읽는다.
public enum WindowChromeStrings {
    public enum Pane: String, Sendable {
        case sidebar
        case content
        case inspector
        case detail
    }

    public static let languageDefaultsKey = "app.language"

    public static func resolvedLanguage(
        defaults: UserDefaults = .standard,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let stored = defaults.string(forKey: languageDefaultsKey),
           let language = AppLanguage(rawValue: stored) {
            return language
        }
        return .system
    }

    public static func title(
        _ pane: Pane,
        language: AppLanguage,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String {
        let korean: Bool
        switch language {
        case .korean:
            korean = true
        case .english:
            korean = false
        case .system:
            korean = preferredLanguages.first.map { $0.hasPrefix("ko") } ?? false
        }
        switch (pane, korean) {
        case (.sidebar, true): return "사이드바"
        case (.sidebar, false): return "Sidebar"
        case (.content, true): return "목록"
        case (.content, false): return "List"
        case (.inspector, true): return "검사"
        case (.inspector, false): return "Inspector"
        case (.detail, true): return "상세"
        case (.detail, false): return "Detail"
        }
    }
}
