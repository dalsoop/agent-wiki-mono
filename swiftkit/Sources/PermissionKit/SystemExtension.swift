import AppKit
import Foundation
import LocalizationKit
@_exported import PermissionCore

// 화면을 **여는** 동작만 여기 남는다(AppKit 필요). 판정·문구는 PermissionCore 에 있고,
// `@_exported import` 로 기존 `import PermissionKit` 사용처는 그대로 컴파일된다.
public extension SystemExtension {
    /// 네트워크 확장 목록까지 연다. 실제 승인은 사용자가 거기서 한다.
    ///
    /// - Returns: 어느 후보로 열렸는지. 전부 실패하면 `nil` — 호출측은 그때 폴백 안내
    ///   (`manualNavigationHint`)를 사람에게 보여야 한다. 예전 판은 반환값이 없어
    ///   "열렸는지 아닌지" 를 아무도 몰랐고, 안 열려도 앱은 조용했다.
    @MainActor @discardableResult
    func openSettings(
        open: (URL) -> Bool = { NSWorkspace.shared.open($0) }
    ) -> String? {
        for candidate in Self.settingsURLCandidates {
            guard let url = URL(string: candidate) else { continue }
            if open(url) { return candidate }
        }
        return nil
    }
}
