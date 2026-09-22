import SwiftUI
import LocalizationKit
import LaunchAtLoginKit

/// 47개 앱의 SettingsView 가 각자 조립하던 "언어 선택 · 로그인 시 실행 · 정보(버전)" 섹션을
/// 재사용 컴포넌트로 모은다. 앱은 이 섹션들을 Form 에 꽂기만 하면 된다.

/// 언어(UI 로케일) 선택 Picker. 선택은 바인딩으로 앱의 LocalizationManager 에 반영한다.
///
/// `coverage` 가 미완료면 피커 아래에 고지를 붙여, 언어 전환이 전 UI에 안 먹는
/// 얕은 i18n 상태를 숨기지 않는다.
public struct LanguageSettingsSection: View {
    private let title: String
    private let label: (AppLanguage) -> String
    private let coverage: TranslationCoverage?
    @Binding private var selection: AppLanguage

    /// - Parameters:
    ///   - title: 섹션/Picker 라벨(예: 앱 L10n `"언어"` / `"Language"`).
    ///   - selection: 현재 언어 바인딩(앱 모델의 AppLanguage).
    ///   - label: 각 언어의 표시 문자열(기본: 한국어/English/System — 고유명).
    ///   - coverage: UI 배선 상태. `nil` 이면 고지 없음(레거시). 미완료면 footer.
    public init(_ title: String = "Language",
                selection: Binding<AppLanguage>,
                label: @escaping (AppLanguage) -> String = SettingsUIStrings.languageLabel,
                coverage: TranslationCoverage? = nil) {
        self.title = title
        self._selection = selection
        self.label = label
        self.coverage = coverage
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(title, selection: $selection) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Text(label(lang)).tag(lang)
                }
            }
            if let notice = coverage?.notice(displayLanguage: selection) {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("translation-coverage-notice")
            }
        }
    }
}

/// 앱 이름 + 버전(빌드) 정보 섹션. **모든 GUI 앱 설정에 필수.**
public struct AboutSection: View {
    private let appName: String
    private let shortVersion: String
    private let build: String
    private let bundleID: String?
    private let showBundleID: Bool

    /// 실행 중 메인 번들에서 이름·버전을 읽어 구성.
    public init(bundle: Bundle = .main, showBundleID: Bool = true) {
        appName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
        shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        bundleID = bundle.bundleIdentifier
        self.showBundleID = showBundleID
    }

    public init(
        appName: String,
        shortVersion: String,
        build: String,
        bundleID: String? = nil,
        showBundleID: Bool = true
    ) {
        self.appName = appName
        self.shortVersion = shortVersion
        self.build = build
        self.bundleID = bundleID
        self.showBundleID = showBundleID
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(appName) {
                Text("v\(shortVersion) (\(build))")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if showBundleID, let bundleID, !bundleID.isEmpty {
                Text(bundleID)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }
}

/// 언어 옵션 **고유명** 라벨. 피커는 현재 UI 언어와 무관하게 언어 이름으로 고르는 편이 낫다.
public enum SettingsUIStrings {
    public static func languageLabel(_ lang: AppLanguage) -> String {
        switch lang {
        case .system: return "System"
        case .korean: return "한국어"
        case .english: return "English"
        }
    }
}

// LaunchAtLoginKit 의 `LaunchAtLoginToggle` 을 여기서도 쓸 수 있게 재노출(앱은 한 모듈만 import).
@_exported import struct LaunchAtLoginKit.LaunchAtLoginToggle
