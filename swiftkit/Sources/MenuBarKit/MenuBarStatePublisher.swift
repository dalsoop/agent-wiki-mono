import Foundation
import StateMirrorKit

/// 메뉴바 앱이 자기 상태를 StateMirror 로 게시하는 표준 계약.
///
/// `MenuBarRefreshController(afterRefresh:)` 훅에서 이 프로토콜을 이행한 모델의
/// `publishMenuBarState()` 를 부르면, 스크린샷 없이 CLI 로 앱 데이터를 읽는
/// 공통 채널(`~/.swift-app-state/<앱>.json`)에 매 갱신마다 최신 스냅샷이 실린다.
@MainActor
public protocol MenuBarStatePublishing: AnyObject {
    /// StateMirror 파일명이 될 앱 이름(예: "TokenBar").
    var menuBarStateAppName: String { get }
    /// 게시할 상태 스냅샷([String: Any] — 비-Codable 편의).
    func menuBarStateSnapshot() -> [String: Any]
}

extension MenuBarStatePublishing {
    /// 현재 스냅샷을 StateMirror 로 게시한다. `afterRefresh` 훅에서 호출.
    public func publishMenuBarState() {
        StateMirror.publishJSONObject(app: menuBarStateAppName, menuBarStateSnapshot())
    }
}
