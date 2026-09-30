import Foundation
import Observation
import SwiftUI

/// Reader / Studio / monlith 가 공유하는 원장 GUI 세션.
/// `LedgerModel` 은 모듈 내부에 두고, 외부는 이 타입 + Root/Settings 뷰만 본다.
@MainActor
@Observable
public final class AgentWikiSession {
    /// 고정 surface (`reader` | `studio` | nil=파일/env 따름).
    public let fixedSurface: String?

    var model = LedgerModel()

    public init(fixedSurface: String? = nil) {
        self.fixedSurface = fixedSurface
        if let fixedSurface {
            try? LedgerAreaOwnership.writeSurfaceFile(fixedSurface)
        }
        applySurfaceClamp()
    }

    /// surface 파일/env 또는 fixedSurface 에 맞춰 영역 클램프.
    public func applySurfaceClamp() {
        let next = LedgerAreaOwnership.clampArea(model.area, surface: fixedSurface)
        if next != model.area {
            model.area = next
        }
    }

    public func refresh() {
        model.refresh()
    }

    public var windowTitle: String {
        LedgerAreaOwnership.windowTitle(surface: fixedSurface)
    }
}
