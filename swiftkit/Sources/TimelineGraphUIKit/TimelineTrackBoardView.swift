import SwiftUI

/// 도메인 비종속 시계열 트랙 보드 및 시간 여행 스크러버 뷰
public struct TimelineTrackBoardView: View {
    public let tracks: [TimelineTrack]
    public let timeRange: ClosedRange<Date>
    @Binding public var scrubberTime: Date
    public var onScrubberChanged: ((Date) -> Void)?

    public init(
        tracks: [TimelineTrack],
        timeRange: ClosedRange<Date>,
        scrubberTime: Binding<Date>,
        onScrubberChanged: ((Date) -> Void)? = nil
    ) {
        self.tracks = tracks
        self.timeRange = timeRange
        self._scrubberTime = scrubberTime
        self.onScrubberChanged = onScrubberChanged
    }

    public var body: some View {
        GeometryReader { geometry in
            let headerLabelWidth: CGFloat = 100.0
            let graphWidth = max(geometry.size.width - headerLabelWidth, 50.0)
            let totalDuration = max(timeRange.upperBound.timeIntervalSince(timeRange.lowerBound), 1.0)

            ZStack(alignment: .topLeading) {
                tracksContent(headerWidth: headerLabelWidth, graphWidth: graphWidth, duration: totalDuration)
                scrubberCursor(headerWidth: headerLabelWidth, graphWidth: graphWidth, duration: totalDuration)
            }
        }
    }

    private func tracksContent(headerWidth: CGFloat, graphWidth: CGFloat, duration: Double) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text("Tracks")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: headerWidth, alignment: .leading)
                TimelineAxisHeaderView(timeRange: timeRange, width: graphWidth)
            }
            .frame(height: 18)

            Divider()

            ForEach(tracks) { track in
                trackRow(track: track, headerWidth: headerWidth, graphWidth: graphWidth, duration: duration)
            }
        }
    }

    private func trackRow(track: TimelineTrack, headerWidth: CGFloat, graphWidth: CGFloat, duration: Double) -> some View {
        HStack(spacing: 0) {
            Text(track.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: headerWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.12))
                    .frame(height: 16)

                ForEach(track.segments) { segment in
                    segmentView(segment: segment, graphWidth: graphWidth, duration: duration)
                }

                ForEach(track.markers) { marker in
                    let xOffset = xPosition(for: marker.date, in: graphWidth, duration: duration)
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)
                        .offset(x: xOffset - 4)
                }
            }
            .frame(width: graphWidth, height: 20)
        }
    }

    private func segmentView(segment: TimelineSegment, graphWidth: CGFloat, duration: Double) -> some View {
        let xOffset = xPosition(for: segment.startDate, in: graphWidth, duration: duration)
        let segWidth = max(xPosition(for: segment.endDate, in: graphWidth, duration: duration) - xOffset, 4.0)

        return RoundedRectangle(cornerRadius: 3)
            .fill(segmentColor(hex: segment.tintHex))
            .frame(width: segWidth, height: 16)
            .offset(x: xOffset)
            .overlay(
                Text(segment.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .offset(x: xOffset)
                    .frame(width: segWidth, alignment: .leading),
                alignment: .leading
            )
    }

    private func scrubberCursor(headerWidth: CGFloat, graphWidth: CGFloat, duration: Double) -> some View {
        let scrubberX = headerWidth + xPosition(for: scrubberTime, in: graphWidth, duration: duration)
        return VStack(spacing: 0) {
            Capsule()
                .fill(Color.accentColor)
                .frame(width: 14, height: 14)
                .overlay(
                    Image(systemName: "clock.fill")
                        .font(.system(size: 7))
                        .foregroundColor(.white)
                )
            Rectangle()
                .fill(Color.accentColor.opacity(0.75))
                .frame(width: 2)
        }
        .offset(x: scrubberX - 7)
        .gesture(
            DragGesture()
                .onChanged { value in
                    let clampedX = min(max(value.location.x - headerWidth, 0), graphWidth)
                    let ratio = Double(clampedX / graphWidth)
                    let newTime = timeRange.lowerBound.addingTimeInterval(ratio * duration)
                    scrubberTime = newTime
                    onScrubberChanged?(newTime)
                }
        )
    }

    private func xPosition(for date: Date, in width: CGFloat, duration: Double) -> CGFloat {
        let elapsed = date.timeIntervalSince(timeRange.lowerBound)
        let ratio = max(min(elapsed / duration, 1.0), 0.0)
        return CGFloat(ratio) * width
    }

    private func segmentColor(hex: String?) -> Color {
        guard let hex else { return Color.accentColor }
        return Color(hex: hex) ?? Color.accentColor
    }
}

/// 시간축 헤더 눈금 뷰
public struct TimelineAxisHeaderView: View {
    public let timeRange: ClosedRange<Date>
    public let width: CGFloat

    public init(timeRange: ClosedRange<Date>, width: CGFloat) {
        self.timeRange = timeRange
        self.width = width
    }

    public var body: some View {
        HStack {
            Text(timeString(from: timeRange.lowerBound))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
            Spacer()
            Text(timeString(from: timeRange.upperBound))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .frame(width: width)
    }

    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

private extension Color {
    struct RGBA {
        var a: UInt64
        var r: UInt64
        var g: UInt64
        var b: UInt64
    }

    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        guard Scanner(string: clean).scanHexInt64(&int) else { return nil }
        let rgba: RGBA
        switch clean.count {
        case 3: // RGB (12-bit)
            rgba = RGBA(a: 255, r: (int >> 8) * 17, g: (int >> 4 & 0xF) * 17, b: (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            rgba = RGBA(a: 255, r: int >> 16, g: int >> 8 & 0xFF, b: int & 0xFF)
        case 8: // ARGB (32-bit)
            rgba = RGBA(a: int >> 24, r: int >> 16 & 0xFF, g: int >> 8 & 0xFF, b: int & 0xFF)
        default:
            return nil
        }
        self.init(
            .sRGB,
            red: Double(rgba.r) / 255,
            green: Double(rgba.g) / 255,
            blue: Double(rgba.b) / 255,
            opacity: Double(rgba.a) / 255
        )
    }
}
