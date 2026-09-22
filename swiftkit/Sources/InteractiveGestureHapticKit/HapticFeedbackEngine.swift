import Foundation

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// 물리적 햅틱 피드백을 시스템 하드웨어로 전달하는 전용 정적 엔진입니다.
/// macOS의 `NSHapticFeedbackManager` 및 iOS의 `UIImpactFeedbackGenerator`를 추상화합니다.
public enum HapticFeedbackEngine {

    /// 지정된 햅틱 프리셋에 따른 촉각 피드백을 발생시킵니다.
    @MainActor
    public static func trigger(_ preset: HapticFeedbackPreset) {
        #if os(macOS)
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch preset {
        case .transientClick:
            performer.perform(.alignment, performanceTime: .now)
        case .impactLight:
            performer.perform(.levelChange, performanceTime: .now)
        case .impactHeavy:
            performer.perform(.generic, performanceTime: .now)
        case .periodicMicroPulse(_, let intensity):
            if intensity >= 0.7 {
                performer.perform(.generic, performanceTime: .now)
            } else if intensity >= 0.3 {
                performer.perform(.levelChange, performanceTime: .now)
            } else {
                performer.perform(.alignment, performanceTime: .now)
            }
        }
        #elseif os(iOS)
        switch preset {
        case .transientClick:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .impactLight:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.prepare()
            generator.impactOccurred()
        case .impactHeavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.prepare()
            generator.impactOccurred()
        case .periodicMicroPulse(_, let intensity):
            let style: UIImpactFeedbackGenerator.FeedbackStyle = intensity >= 0.6 ? .heavy : (intensity >= 0.3 ? .medium : .light)
            let generator = UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            generator.impactOccurred(intensity: CGFloat(max(0.1, min(1.0, intensity))))
        }
        #endif
    }
}
