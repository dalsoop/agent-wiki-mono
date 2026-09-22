import Foundation

/// 앱이 Settings 언어 피커에 보고하는 **UI 문자열 배선 상태**.
///
/// 카탈로그(en/ko)만 있고 View 가 아직 한글 리터럴인 “얕은 i18n” 앱에서,
/// 언어를 바꿔도 화면이 안 바뀌는 것처럼 보이는 문제를 사용자가 이해하도록
/// `LanguageSettingsSection` / `StandardSettingsForm` 이 고지를 띄운다.
///
/// 숫자는 `app-i18n-inspector scan` 의 `hardcodedKorean` 을 앱이 넘긴다
/// (런타임에 소스를 스캔하지 않는다). hard=0 이면 `.complete`.
public struct TranslationCoverage: Sendable, Equatable {
    /// 아직 L10n 에 안 묶인 UI 한글(또는 고정 문자열) 개수. 0 = 완료.
    public var hardcodedUICount: Int

    public init(hardcodedUICount: Int) {
        self.hardcodedUICount = max(0, hardcodedUICount)
    }

    public static let complete = TranslationCoverage(hardcodedUICount: 0)

    public var isComplete: Bool { hardcodedUICount == 0 }

    public var isIncomplete: Bool { !isComplete }

    /// 피커 아래 footer 문구. `displayLanguage` 는 현재 UI 언어(시스템이면 ko/en 휴리스틱).
    public func notice(displayLanguage: AppLanguage) -> String? {
        guard isIncomplete else { return nil }
        let useKorean: Bool = {
            switch displayLanguage {
            case .korean: return true
            case .english: return false
            case .system:
                let pref = Locale.preferredLanguages.first ?? "en"
                return pref.hasPrefix("ko")
            }
        }()
        if useKorean {
            if hardcodedUICount == 1 {
                return "일부 화면 문구는 아직 번역이 연결되어 있지 않습니다. 언어를 바꿔도 그대로일 수 있습니다."
            }
            return "일부 화면 문구 \(hardcodedUICount)개는 아직 번역이 연결되어 있지 않습니다. 언어를 바꿔도 그대로일 수 있습니다."
        }
        if hardcodedUICount == 1 {
            return "Some UI labels are not wired for translation yet. Switching language may not change every string."
        }
        return "\(hardcodedUICount) UI labels are not wired for translation yet. Switching language may not change every string."
    }
}
