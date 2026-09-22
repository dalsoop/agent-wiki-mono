import SwiftUI

/// 마우스 호버(Hover) 시점에 물리적 햅틱을 트리거하는 뷰 모디파이어입니다.
public struct HapticHoverModifier: ViewModifier {
    public var preset: HapticFeedbackPreset

    public init(preset: HapticFeedbackPreset) {
        self.preset = preset
    }

    public func body(content: Content) -> some View {
        content.onHover { isHovered in
            if isHovered {
                HapticFeedbackEngine.trigger(preset)
            }
        }
    }
}

extension View {
    /// 뷰 위로 마우스 커서 진입 시 햅틱 피드백을 발생시킵니다.
    public func hapticFeedbackOnHover(
        _ preset: HapticFeedbackPreset
    ) -> some View {
        self.modifier(HapticHoverModifier(preset: preset))
    }
}
