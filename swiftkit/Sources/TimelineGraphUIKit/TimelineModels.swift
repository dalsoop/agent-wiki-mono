import Foundation

/// 시계열 트랙 상의 구간 세그먼트 (순수 기하/시간 모델)
public struct TimelineSegment: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var trackID: String
    public var startDate: Date
    public var endDate: Date
    public var label: String
    public var tintHex: String?

    public init(
        id: String,
        trackID: String,
        startDate: Date,
        endDate: Date,
        label: String,
        tintHex: String? = nil
    ) {
        self.id = id
        self.trackID = trackID
        self.startDate = min(startDate, endDate)
        self.endDate = max(startDate, endDate)
        self.label = label
        self.tintHex = tintHex
    }

    public var duration: TimeInterval {
        endDate.timeIntervalSince(startDate)
    }

    public func contains(date: Date) -> Bool {
        date >= startDate && date <= endDate
    }
}

/// 시계열 트랙 상의 특정 시점 마커
public struct TimelineMarker: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var trackID: String?
    public var date: Date
    public var label: String
    public var tintHex: String?

    public init(
        id: String,
        trackID: String? = nil,
        date: Date,
        label: String,
        tintHex: String? = nil
    ) {
        self.id = id
        self.trackID = trackID
        self.date = date
        self.label = label
        self.tintHex = tintHex
    }
}

/// 시계열 단일 트랙
public struct TimelineTrack: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var title: String
    public var segments: [TimelineSegment]
    public var markers: [TimelineMarker]

    public init(
        id: String,
        title: String,
        segments: [TimelineSegment] = [],
        markers: [TimelineMarker] = []
    ) {
        self.id = id
        self.title = title
        self.segments = segments
        self.markers = markers
    }
}
