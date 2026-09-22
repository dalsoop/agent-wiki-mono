import Foundation
import CoreGraphics

/// **공유 팔레트 양자화(median-cut)** — 시트 전체(모든 프레임)를 하나의 N색 팔레트로 remap 한다.
///
/// AI 생성 도트 애니의 고질병: 프레임마다 같은 부위 색이 미세하게 달라(24bit) 재생하면 **색이
/// 아른거린다(palette flicker)**. 시트 전체에서 팔레트를 한 번 뽑아 모든 픽셀을 거기로 맞추면
/// 프레임 간 색이 정확히 일치 → 깨끗한 도트 애니. 외부 프로세스 0(네이티브 Extract 경로용).
///
/// dither 없이 nearest 하드 매핑 → 도트 보존(안티에일리어싱/디더 도입 금지).
public enum PaletteQuantizer {
    public struct RGB: Equatable { var r: UInt8; var g: UInt8; var b: UInt8 }

    /// 시트 전체를 `colors` 색으로 양자화한 새 이미지. alpha ≤ `alphaThreshold` 는 투명 유지.
    public static func quantize(_ image: CGImage, colors: Int, alphaThreshold: UInt8 = 24) -> CGImage? {
        guard colors >= 2, let buf = PixelOps.readRGBA(image) else { return nil }
        guard let out = quantize(px: buf.px, w: buf.w, h: buf.h, colors: colors, alphaThreshold: alphaThreshold)
        else { return nil }
        return PixelOps.makeImage(px: out, w: buf.w, h: buf.h)
    }

    /// 순수 계산(테스트용). top-down premultiplied RGBA 버퍼를 받아 remap 된 버퍼를 반환.
    public static func quantize(px: [UInt8], w: Int, h: Int, colors: Int, alphaThreshold: UInt8) -> [UInt8]? {
        guard colors >= 2, px.count >= w * h * 4 else { return nil }
        // 1) 불투명 픽셀 색 수집.
        var samples: [RGB] = []
        samples.reserveCapacity(w * h / 2)
        for i in stride(from: 0, to: w * h * 4, by: 4) where px[i + 3] > alphaThreshold {
            samples.append(RGB(r: px[i], g: px[i + 1], b: px[i + 2]))
        }
        guard !samples.isEmpty else { return px }

        // 2) median-cut 으로 팔레트 생성.
        let palette = medianCut(samples, into: colors)
        guard !palette.isEmpty else { return px }

        // 3) 각 픽셀을 가장 가까운 팔레트색으로(캐시로 중복색 재계산 방지).
        var out = px
        var cache: [UInt32: (UInt8, UInt8, UInt8)] = [:]
        for i in stride(from: 0, to: w * h * 4, by: 4) where px[i + 3] > alphaThreshold {
            let key = UInt32(px[i]) << 16 | UInt32(px[i + 1]) << 8 | UInt32(px[i + 2])
            let c: (UInt8, UInt8, UInt8)
            if let hit = cache[key] { c = hit }
            else { c = nearest(RGB(r: px[i], g: px[i + 1], b: px[i + 2]), in: palette); cache[key] = c }
            out[i] = c.0; out[i + 1] = c.1; out[i + 2] = c.2
        }
        return out
    }

    // MARK: - median-cut

    static func medianCut(_ samples: [RGB], into target: Int) -> [RGB] {
        var boxes: [[RGB]] = [samples]
        while boxes.count < target {
            // 가장 채널 범위가 넓은 박스를 고른다.
            guard let idx = boxes.enumerated()
                .filter({ $0.element.count > 1 })
                .max(by: { rangeSpan($0.element) < rangeSpan($1.element) })?.offset else { break }
            let box = boxes.remove(at: idx)
            let channel = widestChannel(box)
            let sorted = box.sorted { component($0, channel) < component($1, channel) }
            let mid = sorted.count / 2
            boxes.append(Array(sorted[..<mid]))
            boxes.append(Array(sorted[mid...]))
        }
        return boxes.compactMap(average)
    }

    static func rangeSpan(_ box: [RGB]) -> Int {
        guard !box.isEmpty else { return 0 }
        var lo = (r: 255, g: 255, b: 255), hi = (r: 0, g: 0, b: 0)
        for c in box {
            lo.r = min(lo.r, Int(c.r)); hi.r = max(hi.r, Int(c.r))
            lo.g = min(lo.g, Int(c.g)); hi.g = max(hi.g, Int(c.g))
            lo.b = min(lo.b, Int(c.b)); hi.b = max(hi.b, Int(c.b))
        }
        return max(hi.r - lo.r, hi.g - lo.g, hi.b - lo.b)
    }

    static func widestChannel(_ box: [RGB]) -> Int {
        var lo = (r: 255, g: 255, b: 255), hi = (r: 0, g: 0, b: 0)
        for c in box {
            lo.r = min(lo.r, Int(c.r)); hi.r = max(hi.r, Int(c.r))
            lo.g = min(lo.g, Int(c.g)); hi.g = max(hi.g, Int(c.g))
            lo.b = min(lo.b, Int(c.b)); hi.b = max(hi.b, Int(c.b))
        }
        let dr = hi.r - lo.r, dg = hi.g - lo.g, db = hi.b - lo.b
        if dr >= dg && dr >= db { return 0 }
        return dg >= db ? 1 : 2
    }

    static func component(_ c: RGB, _ ch: Int) -> UInt8 { ch == 0 ? c.r : (ch == 1 ? c.g : c.b) }

    static func average(_ box: [RGB]) -> RGB? {
        guard !box.isEmpty else { return nil }
        var r = 0, g = 0, b = 0
        for c in box { r += Int(c.r); g += Int(c.g); b += Int(c.b) }
        let n = box.count
        return RGB(r: UInt8(r / n), g: UInt8(g / n), b: UInt8(b / n))
    }

    static func nearest(_ c: RGB, in palette: [RGB]) -> (UInt8, UInt8, UInt8) {
        var best = palette[0], bestD = Int.max
        for p in palette {
            let dr = Int(c.r) - Int(p.r), dg = Int(c.g) - Int(p.g), db = Int(c.b) - Int(p.b)
            let d = dr * dr + dg * dg + db * db
            if d < bestD { bestD = d; best = p }
        }
        return (best.r, best.g, best.b)
    }
}
