import SwiftUI
import simd

/// 3D 공간 상의 단일 구체 노드를 표현하는 순수 UI 기하학 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 DTO입니다.
public struct SpatialNode3D: Identifiable, Sendable, Equatable {
    public let id: String
    public var position: SIMD3<Float>
    public var radius: Float
    public var color: Color
    public var glowIntensity: Float
    public var pulseSpeed: Float
    public var label: String?

    public init(
        id: String,
        position: SIMD3<Float>,
        radius: Float = 1.0,
        color: Color = .blue,
        glowIntensity: Float = 0.0,
        pulseSpeed: Float = 0.0,
        label: String? = nil
    ) {
        self.id = id
        self.position = position
        self.radius = radius
        self.color = color
        self.glowIntensity = glowIntensity
        self.pulseSpeed = pulseSpeed
        self.label = label
    }
}
