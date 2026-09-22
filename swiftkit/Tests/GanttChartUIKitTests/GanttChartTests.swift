import XCTest
import SwiftUI
@testable import GanttChartUIKit

final class GanttChartTests: XCTestCase {

    func testGanttTrackInitialization() {
        let track = GanttTrack(
            id: "track-1",
            title: "Pipeline Alpha",
            order: 2,
            height: 50.0
        )

        XCTAssertEqual(track.id, "track-1")
        XCTAssertEqual(track.title, "Pipeline Alpha")
        XCTAssertEqual(track.order, 2)
        XCTAssertEqual(track.height, 50.0)
    }

    func testGanttBarDurationAndProperties() {
        let bar = GanttBar(
            id: "bar-1",
            trackId: "track-1",
            startTick: 10,
            endTick: 35,
            label: "Execution Phase",
            fillStyle: .striped,
            tintColor: .orange,
            progress: 0.65
        )

        XCTAssertEqual(bar.id, "bar-1")
        XCTAssertEqual(bar.trackId, "track-1")
        XCTAssertEqual(bar.startTick, 10)
        XCTAssertEqual(bar.endTick, 35)
        XCTAssertEqual(bar.durationTicks, 25)
        XCTAssertEqual(bar.label, "Execution Phase")
        XCTAssertEqual(bar.fillStyle, .striped)
        XCTAssertEqual(bar.tintColor, .orange)
        XCTAssertEqual(bar.progress, 0.65)
    }

    func testGanttBarEndTickValidation() {
        let bar = GanttBar(
            id: "bar-invalid",
            trackId: "track-1",
            startTick: 50,
            endTick: 20,
            label: "Correction Test"
        )

        XCTAssertEqual(bar.startTick, 50)
        XCTAssertEqual(bar.endTick, 50)
        XCTAssertEqual(bar.durationTicks, 0)
    }

    func testGanttMarkerInitialization() {
        let marker = GanttMarker(
            id: "m-1",
            tick: 42,
            label: "Milestone Reached",
            symbol: "star.fill",
            color: .yellow
        )

        XCTAssertEqual(marker.id, "m-1")
        XCTAssertEqual(marker.tick, 42)
        XCTAssertEqual(marker.label, "Milestone Reached")
        XCTAssertEqual(marker.symbol, "star.fill")
        XCTAssertEqual(marker.color, .yellow)
    }

    func testStripedPatternPathGeneration() {
        let pattern = StripedPattern(spacing: 10.0)
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let path = pattern.path(in: rect)

        XCTAssertFalse(path.isEmpty)
        XCTAssertTrue(path.boundingRect.width > 0)
    }

    @MainActor
    func testGanttChartViewInitialization() {
        let tracks = [
            GanttTrack(id: "t2", title: "Second Track", order: 2),
            GanttTrack(id: "t1", title: "First Track", order: 1)
        ]
        let bars = [
            GanttBar(id: "b1", trackId: "t1", startTick: 0, endTick: 20, label: "Job 1")
        ]
        let markers = [
            GanttMarker(id: "m1", tick: 15, label: "Check")
        ]

        let view = GanttChartView(
            tracks: tracks,
            bars: bars,
            markers: markers,
            currentTick: 12
        )

        XCTAssertEqual(view.tracks.first?.id, "t1")
        XCTAssertEqual(view.tracks.last?.id, "t2")
        XCTAssertEqual(view.bars.count, 1)
        XCTAssertEqual(view.markers.count, 1)
        XCTAssertEqual(view.currentTick, 12)
    }

    @MainActor
    func testGanttCausalLinkAndEventTrack() {
        let stimulusTrack = GanttTrack(
            id: "stimulus",
            title: "Stimulus Track",
            order: 0,
            isEventTrack: true
        )
        let responseTrack = GanttTrack(
            id: "response",
            title: "Response Track",
            order: 1
        )

        let barStim = GanttBar(id: "b-stim", trackId: "stimulus", startTick: 10, endTick: 15, label: "Press")
        let barSurge = GanttBar(id: "b-surge", trackId: "response", startTick: 15, endTick: 30, label: "Dopamine Surge")

        let link = GanttCausalLink(
            id: "causal-1",
            fromBarId: "b-stim",
            toBarId: "b-surge",
            label: "Trigger",
            color: .yellow
        )

        let marker = GanttMarker(
            id: "m-press",
            tick: 10,
            label: "Press Event",
            symbol: "hand.tap.fill",
            color: .yellow,
            trackId: "stimulus"
        )

        let view = GanttChartView(
            tracks: [stimulusTrack, responseTrack],
            bars: [barStim, barSurge],
            markers: [marker],
            causalLinks: [link],
            currentTick: 20
        )

        XCTAssertTrue(view.tracks[0].isEventTrack)
        XCTAssertFalse(view.tracks[1].isEventTrack)
        XCTAssertEqual(view.causalLinks.count, 1)
        XCTAssertEqual(view.causalLinks[0].fromBarId, "b-stim")
        XCTAssertEqual(view.causalLinks[0].toBarId, "b-surge")
        XCTAssertEqual(view.markers[0].trackId, "stimulus")
    }
}
