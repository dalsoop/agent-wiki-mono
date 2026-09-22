import SwiftUI
import LocalizationKit
import LaunchAtLoginKit

/// 메뉴바/설정 앱의 **표준 설정 셸**.
///
/// 공통 블록 고정 순서:
/// 1. `AboutSection` (앱 이름 + v버전 (빌드) [+ 번들 ID])
/// 2. 언어 (`LanguageSettingsSection`) — 바인딩이 있을 때만
/// 3. 로그인 시 실행 (`LaunchAtLoginToggle`) — 제목이 있을 때만
/// 4. 앱 전용 슬롯 (`appContent`)
///
/// 자동업데이트는 Sparkle 이 `settingsFormFooter` 로 **이 Form 안**에 섹션을 넣는다.
/// VStack 으로 폼 아래에 붙이지 않는다(스크롤이 끊김).
/// ```swift
/// StandardSettingsForm(language: $model.loc.language, …) {
///     Section("앱 전용") { … }
/// }
/// ```
/// RanodeApp 계열은 `Settings` 씬이 `RanodeSettingsHost.wrap` 으로 이미 붙인다.
public struct StandardSettingsForm<AppContent: View>: View {
    private let showAbout: Bool
    private let showBundleID: Bool
    private let languageTitle: String?
    private let language: Binding<AppLanguage>?
    private let languageLabel: (AppLanguage) -> String
    private let translationCoverage: TranslationCoverage?
    private let launchAtLoginTitle: String?
    private let appContent: AppContent
    @Environment(\.settingsFormFooter) private var settingsFormFooter

    /// - Parameters:
    ///   - showAbout: 상단 버전 섹션 (기본 true — 표준 필수).
    ///   - showBundleID: About 아래 번들 ID 캡션.
    ///   - languageTitle: 언어 피커 라벨. `nil` 이면 언어 블록 생략.
    ///   - language: 현재 언어 바인딩. `languageTitle` 과 함께 있어야 노출.
    ///   - languageLabel: 각 언어 표시 문자열.
    ///   - translationCoverage: 얕은 i18n 고지. `hardcodedUICount>0` 이면 피커 아래 경고.
    ///   - launchAtLoginTitle: 로그인 시 실행 토글 라벨. `nil` 이면 생략.
    ///   - appContent: 앱 전용 `Section` 들.
    public init(
        showAbout: Bool = true,
        showBundleID: Bool = true,
        languageTitle: String? = "Language",
        language: Binding<AppLanguage>? = nil,
        languageLabel: @escaping (AppLanguage) -> String = SettingsUIStrings.languageLabel,
        translationCoverage: TranslationCoverage? = nil,
        launchAtLoginTitle: String? = "Open at Login",
        @ViewBuilder appContent: () -> AppContent
    ) {
        self.showAbout = showAbout
        self.showBundleID = showBundleID
        self.languageTitle = languageTitle
        self.language = language
        self.languageLabel = languageLabel
        self.translationCoverage = translationCoverage
        self.launchAtLoginTitle = launchAtLoginTitle
        self.appContent = appContent()
    }

    public var body: some View {
        Form {
            if showAbout {
                Section {
                    AboutSection(showBundleID: showBundleID)
                }
            }

            if let languageTitle, let language {
                Section {
                    LanguageSettingsSection(
                        languageTitle,
                        selection: language,
                        label: languageLabel,
                        coverage: translationCoverage
                    )
                    if let launchAtLoginTitle {
                        LaunchAtLoginToggle(launchAtLoginTitle)
                    }
                }
            } else if let launchAtLoginTitle {
                Section {
                    LaunchAtLoginToggle(launchAtLoginTitle)
                }
            }

            appContent

            if let footer = settingsFormFooter {
                footer
                    .preference(key: SettingsFormFooterConsumedKey.self, value: true)
            }
        }
        .formStyle(.grouped)
    }
}

/// `RanodeSettingsHost` / `withFleetUpdateSettings()` 가 Sparkle 섹션을 넣을 때 쓴다.
public struct SettingsFormFooterKey: EnvironmentKey {
    nonisolated(unsafe) public static let defaultValue: AnyView? = nil
}

public extension EnvironmentValues {
    var settingsFormFooter: AnyView? {
        get { self[SettingsFormFooterKey.self] }
        set { self[SettingsFormFooterKey.self] = newValue }
    }
}

/// 표준 폼이 footer 를 이미 그렸으면 wrap 이 아래에 한 번 더 붙이지 않는다.
public struct SettingsFormFooterConsumedKey: PreferenceKey {
    public static let defaultValue = false
    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
