import SwiftUI

public struct GanttChartView: View {
    public let tracks: [GanttTrack]
    public let bars: [GanttBar]
    public let markers: [GanttMarker]
    public let causalLinks: [GanttCausalLink]
    public var currentTick: Int64
    public var visibleRange: ClosedRange<Int64>?

    public init(
        tracks: [GanttTrack],
        bars: [GanttBar],
        markers: [GanttMarker] = [],
        causalLinks: [GanttCausalLink] = [],
        currentTick: Int64 = 0,
        visibleRange: ClosedRange<Int64>? = nil
    ) {
        self.tracks = tracks.sorted { $0.order < $1.order }
        self.bars = bars
        self.markers = markers
        self.causalLinks = causalLinks
        self.currentTick = currentTick
        self.visibleRange = visibleRange
    }

    private var effectiveRange: ClosedRange<Int64> {
        if let visibleRange {
            return visibleRange
        }
        let allTicks = bars.flatMap { [$0.startTick, $0.endTick] } + markers.map(\.tick) + [currentTick]
        let minT = allTicks.min() ?? 0
        let maxT = allTicks.max() ?? 100
        return minT...(max(maxT, minT + 20))
    }

    public var body: some View {
        GeometryReader { proxy in
            let range = effectiveRange
            let span = max(1, range.upperBound - range.lowerBound)
            let headerWidth: CGFloat = 110.0
            let timelineWidth = max(proxy.size.width - headerWidth, 100)

            HStack(spacing: 0) {
                trackHeaderColumn(headerWidth: headerWidth)
                Divider()
                timelineArea(span: span, range: range, timelineWidth: timelineWidth)
            }
        }
    }

    private func trackHeaderColumn(headerWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text("Track / Time")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: headerWidth, height: 28, alignment: .leading)
                .padding(.horizontal, 6)
                .background(Color.secondary.opacity(0.1))

            Divider()

            ForEach(tracks) { track in
                HStack(spacing: 6) {
                    if track.isEventTrack {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                    Text(track.title)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .frame(minWidth: 0)
                        .foregroundStyle(track.isEventTrack ? .yellow : .primary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 38)
                .background(track.isEventTrack ? Color.yellow.opacity(0.1) : Color.secondary.opacity(0.04))
                Divider()
            }
            Spacer(minLength: 0)
        }
        .frame(width: headerWidth)
        .background(Color.secondary.opacity(0.05))
    }

    private func timelineArea(span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            timelineRuler(span: span, range: range, timelineWidth: timelineWidth)
            Divider()
            timelineCanvas(span: span, range: range, timelineWidth: timelineWidth)
        }
    }

    private func timelineRuler(span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Color.secondary.opacity(0.08))
                .frame(height: 28)

            let tickSteps = 5
            ForEach(0...tickSteps, id: \.self) { step in
                let ratio = Double(step) / Double(tickSteps)
                let tickVal = range.lowerBound + Int64(Double(span) * ratio)
                let xPos = timelineWidth * CGFloat(ratio)

                Text("\(tickVal)t")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .position(x: xPos, y: 14)
            }
        }
        .frame(height: 28)
    }

    private func timelineCanvas(span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            renderTrackBackgrounds()
            renderCausalLinks(span: span, range: range, timelineWidth: timelineWidth)
            renderBars(span: span, range: range, timelineWidth: timelineWidth)
            renderNowLine(span: span, range: range, timelineWidth: timelineWidth)
            renderMarkers(span: span, range: range, timelineWidth: timelineWidth)
        }
    }

    private func renderTrackBackgrounds() -> some View {
        VStack(spacing: 0) {
            ForEach(tracks) { track in
                Rectangle()
                    .fill(track.isEventTrack ? Color.yellow.opacity(0.06) : Color.clear)
                    .frame(height: 38)
                Divider()
            }
            Spacer(minLength: 0)
        }
    }

    private func renderBars(span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        ForEach(tracks.indices, id: \.self) { trackIndex in
            let track = tracks[trackIndex]
            let trackBars = bars.filter { $0.trackId == track.id }
            let yOffset = CGFloat(trackIndex) * 39.0 + 6.0

            ForEach(trackBars) { bar in
                renderBar(bar, range: range, span: span, timelineWidth: timelineWidth, yOffset: yOffset)
            }
        }
    }

    private func renderNowLine(span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        let nowNorm = CGFloat(currentTick - range.lowerBound) / CGFloat(span)
        let inRange = nowNorm >= 0 && nowNorm <= 1.0
        return Group {
            if inRange {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: nowNorm * timelineWidth)
            }
        }
    }

    private func renderMarkers(span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        ForEach(markers) { marker in
            renderSingleMarker(marker, span: span, range: range, timelineWidth: timelineWidth)
        }
    }

    @ViewBuilder
    private func renderSingleMarker(_ marker: GanttMarker, span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        let mNorm = CGFloat(marker.tick - range.lowerBound) / CGFloat(span)
        if mNorm >= 0 && mNorm <= 1.0 {
            let mx = mNorm * timelineWidth
            if let tId = marker.trackId, let tIdx = tracks.firstIndex(where: { $0.id == tId }) {
                let yOffset = CGFloat(tIdx) * 39.0 + 4.0
                HStack(spacing: 3) {
                    Image(systemName: marker.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(marker.color)
                    Text(marker.label)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(marker.color)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(marker.color.opacity(0.2))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(marker.color.opacity(0.6), lineWidth: 1))
                .offset(x: min(max(mx - 10, 0), timelineWidth - 50), y: yOffset)
            } else {
                VStack(spacing: 1) {
                    Image(systemName: marker.symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(marker.color)
                    Text(marker.label)
                        .font(.system(size: 8))
                        .foregroundStyle(marker.color)
                }
                .offset(x: mx - 10, y: 2)
            }
        }
    }

    private func renderCausalLinks(span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        ForEach(causalLinks) { link in
            renderSingleCausalLink(link, span: span, range: range, timelineWidth: timelineWidth)
        }
    }

    @ViewBuilder
    private func renderSingleCausalLink(_ link: GanttCausalLink, span: Int64, range: ClosedRange<Int64>, timelineWidth: CGFloat) -> some View {
        if let fromBar = bars.first(where: { $0.id == link.fromBarId }),
           let toBar = bars.first(where: { $0.id == link.toBarId }),
           let fromIdx = tracks.firstIndex(where: { $0.id == fromBar.trackId }),
           let toIdx = tracks.firstIndex(where: { $0.id == toBar.trackId }) {

            let fromNorm = CGFloat(fromBar.endTick - range.lowerBound) / CGFloat(span)
            let toNorm = CGFloat(toBar.startTick - range.lowerBound) / CGFloat(span)

            let fromX = min(max(fromNorm * timelineWidth, 0), timelineWidth)
            let fromY = CGFloat(fromIdx) * 39.0 + 19.0
            let toX = min(max(toNorm * timelineWidth, 0), timelineWidth)
            let toY = CGFloat(toIdx) * 39.0 + 19.0
            let midX = (fromX + toX) / 2.0

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: fromX, y: fromY))
                    path.addCurve(
                        to: CGPoint(x: toX, y: toY),
                        control1: CGPoint(x: midX, y: fromY),
                        control2: CGPoint(x: midX, y: toY)
                    )
                }
                .stroke(
                    link.color.opacity(0.85),
                    style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round, dash: [4, 3])
                )

                Path { p in
                    p.move(to: CGPoint(x: max(toX - 5, 0), y: toY - 4))
                    p.addLine(to: CGPoint(x: toX, y: toY))
                    p.addLine(to: CGPoint(x: max(toX - 5, 0), y: toY + 4))
                }
                .stroke(link.color, style: StrokeStyle(lineWidth: 2.0, lineCap: .round))

                if let label = link.label {
                    Text(label)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(link.color)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.black.opacity(0.7))
                        .clipShape(Capsule())
                        .position(x: midX, y: (fromY + toY) / 2.0)
                }
            }
        }
    }

    private func renderBar(_ bar: GanttBar, range: ClosedRange<Int64>, span: Int64, timelineWidth: CGFloat, yOffset: CGFloat) -> some View {
        let startNorm = CGFloat(bar.startTick - range.lowerBound) / CGFloat(span)
        let endNorm = CGFloat(bar.endTick - range.lowerBound) / CGFloat(span)
        let x = min(max(startNorm * timelineWidth, 0), timelineWidth)
        let w = max(2, (endNorm - startNorm) * timelineWidth)

        return ZStack(alignment: .leading) {
            renderBarFill(style: bar.fillStyle, tintColor: bar.tintColor)

            if let prog = bar.progress {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.25))
                    .frame(width: w * CGFloat(max(0.0, min(1.0, prog))))
            }

            Text(bar.label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .lineLimit(1)
        }
        .frame(width: w, height: 26)
        .offset(x: x, y: yOffset)
    }

    @ViewBuilder
    private func renderBarFill(style: GanttFillStyle, tintColor: Color) -> some View {
        switch style {
        case .solid:
            RoundedRectangle(cornerRadius: 4)
                .fill(tintColor.opacity(0.85))
        case .striped:
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(tintColor.opacity(0.35))
                StripedPattern(spacing: 8)
                    .stroke(tintColor, lineWidth: 1.5)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        case .faded:
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [tintColor.opacity(0.9), tintColor.opacity(0.2)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
}
