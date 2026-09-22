import SwiftUI

/// 흐름 다이어그램에서 상태 또는 객체를 표현하는 순수 UI 노드 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 DTO입니다.
public struct FlowNode: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public var label: String
    public var coordinate: CGPoint
    public var statusColor: Color
    public var badge: String?
    public var isPulsing: Bool
    public var radius: CGFloat
    public var subtitle: String?

    public init(
        id: String,
        label: String,
        coordinate: CGPoint,
        statusColor: Color = .blue,
        badge: String? = nil,
        isPulsing: Bool = false,
        radius: CGFloat = 26.0,
        subtitle: String? = nil
    ) {
        self.id = id
        self.label = label
        self.coordinate = coordinate
        self.statusColor = statusColor
        self.badge = badge
        self.isPulsing = isPulsing
        self.radius = radius
        self.subtitle = subtitle
    }
}
