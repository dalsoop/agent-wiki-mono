import Foundation

/// 앱이 노출하는 UI 언어 선택지. `.system` 은 macOS 시스템 언어를 따른다.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system
    case korean = "ko"
    case english = "en"
}
