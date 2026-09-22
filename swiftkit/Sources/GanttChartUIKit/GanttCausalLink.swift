import SwiftUI

/// 간트 차트 내에서 선행 이벤트(예: 자극)와 후속 반응(예: 도파민 서지, 불응기) 간의
/// 인과 관계(Causal Dependency)를 표현하는 순수 UI 기하학 모델입니다.
public struct GanttCausalLink: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let fromBarId: String
    public let toBarId: String
    public var label: String?
    public var color: Color

    public init(
        id: String,
        fromBarId: String,
        toBarId: String,
        label: String? = nil,
        color: Color = .yellow
    ) {
        self.id = id
        self.fromBarId = fromBarId
        self.toBarId = toBarId
        self.label = label
        self.color = color
    }
}
