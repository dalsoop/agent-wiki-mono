import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 가로 스프라이트 시트를 균등 프레임으로 자르고, 프레임 겹쳐보기(onion skin)로 일관성을 검증한다.
///
/// SpriteKit 게임의 `SpriteSheet.slice` 와 같은 규칙(균등 N분할)을 앱/CLI 에서 재사용한다.
public enum SpriteSlicer {
    /// 시트를 로드한다.
    public static func load(_ path: String) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    /// 가로로 frames 등분해 각 프레임 CGImage 를 반환.
    public static func slice(_ image: CGImage, frames: Int) -> [CGImage] {
        guard frames > 0 else { return [] }
        let w = image.width / frames
        let h = image.height
        guard w > 0 else { return [] }
        return (0..<frames).compactMap { i in
            image.cropping(to: CGRect(x: i * w, y: 0, width: w, height: h))
        }
    }

    /// 프레임 간 실루엣 드리프트를 0~1 로 계량한다(0=완전 일치).
    ///
    /// 각 프레임의 알파 마스크를 이진화해 인접 프레임과 XOR 비율의 평균을 낸다.
    /// 값이 크면 캐릭터 중심/크기가 프레임마다 튄다는 신호(검수 게이트).
    public static func silhouetteDrift(_ frames: [CGImage], alphaThreshold: UInt8 = 32) -> Double {
        guard frames.count >= 2 else { return 0 }
        let masks = frames.compactMap { alphaMask($0, threshold: alphaThreshold) }
        guard masks.count == frames.count else { return 0 }
        let w = masks.map(\.w).min() ?? 0
        let h = masks.map(\.h).min() ?? 0
        guard w > 0, h > 0 else { return 0 }

        var total = 0.0
        for i in 1..<masks.count {
            let a = masks[i - 1], b = masks[i]
            var diff = 0, count = 0
            for y in 0..<h {
                for x in 0..<w {
                    let av = a.bits[y * a.w + x]
                    let bv = b.bits[y * b.w + x]
                    if av != bv { diff += 1 }
                    count += 1
                }
            }
            total += count > 0 ? Double(diff) / Double(count) : 0
        }
        return total / Double(masks.count - 1)
    }

    struct Mask { let w: Int; let h: Int; let bits: [Bool] }

    static func alphaMask(_ image: CGImage, threshold: UInt8) -> Mask? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var bits = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            bits[i] = pixels[i * 4 + 3] >= threshold
        }
        return Mask(w: w, h: h, bits: bits)
    }

    /// CGImage 를 PNG 로 저장.
    @discardableResult
    public static func writePNG(_ image: CGImage, to path: String) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
