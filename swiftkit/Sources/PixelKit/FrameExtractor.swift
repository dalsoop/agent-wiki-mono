import Foundation
import CoreGraphics

/// 연결요소(connected components) 기반 프레임 추출.
///
/// 균등 1/N 분할을 폐기하고, 알파 마스크 flood-fill 로 blob 을 찾아
/// **콘텐츠 경계로 정확히** 프레임을 자른다 (codex 생성 시트의 불균등 배치 대응):
/// 1. 알파 ≥ threshold 마스크 → flood-fill(명시적 스택, 재귀 금지) blob: bbox·면적·x중심.
/// 2. 면적 상위 `frameCount` 개를 **seed** 로 선택 → x중심 순 정렬.
/// 3. 나머지 blob(분리된 무기·팔다리·파편)은 x중심이 가장 가까운 seed 그룹에 흡수.
/// 4. 그룹별 union bbox 로 crop. seed 가 모자라면 **throw** (silent fallback 금지 —
///    재생성/수보정 신호).
public enum FrameExtractor {
    public enum ExtractError: Error, Equatable, CustomStringConvertible, LocalizedError {
        /// 검출된 blob 수가 요구 프레임 수보다 적음(또는 frameCount ≤ 0).
        case frameCountMismatch(found: Int, expected: Int)
        /// 비트맵 버퍼 생성 실패.
        case bitmapUnavailable

        public var description: String {
            switch self {
            case let .frameCountMismatch(found, expected):
                return "frame count mismatch: found \(found) blob group(s), expected \(expected) — regenerate or fix the sheet (no silent fallback)"
            case .bitmapUnavailable:
                return "cannot create bitmap buffer for image"
            }
        }
        public var errorDescription: String? { description }
    }

    /// flood-fill 로 찾은 연결요소. 좌표는 top-left 원점(`CGImage.cropping` 좌표계).
    public struct Blob: Sendable, Equatable {
        public var minX: Int
        public var minY: Int
        public var maxX: Int
        public var maxY: Int
        /// 픽셀 수(알파 ≥ threshold).
        public var area: Int
        /// x 중심(픽셀 평균).
        public var xCentroid: Double

        public var width: Int { maxX - minX + 1 }
        public var height: Int { maxY - minY + 1 }
        public var bbox: CGRect {
            CGRect(x: minX, y: minY, width: width, height: height)
        }
    }

    /// 알파 ≥ `alphaThreshold` 마스크의 연결요소(8-이웃)를 전부 반환(순서 비보장).
    public static func connectedComponents(_ image: CGImage, alphaThreshold: UInt8 = 24) -> [Blob] {
        guard let buf = PixelOps.readRGBA(image) else { return [] }
        return connectedComponents(px: buf.px, w: buf.w, h: buf.h, alphaThreshold: alphaThreshold)
    }

    static func connectedComponents(px: [UInt8], w: Int, h: Int, alphaThreshold: UInt8) -> [Blob] {
        var visited = [Bool](repeating: false, count: w * h)
        var blobs: [Blob] = []
        var stack: [Int] = []
        stack.reserveCapacity(1024)

        for start in 0..<(w * h) {
            guard !visited[start], px[start * 4 + 3] >= alphaThreshold else { continue }
            // flood-fill (명시적 스택 — 재귀 금지: 큰 blob 에서 스택오버플로 방지).
            visited[start] = true
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            var minX = w, minY = h, maxX = -1, maxY = -1
            var area = 0
            var sumX = 0.0
            while let idx = stack.popLast() {
                let x = idx % w, y = idx / w
                area += 1
                sumX += Double(x)
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
                // 8-이웃(안티앨리어싱 대각 연결 보존).
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < h else { continue }
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx
                        guard nx >= 0, nx < w else { continue }
                        let nIdx = ny * w + nx
                        if !visited[nIdx], px[nIdx * 4 + 3] >= alphaThreshold {
                            visited[nIdx] = true
                            stack.append(nIdx)
                        }
                    }
                }
            }
            blobs.append(Blob(minX: minX, minY: minY, maxX: maxX, maxY: maxY,
                              area: area, xCentroid: sumX / Double(area)))
        }
        return blobs
    }

    /// 프레임 그룹의 union bbox 들(x중심 오름차순, top-left 좌표).
    ///
    /// - Throws: `ExtractError.frameCountMismatch` — blob 수 < frameCount (silent fallback 금지).
    public static func frameBoxes(_ image: CGImage, frameCount: Int,
                                  alphaThreshold: UInt8 = 24) throws -> [CGRect] {
        guard let buf = PixelOps.readRGBA(image) else { throw ExtractError.bitmapUnavailable }
        let blobs = connectedComponents(px: buf.px, w: buf.w, h: buf.h, alphaThreshold: alphaThreshold)
        guard frameCount > 0, blobs.count >= frameCount else {
            throw ExtractError.frameCountMismatch(found: blobs.count, expected: frameCount)
        }

        // 면적 상위 frameCount 개 = seed → x중심 순 정렬.
        let byArea = blobs.indices.sorted { blobs[$0].area > blobs[$1].area }
        let seedSet = Set(byArea.prefix(frameCount))
        let seeds = byArea.prefix(frameCount).sorted { blobs[$0].xCentroid < blobs[$1].xCentroid }

        // 그룹 union bbox 초기화 = seed bbox.
        var unions = seeds.map { blobs[$0] }
        // 나머지 blob 흡수 — **bbox 간극(gap) 우선, centroid 는 최후 tie-break**.
        //
        // centroid-only 귀속의 실패 모드(인간 관측: atk3 검기 파편 오귀속):
        // 검기 아크는 본체에서 뻗어나가는 얇은 꼬리 + 끝쪽 플레어라서 질량 중심이
        // 이웃 seed 쪽으로 쏠린다. 하지만 파편의 bbox 는 자기 프레임 본체에
        // 접촉(또는 최소 간극)한다 → 기준 순서:
        // 1) seed(원본 bbox)와의 2D 간극 거리 최소
        // 2) 간극 동률(겹침 포함)이면 겹침 면적 최대
        // 3) 그래도 동률이면 x중심 거리 최소
        for i in blobs.indices where !seedSet.contains(i) {
            let b = blobs[i]
            var best = 0
            var bestGap = Double.infinity
            var bestOverlap = -Double.infinity
            var bestCentroid = Double.infinity
            for (gi, si) in seeds.enumerated() {
                let s = blobs[si]
                let gx = Double(max(0, max(s.minX - b.maxX, b.minX - s.maxX)))
                let gy = Double(max(0, max(s.minY - b.maxY, b.minY - s.maxY)))
                let gap = (gx * gx + gy * gy).squareRoot()
                let ow = Double(min(s.maxX, b.maxX) - max(s.minX, b.minX) + 1)
                let oh = Double(min(s.maxY, b.maxY) - max(s.minY, b.minY) + 1)
                let overlap = max(0, ow) * max(0, oh)
                let cd = abs(s.xCentroid - b.xCentroid)
                let better = gap < bestGap
                    || (gap == bestGap && overlap > bestOverlap)
                    || (gap == bestGap && overlap == bestOverlap && cd < bestCentroid)
                if better { best = gi; bestGap = gap; bestOverlap = overlap; bestCentroid = cd }
            }
            unions[best].minX = min(unions[best].minX, b.minX)
            unions[best].minY = min(unions[best].minY, b.minY)
            unions[best].maxX = max(unions[best].maxX, b.maxX)
            unions[best].maxY = max(unions[best].maxY, b.maxY)
        }
        return unions.map(\.bbox)
    }

    /// 프레임 CGImage 배열(왼쪽→오른쪽) 추출.
    ///
    /// - Throws: `ExtractError.frameCountMismatch` / `.bitmapUnavailable`.
    public static func extractFrames(_ image: CGImage, frameCount: Int,
                                     alphaThreshold: UInt8 = 24) throws -> [CGImage] {
        let boxes = try frameBoxes(image, frameCount: frameCount, alphaThreshold: alphaThreshold)
        return try boxes.map { box in
            guard let crop = image.cropping(to: box) else { throw ExtractError.bitmapUnavailable }
            return crop
        }
    }
}
