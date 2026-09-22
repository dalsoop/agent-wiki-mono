import Foundation
import LocalizationKit

/// 함대 수신 UI 문자열. 앱의 `app.language` 키와 같은 값을 읽는다.
enum SparkleL10n {
    static let defaultsKey = "app.language"

    /// `Bundle.module` 생성 접근자는 .app 루트와 빌드 시 baked 절대경로만 보고
    /// `Contents/Resources/` 후보가 없어 설치본이 워크트리 .build 존재에 묶인다 — 워크트리
    /// 삭제 즉시 런치 크래시(2026-08-23 laravel-local-development-setup 실측). 설치 위치에서
    /// 직접 찾는 LocalizationKit 리졸버로 돌린다.
    @MainActor
    static let shared = LocalizationManager(
        baseBundle: ResourceBundle.named("swiftkit-sparkle_SparkleUpdateKit"),
        defaultsKey: defaultsKey
    )

    @MainActor
    static func syncFromDefaults() {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? AppLanguage.system.rawValue
        let language = AppLanguage(rawValue: raw) ?? .system
        if shared.language != language {
            shared.setLanguage(language)
        }
    }

    @MainActor
    static func t(_ key: String) -> String {
        syncFromDefaults()
        return shared.string(key)
    }
}
