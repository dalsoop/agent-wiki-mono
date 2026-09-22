import Foundation
import CoreGraphics

/// 스프라이트 시트의 **프레임 간 캐릭터 드리프트**를 정량 검수한다.
///
/// gpt-image/god-tibo 는 확률적이라 한 시트 안에서도 프레임마다 캐릭터 크기·발 위치·좌우 중심이
/// 미세하게 흔들린다(onion-skin 으로 눈으로 잡던 것). 이 분석기는 각 프레임의 콘텐츠 bbox(알파 기준)를
/// 뽑아 높이/발밑(baseline)/x중심의 편차를 수치로 내, 재생성·수보정 신호를 자동으로 만든다.
///
/// 균등 열 분할 전제(생성 규칙이 "even spacing · shared baseline · same canvas size" 를 강제하므로 유효).
public enum FrameDrift {
    /// 프레임 1개의 콘텐츠 계측(프레임 로컬 좌표, top-left 원점).
    public struct FrameMetric: Sendable, Equatable {
        public let index: Int
        /// 콘텐츠 없음(빈 프레임) 여부.
        public let empty: Bool
        public let contentHeight: Int
        public let contentWidth: Int
        /// 콘텐츠 하단 y(발밑). 프레임 하단과의 거리 = 발 앵커 흔들림 관측점.
        public let bottom: Int
        /// 콘텐츠 x중심(프레임 폭 대비 0~1).
        public let centroidXRatio: Double
    }

    public struct Report: Sendable, Equatable {
        public let frames: [FrameMetric]
        /// 캐릭터 높이 편차 비율 (max-min)/max. 0=완전동일, 클수록 크기 흔들림.
        public let heightDriftRatio: Double
        /// 발밑(bottom) 편차 픽셀. 클수록 캐릭터가 위아래로 떠다님.
        public let baselineDriftPx: Int
        /// x중심 비율 편차(max-min). 클수록 좌우로 밀림.
        public let centroidDriftRatio: Double
        /// 빈 프레임이 하나라도 있으면 true(생성 실패 신호).
        public let hasEmptyFrame: Bool

        /// 기본 임계 초과 여부 — true 면 재생성/수보정 권고.
        public func flagged(heightRatio: Double = 0.12,
                            baselinePx: Int = 6,
                            centroidRatio: Double = 0.10) -> Bool {
            hasEmptyFrame
                || heightDriftRatio > heightRatio
                || baselineDriftPx > baselinePx
                || centroidDriftRatio > centroidRatio
        }
    }

    /// CGImage 시트를 `frames` 개 균등 열로 나눠 드리프트를 계측한다.
    public static func analyze(_ image: CGImage, frames: Int, alphaThreshold: UInt8 = 24) -> Report? {
        guard frames > 0, let buf = PixelOps.readRGBA(image) else { return nil }
        return analyze(px: buf.px, w: buf.w, h: buf.h, frames: frames, alphaThreshold: alphaThreshold)
    }

    /// 순수 계산(테스트용): RGBA 버퍼(w*h*4, 알파는 각 픽셀 4번째 바이트) 기준.
    public static func analyze(px: [UInt8], w: Int, h: Int, frames: Int, alphaThreshold: UInt8) -> Report? {
        guard frames > 0, w >= frames, h > 0, px.count >= w * h * 4 else { return nil }
        let cellW = w / frames
        var metrics: [FrameMetric] = []
        metrics.reserveCapacity(frames)

        for f in 0..<frames {
            let x0 = f * cellW
            let x1 = (f == frames - 1) ? w : x0 + cellW   // 마지막 프레임은 잉여 폭 흡수
            var minY = Int.max, maxX = -1, minX = Int.max, maxY = -1
            var sumX = 0, count = 0
            for y in 0..<h {
                let row = y * w * 4
                for x in x0..<x1 {
                    let a = px[row + x * 4 + 3]
                    if a >= alphaThreshold {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                        sumX += (x - x0)
                        count += 1
                    }
                }
            }
            if count == 0 {
                metrics.append(FrameMetric(index: f, empty: true, contentHeight: 0,
                                           contentWidth: 0, bottom: h, centroidXRatio: 0.5))
            } else {
                let localW = x1 - x0
                metrics.append(FrameMetric(
                    index: f, empty: false,
                    contentHeight: maxY - minY + 1,
                    contentWidth: maxX - minX + 1,
                    bottom: maxY,
                    centroidXRatio: Double(sumX) / Double(count) / Double(max(localW - 1, 1))))
            }
        }

        let nonEmpty = metrics.filter { !$0.empty }
        let heights = nonEmpty.map(\.contentHeight)
        let bottoms = nonEmpty.map(\.bottom)
        let centroids = nonEmpty.map(\.centroidXRatio)

        let maxH = heights.max() ?? 0
        let heightDrift = maxH > 0 ? Double(maxH - (heights.min() ?? maxH)) / Double(maxH) : 0
        let baselineDrift = bottoms.isEmpty ? 0 : (bottoms.max()! - bottoms.min()!)
        let centroidDrift = centroids.isEmpty ? 0 : (centroids.max()! - centroids.min()!)

        return Report(
            frames: metrics,
            heightDriftRatio: heightDrift,
            baselineDriftPx: baselineDrift,
            centroidDriftRatio: centroidDrift,
            hasEmptyFrame: metrics.contains(where: \.empty))
    }
}
