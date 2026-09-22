import Foundation

/// 마찰 드래그 제스처 진행 중의 물리적 상태값(속도, 누적 거리, 지속 시간)을 담는 모델입니다.
public struct FrictionDragValue: Sendable, Equatable {
    /// 현재 드래그 순간 속도 (points/sec)
    public var velocity: Double
    /// 제스처 시작부터 누적된 이동 거리 (points)
    public var cumulativeDistance: Double
    /// 제스처 경과 시간 (seconds)
    public var duration: TimeInterval

    public init(
        velocity: Double,
        cumulativeDistance: Double,
        duration: TimeInterval
    ) {
        self.velocity = velocity
        self.cumulativeDistance = cumulativeDistance
        self.duration = duration
    }
}
