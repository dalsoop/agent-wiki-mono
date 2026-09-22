import SwiftUI

public struct SparklineWaveCanvas: View {
    public let points: [WaveDataPoint]
    public var strokeColor: Color
    public var isLivePulsing: Bool
    public var lineWidth: CGFloat
    public var showGrid: Bool

    public init(
        points: [WaveDataPoint],
        strokeColor: Color = .green,
        isLivePulsing: Bool = false,
        lineWidth: CGFloat = 2.0,
        showGrid: Bool = true
    ) {
        self.points = points
        self.strokeColor = strokeColor
        self.isLivePulsing = isLivePulsing
        self.lineWidth = lineWidth
        self.showGrid = showGrid
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isLivePulsing)) { timeline in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                guard width > 0, height > 0 else { return }

                if showGrid {
                    drawGrid(context: &context, width: width, height: height)
                }

                guard points.count >= 2 else { return }
                drawWaveform(context: &context, width: width, height: height, date: timeline.date)
            }
        }
    }

    private func drawGrid(context: inout GraphicsContext, width: CGFloat, height: CGFloat) {
        var gridPath = Path()
        let rows = 3
        for i in 1...rows {
            let y = height * CGFloat(i) / CGFloat(rows + 1)
            gridPath.move(to: CGPoint(x: 0, y: y))
            gridPath.addLine(to: CGPoint(x: width, y: y))
        }
        context.stroke(gridPath, with: .color(.secondary.opacity(0.12)), lineWidth: 1)
    }

    private func drawWaveform(context: inout GraphicsContext, width: CGFloat, height: CGFloat, date: Date) {
        let (path, fillPath, lastPoint) = buildWavePaths(width: width, height: height)

        let gradient = Gradient(colors: [strokeColor.opacity(0.3), strokeColor.opacity(0.0)])
        context.fill(
            fillPath,
            with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: 0, y: height))
        )
        context.stroke(path, with: .color(strokeColor), lineWidth: lineWidth)

        if isLivePulsing {
            drawPulsePoint(context: &context, at: lastPoint, date: date)
        }
    }

    private func buildWavePaths(width: CGFloat, height: CGFloat) -> (path: Path, fillPath: Path, lastPoint: CGPoint) {
        let amplitudes = points.map(\.amplitude)
        let minAmp = amplitudes.min() ?? 0.0
        let maxAmp = amplitudes.max() ?? 1.0
        let ampRange = maxAmp > minAmp ? (maxAmp - minAmp) : 1.0
        let stepX = width / CGFloat(points.count - 1)

        var path = Path()
        var fillPath = Path()
        var lastPoint: CGPoint = .zero

        for (idx, pt) in points.enumerated() {
            let x = CGFloat(idx) * stepX
            let normY = (pt.amplitude - minAmp) / ampRange
            let y = height - (CGFloat(normY) * (height - 8) + 4)
            let currentPoint = CGPoint(x: x, y: y)

            if idx == 0 {
                path.move(to: currentPoint)
                fillPath.move(to: CGPoint(x: x, y: height))
                fillPath.addLine(to: currentPoint)
            } else {
                let midPoint = CGPoint(
                    x: (lastPoint.x + currentPoint.x) / 2.0,
                    y: (lastPoint.y + currentPoint.y) / 2.0
                )
                path.addQuadCurve(to: midPoint, control: lastPoint)
                fillPath.addQuadCurve(to: midPoint, control: lastPoint)
            }

            if idx == points.count - 1 {
                path.addLine(to: currentPoint)
                fillPath.addLine(to: currentPoint)
                fillPath.addLine(to: CGPoint(x: currentPoint.x, y: height))
                fillPath.closeSubpath()
            }
            lastPoint = currentPoint
        }

        return (path, fillPath, lastPoint)
    }

    private func drawPulsePoint(context: inout GraphicsContext, at point: CGPoint, date: Date) {
        let time = date.timeIntervalSinceReferenceDate
        let pulsePhase = CGFloat((sin(time * 6.0) + 1.0) / 2.0)
        let radius: CGFloat = 3.0 + (pulsePhase * 3.0)
        let haloRadius: CGFloat = radius + 4.0

        let haloRect = CGRect(x: point.x - haloRadius, y: point.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
        context.fill(Path(ellipseIn: haloRect), with: .color(strokeColor.opacity(0.3 * (1.0 - Double(pulsePhase)))))

        let pointRect = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: pointRect), with: .color(strokeColor))
    }
}
