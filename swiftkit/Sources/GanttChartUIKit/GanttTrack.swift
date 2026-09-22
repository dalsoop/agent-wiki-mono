import Foundation

/// 간트 차트의 수평 타임라인 레인(Track)을 정의하는 순수 UI 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 DTO입니다.
public struct GanttTrack: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public var title: String
    public var order: Int
    public var height: CGFloat
    public var isEventTrack: Bool

    public init(
        id: String,
        title: String,
        order: Int = 0,
        height: CGFloat = 40.0,
        isEventTrack: Bool = false
    ) {
        self.id = id
        self.title = title
        self.order = order
        self.height = height
        self.isEventTrack = isEventTrack
    }
}
