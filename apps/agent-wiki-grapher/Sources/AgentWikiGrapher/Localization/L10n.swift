import Foundation

/// 앱의 사용자 노출 문자열 키. `CaseIterable` 이라 누락 검증 테스트가 전 키를 순회할 수 있다.
// 새 케이스를 추가하면 en.lproj / ko.lproj 의 Localizable.strings 에도 같은 키를 추가할 것.
enum L10nKey: String, CaseIterable {
    case menuRefresh = "menu.refresh"
    case menuSettings = "menu.settings"
    case menuQuit = "menu.quit"
    case settingsTitle = "settings.title"
    case settingsLanguage = "settings.language"
    case settingsLaunchAtLogin = "settings.launch_at_login"
    case onboardingSubtitle = "onboarding.subtitle"
    case onboardingFeatureStartTitle = "onboarding.feature_start_title"
    case onboardingFeatureStartDetail = "onboarding.feature_start_detail"
    case onboardingFeatureCliTitle = "onboarding.feature_cli_title"
    case onboardingFeatureCliDetail = "onboarding.feature_cli_detail"
    case onboardingFeatureEntitlementTitle = "onboarding.feature_entitlement_title"
    case onboardingFeatureEntitlementDetail = "onboarding.feature_entitlement_detail"
    case onboardingPrivacyNote = "onboarding.privacy_note"
    case onboardingStart = "onboarding.start"
    case mainPrint = "main.print"
    case mainPrint_2 = "main.print-2"
    case mainPrint_3 = "main.print-3"
    case mainPrint_4 = "main.print-4"
    case mainPrint_5 = "main.print-5"
    case mainPrint_6 = "main.print-6"
    case mainPrint_7 = "main.print-7"
}
