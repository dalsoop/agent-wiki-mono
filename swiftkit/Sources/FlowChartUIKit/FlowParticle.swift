import SwiftUI

/// 간선 위를 흐르는 단일 파티클의 상태 모델 및 기하학 보간 도구입니다.
public struct FlowParticle: Identifiable, Sendable, Equatable {
    public let id: String
    public var progress: Double      // 0.0 ~ 1.0 (곡선 상의 상대 위치)
    public var size: CGFloat         // 파티클의 크기(반지름)
    public var color: Color          // 파티클 색상
    public var opacity: Double       // 불투명도

    public init(
        id: String = UUID().uuidString,
        progress: Double,
        size: CGFloat = 3.5,
        color: Color = .white,
        opacity: Double = 0.9
    ) {
        self.id = id
        self.progress = progress
        self.size = size
        self.color = color
        self.opacity = opacity
    }

    /// 3차 베지어 곡선 공식 B(t)을 통해 시작점, 두 제어점, 끝점 사이의 t(0.0~1.0) 위치를 계산합니다.
    public static func pointOnCubicBezier(
        p0: CGPoint,
        p1: CGPoint,
        p2: CGPoint,
        p3: CGPoint,
        t: CGFloat
    ) -> CGPoint {
        let clampedT = max(0.0, min(1.0, t))
        let oneMinusT = 1.0 - clampedT
        let oneMinusT2 = oneMinusT * oneMinusT
        let oneMinusT3 = oneMinusT2 * oneMinusT
        let t2 = clampedT * clampedT
        let t3 = t2 * clampedT

        let x = oneMinusT3 * p0.x
            + 3.0 * oneMinusT2 * clampedT * p1.x
            + 3.0 * oneMinusT * t2 * p2.x
            + t3 * p3.x

        let y = oneMinusT3 * p0.y
            + 3.0 * oneMinusT2 * clampedT * p1.y
            + 3.0 * oneMinusT * t2 * p2.y
            + t3 * p3.y

        return CGPoint(x: x, y: y)
    }

    /// 두 점 사이의 방향에 따른 자연스러운 수평 S자 베지어 제어점을 생성합니다.
    public static func cubicBezierControlPoints(
        from start: CGPoint,
        to end: CGPoint
    ) -> (p1: CGPoint, p2: CGPoint) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = hypot(dx, dy)
        let horizontalCurvature = max(abs(dx) * 0.5, distance * 0.25)

        let p1 = CGPoint(x: start.x + horizontalCurvature, y: start.y)
        let p2 = CGPoint(x: end.x - horizontalCurvature, y: end.y)
        return (p1, p2)
    }
}
