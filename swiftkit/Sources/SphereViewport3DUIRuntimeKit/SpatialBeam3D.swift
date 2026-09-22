import SwiftUI

public enum SpatialBeamKind: String, Sendable, Equatable, CaseIterable {
    case neural = "neural"               // 신경망: 빠른 전기 펄스 스파이크 (Cyan/Violet)
    case circulatory = "circulatory"     // 혈관계: 심박 동기화 혈류 맥동 (Red/Pink)
    case endocrine = "endocrine"         // 호르몬: 부드러운 화학 신호 흐름 (Gold/Amber)
    case generic = "generic"             // 기본 연결선
}

/// 3D 공간 상에서 펄스(에너지를 싣고 질주하는 동적 신호)를 표현하는 순수 기하학 모델
public struct SpatialPulse3D: Sendable, Equatable, Identifiable {
    public var id: String
    public var birthTime: Double         // 발생 절대 시각 (초 단위)
    public var duration: Double          // 전체 수송 소요 시간 (초 단위)
    public var magnitude: Double         // 0.0 ~ 1.0 강도
    public var color: Color?

    public init(
        id: String = UUID().uuidString,
        birthTime: Double,
        duration: Double,
        magnitude: Double = 1.0,
        color: Color? = nil
    ) {
        self.id = id
        self.birthTime = birthTime
        self.duration = duration
        self.magnitude = magnitude
        self.color = color
    }
}

/// 3D 공간 상에서 두 노드 간의 빔(연결 파이프/광선)을 표현하는 순수 UI 기하학 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 DTO입니다.
public struct SpatialBeam3D: Identifiable, Sendable, Equatable {
    public let id: String
    public let fromNodeId: String
    public let toNodeId: String
    public var thickness: Float
    public var color: Color
    public var particleFlowRate: Float
    public var networkKind: SpatialBeamKind
    public var pulseSpeed: Float
    public var intensity: Float
    public var pulses: [SpatialPulse3D]

    public init(
        id: String,
        fromNodeId: String,
        toNodeId: String,
        thickness: Float = 0.05,
        color: Color = .cyan,
        particleFlowRate: Float = 0.0,
        networkKind: SpatialBeamKind = .generic,
        pulseSpeed: Float = 1.0,
        intensity: Float = 1.0,
        pulses: [SpatialPulse3D] = []
    ) {
        self.id = id
        self.fromNodeId = fromNodeId
        self.toNodeId = toNodeId
        self.thickness = thickness
        self.color = color
        self.particleFlowRate = particleFlowRate
        self.networkKind = networkKind
        self.pulseSpeed = pulseSpeed
        self.intensity = intensity
        self.pulses = pulses
    }
}
