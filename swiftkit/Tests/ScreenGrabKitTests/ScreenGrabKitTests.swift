import XCTest
import CoreGraphics
@testable import ScreenGrabKit

final class ScreenGrabKitTests: XCTestCase {
    func testPixelRectScales() {
        let rect = CaptureGeometry.pixelRect(
            selection: CGRect(x: 10, y: 20, width: 100, height: 50),
            displayHeightPoints: 900,
            scale: 2
        )
        XCTAssertEqual(rect, CGRect(x: 20, y: 40, width: 200, height: 100))
    }

    func testPNGEncodeProducesData() throws {
        // 1x1 흰 픽셀 CGImage.
        let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        let image = ctx.makeImage()!
        // "데이터가 나왔다" 가 "PNG 가 나왔다" 가 되려면 매직 넘버까지 봐야 한다.
        let png = try XCTUnwrap(ScreenGrabEncoder.pngData(image))
        let jpeg = try XCTUnwrap(ScreenGrabEncoder.jpegData(image, quality: 0.5))
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "PNG 시그니처")
        XCTAssertEqual(Array(jpeg.prefix(2)), [0xFF, 0xD8], "JPEG SOI 마커")
    }
}
