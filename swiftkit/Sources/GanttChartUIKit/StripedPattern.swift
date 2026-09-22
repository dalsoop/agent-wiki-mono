import SwiftUI

/// 간트 바의 스트라이프 패턴을 그리기 위한 사선 셰이프입니다.
public struct StripedPattern: Shape, Sendable {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 8.0) {
        self.spacing = spacing
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let total = rect.width + rect.height
        var x: CGFloat = -rect.height

        while x < total {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            x += spacing
        }
        return path
    }
}
