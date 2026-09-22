import AppKit
import Foundation
@_exported import PermissionCore

// 화면을 **여는** 동작만 여기 남는다(AppKit 필요). 앵커·문구는 PermissionCore 에 있다 —
// SystemExtension 이 쓰는 것과 같은 분업이다.
public extension LoginItemsSettings {
    /// "로그인 항목 및 확장 프로그램" 화면을 연다. 실제 토글은 사용자가 거기서 한다.
    ///
    /// - Returns: 어느 후보로 열렸는지. 전부 실패하면 `nil` — 그때 호출측은
    ///   `manualNavigationHint(language:)` 를 사람에게 보여야 한다.
    @MainActor @discardableResult
    static func openSettings(
        open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> String? {
        for candidate in settingsURLCandidates {
            guard let url = URL(string: candidate) else { continue }
            if open(url) { return candidate }
        }
        return nil
    }
}
