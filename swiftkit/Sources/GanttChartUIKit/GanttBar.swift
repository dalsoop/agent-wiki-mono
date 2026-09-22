import SwiftUI

/// 간트 차트의 특정 트랙 위에서 기간(시작 틱 ~ 종료 틱)을 점유하는 바(Bar) 모델입니다.
/// 특정 비즈니스 도메인에 결합되지 않는 순수 DTO입니다.
public struct GanttBar: Identifiable, Sendable, Equatable, Hashable {
    public let id: String
    public let trackId: String
    public var startTick: Int64
    public var endTick: Int64
    public var label: String
    public var fillStyle: GanttFillStyle
    public var tintColor: Color
    public var progress: Double?      // 0.0 ~ 1.0 (옵션 진행도)

    public var durationTicks: Int64 {
        max(0, endTick - startTick)
    }

    public init(
        id: String,
        trackId: String,
        startTick: Int64,
        endTick: Int64,
        label: String,
        fillStyle: GanttFillStyle = .solid,
        tintColor: Color = .blue,
        progress: Double? = nil
    ) {
        self.id = id
        self.trackId = trackId
        self.startTick = startTick
        self.endTick = max(startTick, endTick)
        self.label = label
        self.fillStyle = fillStyle
        self.tintColor = tintColor
        self.progress = progress
    }
}
