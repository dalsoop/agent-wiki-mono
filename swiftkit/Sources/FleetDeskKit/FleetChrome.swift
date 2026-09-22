import Foundation

/// 함대 GUI 가 사는 자리. `package-identity.json` 의 `chrome` 과 같은 값이다.
///
/// - `dock`: 창 앱. 시스템 Dock 아이콘이 생길 수 있고, 책상 숨김 정책을 탄다.
/// - `menubar`: 상단 메뉴바 상주. `LSUIElement` 로 Dock 에 안 뜬다.
public enum FleetChrome: String, Codable, Sendable, CaseIterable {
    case dock
    case menubar

    public static let identityKey = "chrome"
}
