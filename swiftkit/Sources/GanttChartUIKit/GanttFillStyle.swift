import Foundation

/// 간트 바의 시각적 채우기 스타일을 지정하는 열거형입니다.
public enum GanttFillStyle: String, Sendable, Codable, CaseIterable, Equatable, Hashable {
    case solid
    case striped
    case faded
}
