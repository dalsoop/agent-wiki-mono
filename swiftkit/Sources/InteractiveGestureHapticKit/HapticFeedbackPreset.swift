import Foundation

/// 물리 기반 햅틱 피드백의 프리셋을 정의하는 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 햅틱 패턴입니다.
public enum HapticFeedbackPreset: Sendable, Equatable, Hashable {
    /// 주기적 미세 펄스 (진동수 Hz, 강도 0.0 ~ 1.0)
    case periodicMicroPulse(frequencyHz: Double, intensity: Double)
    /// 경량 충격 햅틱
    case impactLight
    /// 중량 충격 햅틱
    case impactHeavy
    /// 순간적 정밀 클릭 햅틱 (노드 피킹, 경계 도달 등)
    case transientClick

    /// 도메인 편의 별칭: 부드러운 저주파 진동
    public static func gentleRumble(intensity: Double = 0.5) -> HapticFeedbackPreset {
        .periodicMicroPulse(frequencyHz: 25.0, intensity: intensity)
    }
}
