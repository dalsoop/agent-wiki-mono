import Foundation
import CoreGraphics

/// Deterministic Fruchterman–Reingold force-directed layout.
/// No RNG — nodes seed on a circle by index, so the same graph always
/// produces the same picture (stable across app launches).
public struct ForceLayout: Sendable {
    public var iterations: Int
    public init(iterations: Int = 300) { self.iterations = iterations }

    public func layout(nodes: [String], edges: [(String, String)], size: CGSize) -> [String: CGPoint] {
        let n = nodes.count
        guard n > 0 else { return [:] }
        let W = size.width - 120, H = size.height - 120
        let k = sqrt(W * H / CGFloat(n))          // ideal edge length

        var p = [String: CGPoint](minimumCapacity: n)
        for (i, name) in nodes.enumerated() {
            let a = 2 * Double.pi * Double(i) / Double(n)
            p[name] = CGPoint(x: W/2 + 60 + CGFloat(cos(a)) * W/3,
                              y: H/2 + 60 + CGFloat(sin(a)) * H/3)
        }
        var temp = W / 10

        for _ in 0..<iterations {
            var disp = [String: CGVector](minimumCapacity: n)
            for i in 0..<n {
                var d = CGVector(dx: 0, dy: 0)
                let pi = p[nodes[i]]!
                for j in 0..<n where j != i {
                    let r = repulsion(from: pi, to: p[nodes[j]]!, i: i, j: j, k: k)
                    d.dx += r.dx
                    d.dy += r.dy
                }
                disp[nodes[i]] = d
            }
            for (a, b) in edges {
                guard let pa = p[a], let pb = p[b] else { continue }
                let dx = pa.x - pb.x, dy = pa.y - pb.y
                let dl = max(sqrt(dx*dx + dy*dy), 0.01)
                let f = dl * dl / k
                let fx = dx / dl * f, fy = dy / dl * f
                var da = disp[a] ?? CGVector(); da.dx -= fx; da.dy -= fy; disp[a] = da
                var db = disp[b] ?? CGVector(); db.dx += fx; db.dy += fy; disp[b] = db
            }
            for name in nodes {
                guard let d = disp[name] else { continue }
                let dl = max(sqrt(d.dx*d.dx + d.dy*d.dy), 0.01)
                var np = p[name]!
                np.x += d.dx / dl * min(dl, temp)
                np.y += d.dy / dl * min(dl, temp)
                np.x = min(max(40, np.x), size.width - 40)
                np.y = min(max(40, np.y), size.height - 50)
                p[name] = np
            }
            temp = max(temp * 0.96, 2)
        }
        return p
    }

    private func repulsion(from pi: CGPoint, to pj: CGPoint, i: Int, j: Int, k: CGFloat) -> CGVector {
        var dx = pi.x - pj.x
        var dy = pi.y - pj.y
        var dl = sqrt(dx * dx + dy * dy)
        if dl < 0.01 {
            dx = CGFloat(i - j)
            dy = 0.1
            dl = 0.1
        }
        let force = k * k / dl
        return CGVector(dx: dx / dl * force, dy: dy / dl * force)
    }
}
