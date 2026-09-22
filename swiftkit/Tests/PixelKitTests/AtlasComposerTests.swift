import XCTest
import CoreGraphics
@testable import PixelKit

final class AtlasComposerTests: XCTestCase {
    func makeSheet(width: Int, height: Int) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }

    func testComposeGridGeometry() {
        // idle 8f 소스(가로 8*24=192), atk 5f 소스 → 셀 96×128 그리드.
        let idle = makeSheet(width: 8 * 24, height: 32)
        let atk = makeSheet(width: 5 * 24, height: 32)
        let out = AtlasComposer.compose(
            motions: [
                .init(name: "idle", sheet: idle, frames: 8, fps: 8, loop: true),
                .init(name: "atk", sheet: atk, frames: 5, fps: 12, loop: false),
            ],
            cellWidth: 96, cellHeight: 128)
        let r = try! XCTUnwrap(out)
        // 시트 = maxFrames(8)*96 × rows(2)*128.
        XCTAssertEqual(r.manifest.frame_layout.sheetWidth, 8 * 96)
        XCTAssertEqual(r.manifest.frame_layout.sheetHeight, 2 * 128)
        XCTAssertEqual(r.manifest.frame_layout.rows["idle"]?.count, 8)
        XCTAssertEqual(r.manifest.frame_layout.rows["atk"]?.count, 5)
        // provenance: fps/loop 보존.
        XCTAssertEqual(r.manifest.animation.rows["idle"]?.fps, 8)
        XCTAssertEqual(r.manifest.animation.rows["idle"]?.loop, true)
        XCTAssertEqual(r.manifest.animation.rows["atk"]?.loop, false)
    }

    func testFrameRectsTopLeftAndYFlipContract() {
        let idle = makeSheet(width: 4 * 24, height: 32)
        let out = try! XCTUnwrap(AtlasComposer.compose(
            motions: [.init(name: "idle", sheet: idle, frames: 4, fps: 8, loop: true)],
            cellWidth: 96, cellHeight: 128))
        let sheetH = out.manifest.frame_layout.sheetHeight
        let frames = try! XCTUnwrap(out.manifest.frame_layout.rows["idle"])
        // top-left 픽셀 좌표: 행 0 → y=0, 열 순차.
        XCTAssertEqual(frames[0].x, 0); XCTAssertEqual(frames[0].y, 0)
        XCTAssertEqual(frames[1].x, 96)
        // 게임 로더 y 반전 계약: normY = 1 - (y+h)/sheetH. 단일 행이므로 0 이어야.
        let f = frames[0]
        let normY = 1.0 - Double(f.y + f.h) / Double(sheetH)
        XCTAssertEqual(normY, 0.0, accuracy: 1e-9)
    }
}
