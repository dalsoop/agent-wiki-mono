import Foundation
import CoreGraphics

/// AI 생성 스프라이트 시트의 고질적 문제 — **액션(시트)마다 캐릭터 크기·접지 위치가 달라
/// 게임에서 애니 전환 때 캐릭터가 커졌다 작아졌다** 하는 것 — 을 픽셀 단위로 정규화한다.
///
/// 기법(LayrKits/Sprite-Pipeline·spright 등 확립된 방식 + sprite-gen 소화):
/// 1. 프레임마다 알파 bounding box 검출.
/// 2. 시트별 대표 신장(프레임 bbox 높이 중앙값)을 **공통 목표 높이**로 스케일.
///    시트 전체를 **한 배율**로 스케일하므로 시트 내 모션(팔 뻗기·점프)은 보존.
///    **폭-fit**: 스케일 후 콘텐츠 폭이 `cellW-2` 를 넘는 프레임이 있으면 그 프레임만
///    줄이는 게 아니라 시트 배율 자체를 낮춰(min(heightScale, widthScale)) **클리핑 금지**.
/// 3. 다운스케일은 **area-average(박스필터)**, 업스케일은 **정수배 NEAREST 만**
///    (비정수 업스케일 금지 — 목표높이 미달이면 가장 가까운 정수배) → 도트 보존.
/// 4. 각 프레임을 고정 셀에 **발(bbox 하단) baseline 앵커 + 알파 가중 중심(centroid,
///    α≤10 무시) 수평 정렬**로 배치 → 기울어진 포즈에서도 수평 지터 없음.
/// 결과: 모든 애니에서 캐릭터 크기·접지가 일정한, 도트로 관리되는 시트.
public enum FrameNormalizer {
    /// 수평 centroid 계산에서 무시할 알파 상한(α ≤ 이 값 무시).
    static let centroidAlphaIgnore: UInt8 = 10

    public struct Options: Sendable {
        /// 출력 셀 크기(프레임 1칸). 최종 시트 폭 = cellW * frames.
        public var cellW: Int
        public var cellH: Int
        /// 캐릭터 목표 높이(px). 모든 시트가 이 높이에 맞춰짐.
        public var targetCharHeight: Int
        /// 셀 바닥에서 발(baseline)까지 여백(px).
        public var baselineFromBottom: Int
        public var alphaThreshold: UInt8
        public init(cellW: Int = 96, cellH: Int = 128, targetCharHeight: Int = 104,
                    baselineFromBottom: Int = 6, alphaThreshold: UInt8 = 24) {
            self.cellW = cellW; self.cellH = cellH
            self.targetCharHeight = targetCharHeight
            self.baselineFromBottom = baselineFromBottom
            self.alphaThreshold = alphaThreshold
        }
    }

    /// 시트를 균등 slice 후 정규화해 새 CGImage(cellW*frames × cellH)로 반환.
    /// (기존 API 호환 — 연결요소 추출을 쓰려면 `FrameExtractor.extractFrames` 결과를
    /// `normalize(frames:options:)` 오버로드에 넘긴다.)
    public static func normalize(_ image: CGImage, frames: Int, options o: Options = .init()) -> CGImage? {
        guard frames > 0 else { return nil }
        let cells = SpriteSlicer.slice(image, frames: frames)
        guard cells.count == frames else { return nil }
        return normalize(frames: cells, options: o)
    }

    /// 프레임 CGImage 배열(예: `FrameExtractor.extractFrames` 결과)을 정규화한다.
    public static func normalize(frames cells: [CGImage], options o: Options = .init()) -> CGImage? {
        guard !cells.isEmpty, o.cellW > 2, o.cellH > o.baselineFromBottom, o.baselineFromBottom >= 0,
              o.targetCharHeight > 0 else { return nil }

        // 프레임별 버퍼 + 콘텐츠 bbox.
        var buffers: [(px: [UInt8], w: Int, h: Int)] = []
        var boxes: [(x: Int, y: Int, w: Int, h: Int)?] = []
        for cell in cells {
            guard let buf = PixelOps.readRGBA(cell) else { return nil }
            boxes.append(PixelOps.alphaBox(px: buf.px, w: buf.w, h: buf.h, threshold: o.alphaThreshold))
            buffers.append(buf)
        }
        let contentBoxes = boxes.compactMap { $0 }
        guard !contentBoxes.isEmpty else { return nil }

        // 대표 신장 = bbox 높이 중앙값(극단 프레임에 강건) → 목표 높이 배율.
        let heights = contentBoxes.map(\.h).sorted()
        let refHeight = heights[heights.count / 2]
        var scale = Double(o.targetCharHeight) / Double(max(1, refHeight))

        // 폭-fit + 높이-fit: 어떤 프레임도 셀을 넘지 않도록 **시트 전체 배율**을 낮춘다(클리핑 금지).
        let maxContentW = Double(o.cellW - 2)
        let maxContentH = Double(o.cellH - o.baselineFromBottom)
        for box in contentBoxes {
            scale = min(scale, maxContentW / Double(box.w), maxContentH / Double(box.h))
        }
        guard scale > 0 else { return nil }

        // 업스케일은 정수배만(NEAREST). 목표 미달이면 가장 가까운 정수배 — 단 fit 을 깨면 내린다.
        var upFactor: Int?
        if scale >= 1 {
            var f = max(1, Int(scale.rounded()))
            func fits(_ f: Int) -> Bool {
                contentBoxes.allSatisfy {
                    Double($0.w * f) <= maxContentW && Double($0.h * f) <= maxContentH
                }
            }
            while f > 1 && !fits(f) { f -= 1 }
            upFactor = f
            scale = Double(f)
        }

        // 출력 버퍼(top-down RGBA, 투명 초기화)에 프레임별 배치.
        let outW = o.cellW * cells.count, outH = o.cellH
        var out = [UInt8](repeating: 0, count: outW * outH * 4)

        for (i, buf) in buffers.enumerated() {
            guard let box = boxes[i] else { continue }
            // 콘텐츠 crop.
            let crop = subBuffer(buf.px, w: buf.w, box: box)
            // 스케일: 정수배 NEAREST 업스케일 / area-average 다운스케일.
            let scaled: (px: [UInt8], w: Int, h: Int)
            if let f = upFactor {
                scaled = f == 1 ? (crop, box.w, box.h) : nearestUpscale(crop, w: box.w, h: box.h, factor: f)
            } else {
                scaled = boxDownscale(crop, w: box.w, h: box.h, scale: scale)
            }
            let sw = scaled.w, sh = scaled.h
            guard sw > 0, sh > 0 else { continue }

            // 수평: 알파 가중 중심(α≤10 무시)을 셀 중앙에 → 수평 지터 제거.
            let cx = alphaCentroidX(scaled.px, w: sw, h: sh)
            let cellStart = i * o.cellW
            var dx = cellStart + Int((Double(o.cellW) / 2 - cx).rounded())
            // 클리핑 절대 금지: 폭-fit 보장(sw ≤ cellW-2) 하에 셀 안으로 clamp.
            dx = min(max(dx, cellStart + 1), cellStart + o.cellW - 1 - sw)
            // 수직: 발(콘텐츠 하단)을 baseline 에 고정.
            let dy = max(0, o.cellH - o.baselineFromBottom - sh)

            blit(scaled.px, w: sw, h: sh, into: &out, outW: outW, atX: dx, atY: dy)
        }
        return PixelOps.makeImage(px: out, w: outW, h: outH)
    }

    // MARK: - 픽셀 연산 (top-down premultiplied RGBA)

    /// box 영역만 잘라낸 새 버퍼.
    static func subBuffer(_ px: [UInt8], w: Int, box: (x: Int, y: Int, w: Int, h: Int)) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: box.w * box.h * 4)
        for row in 0..<box.h {
            let src = ((box.y + row) * w + box.x) * 4
            let dst = row * box.w * 4
            out.replaceSubrange(dst..<(dst + box.w * 4), with: px[src..<(src + box.w * 4)])
        }
        return out
    }

    /// 정수배 NEAREST 업스케일(픽셀 복제 — 도트 보존).
    static func nearestUpscale(_ px: [UInt8], w: Int, h: Int, factor f: Int) -> (px: [UInt8], w: Int, h: Int) {
        let ow = w * f, oh = h * f
        var out = [UInt8](repeating: 0, count: ow * oh * 4)
        for y in 0..<oh {
            let sy = y / f
            for x in 0..<ow {
                let s = (sy * w + x / f) * 4, d = (y * ow + x) * 4
                out[d] = px[s]; out[d + 1] = px[s + 1]; out[d + 2] = px[s + 2]; out[d + 3] = px[s + 3]
            }
        }
        return (out, ow, oh)
    }

    /// area-average(박스필터) 다운스케일. premultiplied 채널을 그대로 평균 → 알파 정확.
    static func boxDownscale(_ px: [UInt8], w: Int, h: Int, scale: Double) -> (px: [UInt8], w: Int, h: Int) {
        let ow = max(1, Int((Double(w) * scale).rounded()))
        let oh = max(1, Int((Double(h) * scale).rounded()))
        guard ow < w || oh < h else { return (px, w, h) }
        let rx = Double(w) / Double(ow), ry = Double(h) / Double(oh)
        var out = [UInt8](repeating: 0, count: ow * oh * 4)
        for dy in 0..<oh {
            let y0 = Int(Double(dy) * ry), y1 = min(h, max(y0 + 1, Int((Double(dy + 1) * ry).rounded(.up))))
            for dxi in 0..<ow {
                let x0 = Int(Double(dxi) * rx), x1 = min(w, max(x0 + 1, Int((Double(dxi + 1) * rx).rounded(.up))))
                var r = 0.0, g = 0.0, b = 0.0, a = 0.0
                for sy in y0..<y1 {
                    for sx in x0..<x1 {
                        let s = (sy * w + sx) * 4
                        r += Double(px[s]); g += Double(px[s + 1]); b += Double(px[s + 2]); a += Double(px[s + 3])
                    }
                }
                let n = Double((y1 - y0) * (x1 - x0))
                let d = (dy * ow + dxi) * 4
                out[d] = UInt8((r / n).rounded()); out[d + 1] = UInt8((g / n).rounded())
                out[d + 2] = UInt8((b / n).rounded()); out[d + 3] = UInt8((a / n).rounded())
            }
        }
        return (out, ow, oh)
    }

    /// 알파 가중 x 중심(α ≤ centroidAlphaIgnore 무시). 콘텐츠 없으면 중앙.
    static func alphaCentroidX(_ px: [UInt8], w: Int, h: Int) -> Double {
        var sum = 0.0, weight = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let a = px[(y * w + x) * 4 + 3]
                guard a > centroidAlphaIgnore else { continue }
                sum += (Double(x) + 0.5) * Double(a)
                weight += Double(a)
            }
        }
        return weight > 0 ? sum / weight : Double(w) / 2
    }

    /// src 버퍼를 out 버퍼 (atX, atY)에 복사(셀은 서로 겹치지 않으므로 단순 대입).
    static func blit(_ src: [UInt8], w: Int, h: Int, into out: inout [UInt8], outW: Int, atX: Int, atY: Int) {
        for row in 0..<h {
            let s = row * w * 4
            let d = ((atY + row) * outW + atX) * 4
            out.replaceSubrange(d..<(d + w * 4), with: src[s..<(s + w * 4)])
        }
    }

    /// 알파 ≥ threshold 인 픽셀의 bounding box(top-left 원점, `CGImage.cropping` 좌표계).
    /// 주의: CGBitmapContext 에 draw 한 버퍼는 **row 0 = 이미지 최상단(top-down)** 이다
    /// (경험적 검증 — 과거 "row 0 = 하단" 주석은 오류였고 y 가 뒤집혀 반환됐다).
    static func contentBox(_ image: CGImage, threshold: UInt8) -> CGRect {
        guard let buf = PixelOps.readRGBA(image),
              let box = PixelOps.alphaBox(px: buf.px, w: buf.w, h: buf.h, threshold: threshold)
        else { return .zero }
        return CGRect(x: box.x, y: box.y, width: box.w, height: box.h)
    }
}
