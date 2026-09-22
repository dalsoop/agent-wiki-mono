import Foundation
import LocalizationKit

/// "로그인 항목 및 확장 프로그램" 설정 화면의 딥링크 SSOT.
///
/// **왜 여기 있나.** 앱은 로그인 항목을 코드로 끄지 못한다 — `SMAppService` 는 자기
/// 번들 전용이고 BTM 저장소(`/var/db/com.apple.backgroundtaskmanagement`)는 root 소유다.
/// 그래서 함대 앱이 할 수 있는 최선은 **사용자를 정확한 화면에 데려다 놓는 것**이고,
/// 그러면 앱마다 앵커 문자열을 박게 된다. macOS 가 앵커를 바꾸는 날 함대가 조용히
/// 갈라지지 않도록 한 곳에 모은다.
///
/// 여는 동작(AppKit)은 `PermissionKit` 쪽 확장에 있다 — 여기는 Foundation 만 쓴다.
/// CLI 도 문자열·안내 문구를 그대로 읽을 수 있어야 하기 때문이다.
public enum LoginItemsSettings: Sendable {
    /// 정규 앵커. 앱은 이 상수를 쓰고 문자열을 다시 적지 않는다.
    public static let settingsURLString =
        "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"

    /// 앞이 더 깊다 — 안 열리면 한 단계씩 얕은 화면으로 물러난다.
    ///
    /// 하나만 쓰면 안 된다: macOS 버전에 따라 무시되는 앵커가 달라서, 단일 앵커는
    /// "버튼을 눌렀는데 아무 화면도 안 뜬다" 는 회귀를 낸다(`SystemExtension` 이
    /// 같은 이유로 후보 목록을 갖고 있다).
    public static let settingsURLCandidates: [String] = [
        settingsURLString,
        "x-apple.systempreferences:com.apple.ExtensionsPreferences",
        "x-apple.systempreferences:com.apple.preference.general",
    ]

    /// 딥링크가 통째로 실패했을 때 사람이 손으로 갈 경로.
    ///
    /// 호출측은 `openSettings()` 가 `nil` 을 돌려줬을 때 이 문구를 보여준다 —
    /// 안 열렸는데 앱이 조용하면 사용자는 앱이 고장 났다고 읽는다.
    public static func manualNavigationHint(language: AppLanguage = .system) -> String {
        SystemExtension.isKorean(language)
            ? "설정이 자동으로 열리지 않았습니다 — 시스템 설정 › 일반 › 로그인 항목 및 확장 프로그램 에서 직접 확인하세요."
            : "Settings did not open automatically — open System Settings › General › Login Items & Extensions yourself."
    }
}
