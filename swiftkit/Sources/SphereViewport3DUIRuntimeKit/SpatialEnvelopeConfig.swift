import SwiftUI

/// 3D 클러스터를 감싸는 반투명 외피(Envelope) 메쉬의 시각 및 물리 거동 설정 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 DTO입니다.
public struct SpatialEnvelopeConfig: Sendable, Equatable {
    public var opacity: Float
    public var baseColor: Color
    public var breathingRate: Float
    public var deformFactor: Float

    public init(
        opacity: Float = 0.2,
        baseColor: Color = .white,
        breathingRate: Float = 0.5,
        deformFactor: Float = 0.1
    ) {
        self.opacity = opacity
        self.baseColor = baseColor
        self.breathingRate = breathingRate
        self.deformFactor = deformFactor
    }
}
