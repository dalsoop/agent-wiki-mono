import Foundation

/// 배선도의 **배치 계산** — 그리기와 분리한다.
///
/// 뷰 안에 좌표를 두면 화면을 띄워 눈으로 보는 것 말고는 검증할 방법이 없다. 이 Mac
/// 에서는 다른 에이전트 세션 창이 계속 앞으로 올라와 스크린샷이 신뢰할 수 없었다
/// (2026-08-04 실측 — 창 캡처가 세 번 연속 다른 앱을 찍었다). 배치가 순수 함수면
/// 상자가 겹치는지, 화살표가 상자 테두리에 닿는지를 **테스트로** 못 박을 수 있다.
public struct StructureLayout: Sendable {
    public struct Point: Sendable, Equatable {
        public let x: Double
        public let y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public struct Rect: Sendable, Equatable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
        public var midX: Double { x + width / 2 }
        public var midY: Double { y + height / 2 }
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
        public func intersects(_ other: Rect) -> Bool {
            x < other.maxX && other.x < maxX && y < other.maxY && other.y < maxY
        }
        public func contains(_ p: Point, slack: Double = 0.5) -> Bool {
            p.x >= x - slack && p.x <= maxX + slack && p.y >= y - slack && p.y <= maxY + slack
        }
    }

    /// 층 — 위에서 아래로 봉인 → 해석 → 파생. 데이터가 흐르는 방향이 아니라
    /// **신뢰의 방향**이다: 아래로 갈수록 언제든 다시 만들 수 있다.
    public enum Tier: Int, Sendable { case seal = 0, interpretation = 1, derived = 2 }

    public struct Box: Sendable {
        public let id: String
        public let title: String
        public let subtitle: String
        public let tier: Tier
        public let rect: Rect
    }

    public struct Wire: Sendable {
        public let edgeID: String
        public let from: Point
        public let to: Point
        public var label: Point {
            Point(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        }
    }

    public let boxes: [Box]
    public let wires: [Wire]
    public let size: (width: Double, height: Double)

    private static let tierY: [Tier: Double] = [.seal: 24, .interpretation: 186, .derived: 348]
    private static let boxHeight: Double = 62

    public init(structure: LedgerStructure) {
        func bytes(_ id: String) -> String {
            guard let layer = structure.layers.first(where: { $0.id == id }) else { return "" }
            let n = layer.bytes
            let size = n >= 1_000_000 ? String(format: "%.1f MB", Double(n) / 1_000_000)
                : (n >= 1_000 ? String(format: "%.0f KB", Double(n) / 1_000) : "\(n) B")
            return "\(layer.files)개 · \(size)"
        }

        // 열 좌표 고정 격자 — 눈대중 오프셋은 노이즈로 읽힌다.
        let specs: [(id: String, title: String, subtitle: String, tier: Tier, x: Double, w: Double)] = [
            ("blobs", "blobs", bytes("blobs"), .seal, 40, 250),
            ("objects", "objects", bytes("objects"), .interpretation, 40, 250),
            ("events", "events", bytes("events"), .interpretation, 330, 200),
            ("선별", "선별 (분류)", "screening", .interpretation, 560, 130),
            ("state/index.db", "state/index.db", "objects·cites·fts5", .derived, 40, 250),
            ("state/fts5", "state/fts5", "어휘 검색", .derived, 330, 200),
            ("state/graph.db", "state/graph.db", "관계도", .derived, 560, 130),
        ]
        let laidOut = specs.map { spec in
            Box(id: spec.id, title: spec.title, subtitle: spec.subtitle, tier: spec.tier,
                rect: Rect(x: spec.x, y: Self.tierY[spec.tier] ?? 0,
                           width: spec.w, height: Self.boxHeight))
        }
        self.boxes = laidOut
        let byID = Dictionary(uniqueKeysWithValues: laidOut.map { ($0.id, $0) })
        func resolve(_ endpoint: String) -> Box? {
            byID[endpoint] ?? laidOut.first { endpoint.hasPrefix($0.id) }
        }
        self.wires = structure.edges.compactMap { edge in
            guard let from = resolve(edge.from), let to = resolve(edge.to) else { return nil }
            // 자기 간선(같은 층 안의 관계 — 예: 객체끼리의 인용)은 상자 왼쪽에 짧은
            // 고리로 건다. 건너뛰면 그 간선이 **그림에서 조용히 사라진다**(테스트가 잡음).
            guard from.id != to.id else {
                let y = from.rect.midY
                return Wire(edgeID: edge.id,
                            from: Point(x: from.rect.x, y: y - 10),
                            to: Point(x: from.rect.x, y: y + 10))
            }
            return Wire(edgeID: edge.id,
                        from: Self.anchor(from.rect, toward: to.rect),
                        to: Self.anchor(to.rect, toward: from.rect))
        }
        let right = laidOut.map(\.rect.maxX).max() ?? 0
        let bottom = laidOut.map(\.rect.maxY).max() ?? 0
        self.size = (right + 40, bottom + 30)
    }

    /// 두 중심을 잇는 선이 사각형 테두리와 만나는 점 — 화살표가 상자 안으로 파고들지 않게.
    static func anchor(_ rect: Rect, toward other: Rect) -> Point {
        let cx = rect.midX, cy = rect.midY
        let dx = other.midX - cx, dy = other.midY - cy
        guard dx != 0 || dy != 0 else { return Point(x: cx, y: cy) }
        let halfW = rect.width / 2, halfH = rect.height / 2
        let sx = dx == 0 ? Double.infinity : halfW / abs(dx)
        let sy = dy == 0 ? Double.infinity : halfH / abs(dy)
        let scale = min(sx, sy)
        return Point(x: cx + dx * scale, y: cy + dy * scale)
    }
}
