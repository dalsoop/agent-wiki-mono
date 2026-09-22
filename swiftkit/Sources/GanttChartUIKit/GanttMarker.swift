import SwiftUI

/// 타임라인 상의 특정 틱(Tick) 시점에 발생하는 이벤트나 이정표를 표시하는 마커 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 DTO입니다.
public struct GanttMarker: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public var tick: Int64
    public var label: String
    public var symbol: String        // SF Symbols 이름 또는 기호 텍스트 (예: "flag.fill", "diamond.fill")
    public var color: Color
    public var trackId: String?

    public init(
        id: String,
        tick: Int64,
        label: String,
        symbol: String = "flag.fill",
        color: Color = .orange,
        trackId: String? = nil
    ) {
        self.id = id
        self.tick = tick
        self.label = label
        self.symbol = symbol
        self.color = color
        self.trackId = trackId
    }
}
