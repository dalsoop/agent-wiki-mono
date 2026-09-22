import Foundation
import CoreGraphics

/// PixelKit 내부 공용 RGBA 버퍼 IO.
///
/// 버퍼 규약: **premultipliedLast RGBA8, row 0 = 이미지 최상단(top-down)**.
/// (CGBitmapContext 에 `ctx.draw` 하면 메모리 row 0 이 이미지 상단이다 —
/// CG 좌표 y=0(하단)이 마지막 메모리 row 에 대응한다. 경험적으로 검증됨.)
/// `CGImage.cropping(to:)` 의 rect 도 top-left 원점이므로 이 규약과 일치한다.
enum PixelOps {
    /// 이미지를 top-down RGBA8(premultiplied) 버퍼로 읽는다.
    static func readRGBA(_ image: CGImage) -> (px: [UInt8], w: Int, h: Int)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        let ok = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? (px, w, h) : nil
    }

    /// top-down RGBA8(premultiplied) 버퍼로 CGImage 를 만든다.
    static func makeImage(px: [UInt8], w: Int, h: Int) -> CGImage? {
        guard w > 0, h > 0, px.count == w * h * 4 else { return nil }
        var copy = px
        let cs = CGColorSpaceCreateDeviceRGB()
        return copy.withUnsafeMutableBytes { raw -> CGImage? in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            return ctx.makeImage()
        }
    }

    /// 알파 ≥ threshold 픽셀의 bounding box(top-down 좌표). 없으면 nil.
    static func alphaBox(px: [UInt8], w: Int, h: Int, threshold: UInt8)
        -> (x: Int, y: Int, w: Int, h: Int)? {
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] >= threshold {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return (minX, minY, maxX - minX + 1, maxY - minY + 1)
    }
}

/// 크로마키 배경을 **soft-alpha unmix** 로 벗긴다 (외부 프로세스 없음, 순수 CoreGraphics).
///
/// - near-key(키색과 색거리 ≤ `keyThreshold`) → alpha 0 + RGB clear.
/// - 경계(안티앨리어싱 블렌드) 픽셀 → 키 거리 비례 **soft alpha** + **despill**
///   (물리적 unmix: `fg = (c − (1−a)·key) / a` — 키 성분을 제거한 원색 복원).
///   → rembg 류가 뜯어내는 머리카락·아웃라인의 반투명 경계를 보존한다.
/// - **검정 키 특례**: 캐릭터도 어두울 수 있으므로 색거리 대신
///   luminance(value)+채도(chroma) 결합 판정 — 채도가 있으면(어두운 유채색 갑옷 등)
///   보존하고 **순수 검정 배경만** 제거한다.
public enum ChromaKeyer {
    /// 키색(불투명 RGB).
    public struct KeyColor: Sendable, Equatable {
        public var r: UInt8
        public var g: UInt8
        public var b: UInt8
        public init(r: UInt8, g: UInt8, b: UInt8) { self.r = r; self.g = g; self.b = b }

        /// `#RRGGBB` / `RRGGBB` 파싱. 실패 시 nil.
        public init?(hex: String) {
            var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
            s = s.trimmingCharacters(in: .whitespaces)
            guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
            self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
        }

        /// 검정 키 판정(#000 근처).
        var isNearBlack: Bool { max(r, g, b) <= 40 }
    }

    public struct Options: Sendable {
        /// 명시 키색. nil 이면 모서리 4점 샘플로 자동 감지.
        public var keyColor: KeyColor?
        /// near-key 판정 색거리(유클리드 RGB). 이하 → alpha 0.
        public var keyThreshold: Double
        /// soft 경계 폭: 거리 (keyThreshold, keyThreshold+softness) 구간을 alpha 0→1 로 선형 매핑.
        public var softness: Double
        /// 검정 키: value+chroma 결합 점수가 이하이면 alpha 0.
        public var blackScoreThreshold: Double
        /// 검정 키: soft 경계 폭(점수 기준).
        public var blackSoftness: Double
        /// 검정 키: chroma(max−min)가 이를 넘으면 어두워도 캐릭터로 간주(완전 보존).
        public var blackChromaTolerance: Double
        public init(keyColor: KeyColor? = nil, keyThreshold: Double = 96, softness: Double = 64,
                    blackScoreThreshold: Double = 24, blackSoftness: Double = 40,
                    blackChromaTolerance: Double = 28) {
            self.keyColor = keyColor
            self.keyThreshold = keyThreshold
            self.softness = softness
            self.blackScoreThreshold = blackScoreThreshold
            self.blackSoftness = blackSoftness
            self.blackChromaTolerance = blackChromaTolerance
        }
    }

    /// 배경을 벗긴 투명 PNG 용 CGImage 를 반환. 실패(비트맵 생성 불가) 시 nil.
    public static func removeBackground(_ image: CGImage, options o: Options = .init()) -> CGImage? {
        guard var buf = PixelOps.readRGBA(image) else { return nil }
        let key = o.keyColor ?? detectKeyColor(px: buf.px, w: buf.w, h: buf.h, threshold: o.keyThreshold)
        let black = key.isNearBlack
        let kr = Double(key.r), kg = Double(key.g), kb = Double(key.b)
        let soft = max(1, o.softness)
        let blackSoft = max(1, o.blackSoftness)

        for i in 0..<(buf.w * buf.h) {
            let p = i * 4
            let a0 = Double(buf.px[p + 3]) / 255.0
            guard a0 > 0 else { continue }
            // premultiplied → straight (입력이 불투명 시트면 그대로).
            let r = Double(buf.px[p]) / a0, g = Double(buf.px[p + 1]) / a0, b = Double(buf.px[p + 2]) / a0

            let a: Double
            if black {
                // luminance+채도 결합: 순수 검정만 제거, 어두운 유채색은 보존.
                let v = max(r, g, b), chroma = v - min(r, g, b)
                if chroma > o.blackChromaTolerance {
                    a = 1
                } else {
                    let score = v + 1.5 * chroma
                    a = min(1, max(0, (score - o.blackScoreThreshold) / blackSoft))
                }
            } else {
                let d = ((r - kr) * (r - kr) + (g - kg) * (g - kg) + (b - kb) * (b - kb)).squareRoot()
                a = min(1, max(0, (d - o.keyThreshold) / soft))
            }

            let outA = a * a0
            if outA <= 0 {
                buf.px[p] = 0; buf.px[p + 1] = 0; buf.px[p + 2] = 0; buf.px[p + 3] = 0
            } else if a < 1 {
                // unmix(despill): fg = (c − (1−a)·key)/a → premultiplied 저장 = fg·a.
                func unmix(_ c: Double, _ k: Double) -> UInt8 {
                    let fg = min(255, max(0, (c - (1 - a) * k) / a))
                    return UInt8((fg * outA).rounded())
                }
                buf.px[p] = unmix(r, kr)
                buf.px[p + 1] = unmix(g, kg)
                buf.px[p + 2] = unmix(b, kb)
                buf.px[p + 3] = UInt8((outA * 255).rounded())
            }
            // a >= 1: 원본 유지.
        }
        return PixelOps.makeImage(px: buf.px, w: buf.w, h: buf.h)
    }

    /// 모서리 4점(3×3 패치 평균) 샘플 → 다수결(threshold 내 상호 일치가 가장 많은 색)의 평균.
    static func detectKeyColor(px: [UInt8], w: Int, h: Int, threshold: Double) -> KeyColor {
        func patch(_ cx: Int, _ cy: Int) -> (Double, Double, Double) {
            var r = 0.0, g = 0.0, b = 0.0, n = 0.0
            for dy in -1...1 {
                for dx in -1...1 {
                    let x = min(max(cx + dx, 0), w - 1), y = min(max(cy + dy, 0), h - 1)
                    let p = (y * w + x) * 4
                    let a = Double(px[p + 3]) / 255.0
                    guard a > 0 else { continue }
                    r += Double(px[p]) / a; g += Double(px[p + 1]) / a; b += Double(px[p + 2]) / a
                    n += 1
                }
            }
            guard n > 0 else { return (0, 0, 0) }
            return (r / n, g / n, b / n)
        }
        let corners = [patch(0, 0), patch(w - 1, 0), patch(0, h - 1), patch(w - 1, h - 1)]
        func dist(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
            ((a.0 - b.0) * (a.0 - b.0) + (a.1 - b.1) * (a.1 - b.1) + (a.2 - b.2) * (a.2 - b.2)).squareRoot()
        }
        // 각 후보에 동의(threshold 내)하는 모서리 수 → 최다 득표 후보 진영의 평균.
        var best = corners[0], bestVotes = -1
        for c in corners {
            let votes = corners.filter { dist($0, c) <= threshold }.count
            if votes > bestVotes { bestVotes = votes; best = c }
        }
        let agreeing = corners.filter { dist($0, best) <= threshold }
        let n = Double(agreeing.count)
        let avg = agreeing.reduce((0.0, 0.0, 0.0)) { ($0.0 + $1.0, $0.1 + $1.1, $0.2 + $1.2) }
        return KeyColor(r: UInt8(min(255, max(0, avg.0 / n)).rounded()),
                        g: UInt8(min(255, max(0, avg.1 / n)).rounded()),
                        b: UInt8(min(255, max(0, avg.2 / n)).rounded()))
    }
}
