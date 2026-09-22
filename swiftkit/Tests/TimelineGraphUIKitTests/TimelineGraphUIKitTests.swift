import Foundation
import TimelineGraphUIKit
import Testing

@Suite struct TimelineGraphUIKitTests {
    @Test func timelineSegmentCalculatesDurationAndInclusion() {
        let base = Date()
        let start = base
        let end = base.addingTimeInterval(3600) // 1시간

        let segment = TimelineSegment(
            id: "seg-1",
            trackID: "track-1",
            startDate: start,
            endDate: end,
            label: "작업 구간"
        )

        #expect(segment.duration == 3600)
        #expect(segment.contains(date: base.addingTimeInterval(1800))) // 중간 시점 포함
        #expect(!segment.contains(date: base.addingTimeInterval(-10))) // 시작 전 미포함
        #expect(!segment.contains(date: base.addingTimeInterval(3610))) // 종료 후 미포함
    }

    @Test func timelineTrackCollectsSegmentsAndMarkers() {
        let base = Date()
        let seg = TimelineSegment(id: "s1", trackID: "t1", startDate: base, endDate: base.addingTimeInterval(60), label: "S")
        let marker = TimelineMarker(id: "m1", trackID: "t1", date: base.addingTimeInterval(30), label: "M")

        let track = TimelineTrack(id: "t1", title: "하네스 세션", segments: [seg], markers: [marker])
        #expect(track.segments.count == 1)
        #expect(track.markers.count == 1)
        #expect(track.title == "하네스 세션")
    }
}
