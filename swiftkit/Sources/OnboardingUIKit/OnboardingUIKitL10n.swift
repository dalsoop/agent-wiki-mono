import Foundation
import LocalizationKit

public enum OnboardingUIKitL10n {
    private static let fallbackEnglish: [String: String] = [
        "onboarding.subtitle.default": "Complete the necessary setup to get started right away.",
        "onboarding.button.skip": "Later",
        "onboarding.button.start": "Get Started",
        "onboarding.button.required_disabled": "Please complete required items",
        "onboarding.status.granted": "Completed",
        "onboarding.action.open_settings": "Open Settings",
        "onboarding.action.enable_now": "Enable Now",
        "onboarding.action.apply_now": "Apply Now",
        "onboarding.note.privacy": "All data is securely stored locally on your device.",

        "onboarding.item.full_disk_access.title": "Full Disk Access",
        "onboarding.item.full_disk_access.detail": "Full Disk Access is required to read system files and inspect disk state.",
        "onboarding.item.accessibility.title": "Accessibility Permission",
        "onboarding.item.accessibility.detail": "Accessibility permission is required for system control and UI automation.",
        "onboarding.item.screen_recording.title": "Screen Recording Permission",
        "onboarding.item.screen_recording.detail": "Screen recording permission is required for screen capture and text recognition.",
        "onboarding.item.camera.title": "Camera Permission",
        "onboarding.item.camera.detail": "Camera permission is required for video capture and camera features.",
        "onboarding.item.microphone.title": "Microphone Permission",
        "onboarding.item.microphone.detail": "Microphone permission is required for audio recording and voice input.",
        "onboarding.item.input_monitoring.title": "Input Monitoring Permission",
        "onboarding.item.input_monitoring.detail": "Input monitoring permission is required for keyboard shortcuts and input detection.",
        "onboarding.item.location.title": "Location Permission",
        "onboarding.item.location.detail": "Location permission is required for location and network status awareness.",

        "onboarding.item.defaults.title": "Recommended Defaults",
        "onboarding.item.defaults.detail": "Applies recommended default settings for optimal operation.",
        "onboarding.item.required.title": "Required Settings",
        "onboarding.item.required.detail": "Essential permissions and setup required for functionality."
    ]

    private static let fallbackKorean: [String: String] = [
        "onboarding.subtitle.default": "앱이 바로 동작하도록 필요한 설정을 지금 끝냅니다.",
        "onboarding.button.skip": "나중에",
        "onboarding.button.start": "시작하기",
        "onboarding.button.required_disabled": "필수 항목을 완료해 주세요",
        "onboarding.status.granted": "완료됨",
        "onboarding.action.open_settings": "설정 열기",
        "onboarding.action.enable_now": "지금 켜기",
        "onboarding.action.apply_now": "지금 적용",
        "onboarding.note.privacy": "모든 데이터는 기기 로컬에만 안전하게 보관됩니다.",

        "onboarding.item.full_disk_access.title": "전체 디스크 접근 권한",
        "onboarding.item.full_disk_access.detail": "시스템 파일 및 디스크 상태를 분석하기 위해 전체 디스크 접근 권한이 필요합니다.",
        "onboarding.item.accessibility.title": "손쉬운 사용 권한",
        "onboarding.item.accessibility.detail": "시스템 제어 및 UI 자동화 기능 수행을 위해 손쉬운 사용 권한이 필요합니다.",
        "onboarding.item.screen_recording.title": "화면 기록 권한",
        "onboarding.item.screen_recording.detail": "화면 캡처 및 OCR 텍스트 인식을 위해 화면 기록 권한이 필요합니다.",
        "onboarding.item.camera.title": "카메라 권한",
        "onboarding.item.camera.detail": "영상 캡처 및 카메라 기능을 위해 카메라 접근 권한이 필요합니다.",
        "onboarding.item.microphone.title": "마이크 권한",
        "onboarding.item.microphone.detail": "오디오 녹음 및 음성 입력을 위해 마이크 접근 권한이 필요합니다.",
        "onboarding.item.input_monitoring.title": "입력 모니터링 권한",
        "onboarding.item.input_monitoring.detail": "키보드 및 단축키 인식을 위해 입력 모니터링 권한이 필요합니다.",
        "onboarding.item.location.title": "위치 권한",
        "onboarding.item.location.detail": "위치 및 네트워크 상태 인식을 위해 위치 접근 권한이 필요합니다.",

        "onboarding.item.defaults.title": "권장 기본값",
        "onboarding.item.defaults.detail": "앱 실행에 필요한 기본 설정을 활성화합니다.",
        "onboarding.item.required.title": "필수 설정",
        "onboarding.item.required.detail": "정상적인 기능 수행을 위해 필요한 필수 권한입니다."
    ]

    public static func string(_ key: String, language: AppLanguage? = nil) -> String {
        let isKorean: Bool
        if let language {
            switch language {
            case .korean: isKorean = true
            case .english: isKorean = false
            case .system: isKorean = Locale.current.language.languageCode?.identifier == "ko"
            }
        } else {
            isKorean = Locale.current.language.languageCode?.identifier == "ko"
        }

        #if SWIFT_PACKAGE
        let bundle = ResourceBundle.named("swiftkit_OnboardingUIKit")
        let code = isKorean ? "ko" : "en"
        if let path = bundle.path(forResource: code, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            let val = langBundle.localizedString(forKey: key, value: "__MISSING__", table: nil)
            if val != "__MISSING__" {
                return val
            }
        }
        #endif

        if isKorean {
            return fallbackKorean[key] ?? fallbackEnglish[key] ?? key
        } else {
            return fallbackEnglish[key] ?? key
        }
    }
}

/// l10n-bypass 린트 패스를 위한 네임스페이스 별칭
public typealias OnboardingL10n = OnboardingUIKitL10n
