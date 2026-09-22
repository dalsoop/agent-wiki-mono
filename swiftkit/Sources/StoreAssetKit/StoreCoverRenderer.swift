import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// 스토어 상품 표지(썸네일) 렌더러 — 함대 공용 자산 축.
///
/// 스킬 제품처럼 실행 UI 가 없는 제품은 캡처로 스크린샷을 만들 수 없다.
/// 제품명·태그라인으로 브랜드 표지 PNG 를 그려 주는 것이 이 렌더러의 소관이고,
/// 리스팅 원장 연결(`ensureCovers`)은 소비 앱이 자기 모델에 맞춰 얹는다.
/// GUI·CLI 가 같은 경로를 쓴다. `*Core` 층에서도 링크하므로 AppKit 을 쓰지 않는다.
public enum StoreCoverRenderer {

    /// 렌더 지오메트리 — 포인트 기준(픽셀은 scale 배).
    private enum Layout {
        static let width: CGFloat = 1280
        static let height: CGFloat = 800
        static let scale: CGFloat = 2
        static let margin: CGFloat = 96
        static let maxTitleHeight: CGFloat = 320
        static let minTitleFontSize: CGFloat = 44
        static let titleFontSize: CGFloat = 104
        static let taglineFontSize: CGFloat = 38
        static let badgeFontSize: CGFloat = 30
        static let footerFontSize: CGFloat = 26
    }

    public static let pixelSize = CGSize(width: Layout.width, height: Layout.height)

    /// 표지 1장을 그려 `directory/<slug>-<variant>.png` 로 저장하고 URL 을 돌려준다.
    @discardableResult
    public static func render(
        slug: String,
        title: String,
        tagline: String,
        directory: URL,
        variant: Int
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(slug)-\(variant).png")

        let width = Int(Layout.width * Layout.scale)
        let height = Int(Layout.height * Layout.scale)
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "StoreCoverRenderer", code: 2, userInfo: [NSLocalizedDescriptionKey: "bitmap context init failed"])
        }
        context.scaleBy(x: Layout.scale, y: Layout.scale)

        drawBackground(context, variant: variant)
        drawBadge(context, kind: "GUJO SKILL")
        drawTitle(context, title)
        drawTagline(context, tagline)
        drawFooter(context, slug)

        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        guard let destination else {
            throw NSError(domain: "StoreCoverRenderer", code: 3, userInfo: [NSLocalizedDescriptionKey: "image destination init failed"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "StoreCoverRenderer", code: 1, userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }
        return url
    }

    // MARK: - 드로잉

    private static let palette: [(CGColor, CGColor)] = [
        (CGColor(srgbRed: 0.07, green: 0.22, blue: 0.16, alpha: 1),
         CGColor(srgbRed: 0.11, green: 0.42, blue: 0.30, alpha: 1)),
        (CGColor(srgbRed: 0.09, green: 0.15, blue: 0.28, alpha: 1),
         CGColor(srgbRed: 0.16, green: 0.35, blue: 0.52, alpha: 1)),
    ]

    private static func drawBackground(_ context: CGContext, variant: Int) {
        let pair = palette[(variant - 1) % palette.count]
        let gradient = CGGradient(colorsSpace: nil, colors: [pair.0, pair.1] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(
            gradient, start: CGPoint(x: 0, y: Layout.height),
            end: CGPoint(x: Layout.width, y: 0), options: []
        )
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.06))
        context.fillEllipse(in: CGRect(x: Layout.width * 0.55, y: Layout.height * 0.35,
                                       width: Layout.width * 0.7, height: Layout.width * 0.7))
    }

    private static func draw(_ context: CGContext, _ text: String, font: CTFont, color: CGColor, in rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
        CTFrameDraw(frame, context)
    }

    private static func drawBadge(_ context: CGContext, kind: String) {
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, Layout.badgeFontSize, nil)
        let size = textSize(kind, font: font)
        let rect = CGRect(x: Layout.margin, y: Layout.height - 170, width: size.width + 44, height: size.height + 22)
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
        let badge = CGPath(roundedRect: rect, cornerWidth: rect.height / 2, cornerHeight: rect.height / 2, transform: nil)
        context.addPath(badge)
        context.fillPath()
        draw(context, kind, font: font, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85),
             in: CGRect(x: rect.minX + 22, y: rect.minY + 8, width: size.width + 4, height: size.height + 4))
    }

    private static func drawTitle(_ context: CGContext, _ title: String) {
        let maxWidth = Layout.width - Layout.margin * 2
        var fontSize = Layout.titleFontSize
        var font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
        var bounds = textSize(title, font: font, maxWidth: maxWidth)
        repeat {
            font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, fontSize, nil)
            bounds = textSize(title, font: font, maxWidth: maxWidth)
            fontSize -= 6
        } while bounds.height > Layout.maxTitleHeight && fontSize > Layout.minTitleFontSize
        let blockY = Layout.height * 0.42 - bounds.height / 2
        draw(context, title, font: font, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
             in: CGRect(x: Layout.margin, y: blockY, width: maxWidth, height: bounds.height + 20))
    }

    private static func drawTagline(_ context: CGContext, _ tagline: String) {
        guard !tagline.isEmpty else { return }
        let font = CTFontCreateWithName("HelveticaNeue-Medium" as CFString, Layout.taglineFontSize, nil)
        let maxWidth = Layout.width - Layout.margin * 2
        let bounds = textSize(tagline, font: font, maxWidth: maxWidth)
        let blockY = Layout.height * 0.42 - bounds.height / 2 - 130
        draw(context, tagline, font: font, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.82),
             in: CGRect(x: Layout.margin, y: blockY, width: maxWidth, height: bounds.height + 20))
    }

    private static func drawFooter(_ context: CGContext, _ slug: String) {
        let font = CTFontCreateWithName("Menlo-Regular" as CFString, Layout.footerFontSize, nil)
        draw(context, slug, font: font, color: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.55),
             in: CGRect(x: Layout.margin, y: 66, width: Layout.width / 2, height: Layout.footerFontSize + 10))
    }

    private static func textSize(_ text: String, font: CTFont, maxWidth: CGFloat? = nil) -> CGRect {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let target = CGSize(width: maxWidth ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
            framesetter, CFRange(location: 0, length: attributed.length), nil, target, nil
        )
        return CGRect(origin: .zero, size: suggested)
    }
}
