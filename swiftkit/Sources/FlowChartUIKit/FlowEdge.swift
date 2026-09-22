import SwiftUI

/// 흐름 다이어그램에서 노드 간의 연결과 흐름을 나타내는 순수 UI 간선 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 DTO입니다.
public struct FlowEdge: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let sourceId: String
    public let targetId: String
    public var bandwidth: Double     // 선의 굵기
    public var flowRate: Double      // 파티클 흐름 속도
    public var color: Color
    public var isBidirectional: Bool
    public var particleCount: Int    // 흐르는 파티클 개수
    public var label: String?

    public init(
        id: String,
        sourceId: String,
        targetId: String,
        bandwidth: Double = 2.0,
        flowRate: Double = 0.5,
        color: Color = Color.secondary.opacity(0.6),
        isBidirectional: Bool = false,
        particleCount: Int = 3,
        label: String? = nil
    ) {
        self.id = id
        self.sourceId = sourceId
        self.targetId = targetId
        self.bandwidth = bandwidth
        self.flowRate = flowRate
        self.color = color
        self.isBidirectional = isBidirectional
        self.particleCount = particleCount
        self.label = label
    }
}
