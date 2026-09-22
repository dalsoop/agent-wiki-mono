import CoreGraphics
import Foundation

// MARK: - 모델

/// 레이아웃 입력 노드. `fixedPosition` 이 있으면 시뮬레이션 내내 고정된다(핀 노드).
public struct LayoutNode: Sendable, Equatable, Identifiable {
    public let id: String
    public var fixedPosition: CGPoint?

    public init(id: String, fixedPosition: CGPoint? = nil) {
        self.id = id
        self.fixedPosition = fixedPosition
    }
}

/// 레이아웃 입력 엣지. `weight` 가 클수록 스프링이 뻣뻣해져(더 짧게) 당긴다.
public struct LayoutEdge: Sendable, Equatable {
    public let from: String
    public let to: String
    public var weight: Double

    public init(from: String, to: String, weight: Double = 1.0) {
        self.from = from
        self.to = to
        self.weight = weight
    }
}

/// 레이아웃 결과 — 노드 id → 캔버스 좌표(항상 주어진 canvasSize 안).
public struct LayoutResult: Sendable, Equatable {
    public var positions: [String: CGPoint]

    public init(positions: [String: CGPoint]) {
        self.positions = positions
    }

    public subscript(id: String) -> CGPoint? { positions[id] }
}

// MARK: - Force-directed 레이아웃 (spring/repulsion 모델)

/// 외부 SPM 의존 없는 결정론적 force-directed 2D 레이아웃.
///
/// - 결정론: 같은 입력(노드·엣지 집합·canvasSize·configuration) 이면 언제나 같은 출력.
///   초기 배치는 벽시계·난수가 아니라 **id 정렬 순서 기반 원형 배치**로 시드한다.
/// - 경계: 매 반복과 최종 결과 모두 `canvasSize` 안으로 clamp 한다.
/// - 최소 간격: 시뮬레이션 후 겹침 해소 패스로 `minSeparation` 이상을 보장한다.
public enum ForceDirectedLayout {

    public struct Configuration: Sendable, Equatable {
        /// 시뮬레이션 스텝 수.
        public var iterations: Int
        /// 노드 간 반발력 계수(Coulomb 유사).
        public var repulsion: Double
        /// 엣지 스프링의 자연 길이.
        public var springLength: Double
        /// 엣지 스프링 강성.
        public var springStiffness: Double
        /// 최종적으로 보장할 노드 간 최소 거리.
        public var minSeparation: Double
        /// 속도 감쇠(0~1). 클수록 빨리 정지.
        public var damping: Double
        /// 스텝당 최대 이동량(발산 방지).
        public var maxStepDisplacement: Double
        /// 캔버스 가장자리 여백(노드 반지름 고려).
        public var margin: Double

        public init(
            iterations: Int = 220,
            repulsion: Double = 3200,
            springLength: Double = 60,
            springStiffness: Double = 0.06,
            minSeparation: Double = 20,
            damping: Double = 0.82,
            maxStepDisplacement: Double = 24,
            margin: Double = 24
        ) {
            self.iterations = iterations
            self.repulsion = repulsion
            self.springLength = springLength
            self.springStiffness = springStiffness
            self.minSeparation = minSeparation
            self.damping = damping
            self.maxStepDisplacement = maxStepDisplacement
            self.margin = margin
        }
    }

    /// 노드·엣지로부터 결정론적 force-directed 레이아웃을 계산한다.
    public static func layout(
        nodes: [LayoutNode],
        edges: [LayoutEdge],
        canvasSize: CGSize,
        configuration: Configuration = Configuration()
    ) -> LayoutResult {
        guard !nodes.isEmpty else { return LayoutResult(positions: [:]) }
        // 결정론 보장: 호출자가 넘긴 순서가 매번 같으리란 보장이 없으므로(Set 순회 등),
        // id 로 정렬해 인덱스를 고정한다.
        let sorted = nodes.sorted { $0.id < $1.id }
        let width = max(canvasSize.width, 1)
        let height = max(canvasSize.height, 1)
        let margin = min(configuration.margin, min(width, height) / 2 - 1)
        let usableW = max(width - margin * 2, 1)
        let usableH = max(height - margin * 2, 1)
        let center = CGPoint(x: width / 2, y: height / 2)
        let n = sorted.count

        // 인접 인덱스 맵.
        var index: [String: Int] = [:]
        for (i, node) in sorted.enumerated() { index[node.id] = i }
        let validEdges = edges.compactMap { edge -> (Int, Int, Double)? in
            guard let a = index[edge.from], let b = index[edge.to], a != b else { return nil }
            return (a, b, max(edge.weight, 0.001))
        }
        let fixed = sorted.map { $0.fixedPosition != nil }

        // 결정론적 초기 배치: id 정렬 순 원형 시드(그리드 아님 — 초반 반발이 고르게 퍼진다).
        var pos: [CGPoint] = (0..<n).map { i in
            if let f = sorted[i].fixedPosition {
                return clamp(f, minX: margin, maxX: width - margin, minY: margin, maxY: height - margin)
            }
            if n == 1 { return center }
            let angle = 2.0 * Double.pi * Double(i) / Double(n)
            let radius = min(usableW, usableH) * 0.38
            return CGPoint(x: center.x + CGFloat(cos(angle)) * radius,
                            y: center.y + CGFloat(sin(angle)) * radius)
        }

        for _ in 0..<max(configuration.iterations, 0) {
            var force = [CGVector](repeating: .zero, count: n)

            // 반발력(모든 쌍) — O(n^2), 함대/세션 그래프 규모(수백 이내)에 적합.
            if n > 1 {
                for i in 0..<n {
                    for j in (i + 1)..<n {
                        var dx = pos[i].x - pos[j].x
                        var dy = pos[i].y - pos[j].y
                        var distSq = Double(dx * dx + dy * dy)
                        if distSq < 0.0001 {
                            // 완전히 겹친 시작점 — id 기반 결정론적 방향으로 살짝 벌린다.
                            let seed = Double((i * 2654435761 + j) % 360)
                            let angle = seed * .pi / 180
                            dx = CGFloat(cos(angle)) * 0.01
                            dy = CGFloat(sin(angle)) * 0.01
                            distSq = 0.0001
                        }
                        let dist = sqrt(distSq)
                        let f = configuration.repulsion / distSq
                        let fx = CGFloat(Double(dx) / dist * f)
                        let fy = CGFloat(Double(dy) / dist * f)
                        force[i].dx += fx
                        force[i].dy += fy
                        force[j].dx -= fx
                        force[j].dy -= fy
                    }
                }
            }

            // 인력(스프링, 엣지).
            for (a, b, weight) in validEdges {
                let dx = pos[b].x - pos[a].x
                let dy = pos[b].y - pos[a].y
                let dist = max(Double(sqrt(dx * dx + dy * dy)), 0.01)
                let displacement = dist - configuration.springLength
                let f = displacement * configuration.springStiffness * weight
                let fx = CGFloat(f * Double(dx) / dist)
                let fy = CGFloat(f * Double(dy) / dist)
                force[a].dx += fx
                force[a].dy += fy
                force[b].dx -= fx
                force[b].dy -= fy
            }

            // 중심으로 약하게 당겨 발산 방지.
            for i in 0..<n {
                force[i].dx += (center.x - pos[i].x) * 0.01
                force[i].dy += (center.y - pos[i].y) * 0.01
            }

            for i in 0..<n where !fixed[i] {
                var dx = force[i].dx * CGFloat(configuration.damping)
                var dy = force[i].dy * CGFloat(configuration.damping)
                let mag = sqrt(dx * dx + dy * dy)
                let cap = CGFloat(configuration.maxStepDisplacement)
                if mag > cap, mag > 0 {
                    dx = dx / mag * cap
                    dy = dy / mag * cap
                }
                pos[i].x += dx
                pos[i].y += dy
                pos[i] = clamp(pos[i], minX: margin, maxX: width - margin, minY: margin, maxY: height - margin)
            }
        }

        // 겹침 해소 — 최소 간격 미달 쌍을 결정론적 순서(오름차순 (i,j))로 반복 분리.
        if n > 1 {
            let minSep = CGFloat(configuration.minSeparation)
            for _ in 0..<6 {
                var moved = false
                for i in 0..<n {
                    for j in (i + 1)..<n {
                        var dx = pos[j].x - pos[i].x
                        var dy = pos[j].y - pos[i].y
                        var dist = sqrt(dx * dx + dy * dy)
                        guard dist < minSep else { continue }
                        if dist < 0.0001 {
                            let seed = Double((i * 2654435761 + j) % 360)
                            let angle = seed * .pi / 180
                            dx = CGFloat(cos(angle))
                            dy = CGFloat(sin(angle))
                            dist = 1
                        }
                        let push = (minSep - dist) / 2
                        let ux = dx / dist
                        let uy = dy / dist
                        if !fixed[i] {
                            pos[i].x -= ux * push
                            pos[i].y -= uy * push
                        }
                        if !fixed[j] {
                            pos[j].x += ux * push
                            pos[j].y += uy * push
                        }
                        pos[i] = clamp(pos[i], minX: margin, maxX: width - margin, minY: margin, maxY: height - margin)
                        pos[j] = clamp(pos[j], minX: margin, maxX: width - margin, minY: margin, maxY: height - margin)
                        moved = true
                    }
                }
                if !moved { break }
            }
        }

        var result: [String: CGPoint] = [:]
        result.reserveCapacity(n)
        for (i, node) in sorted.enumerated() { result[node.id] = pos[i] }
        return LayoutResult(positions: result)
    }

    private static func clamp(_ p: CGPoint, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGPoint {
        // minX>maxX(캔버스가 여백보다 작음) 방어 — 중앙으로 수렴.
        let lo = min(minX, maxX)
        let hi = max(minX, maxX)
        let loY = min(minY, maxY)
        let hiY = max(minY, maxY)
        return CGPoint(x: Swift.min(Swift.max(p.x, lo), hi), y: Swift.min(Swift.max(p.y, loY), hiY))
    }
}
