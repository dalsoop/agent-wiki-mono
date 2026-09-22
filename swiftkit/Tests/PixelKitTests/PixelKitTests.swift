import XCTest
import CoreGraphics
import CommandKit
@testable import PixelKit

/// magick/rembg/pngquant 흉내: identify 는 크기 문자열, 그 외엔 마지막 .png 인자에 파일 생성.
final class MockCmd: CommandRunning, @unchecked Sendable {
    var calls: [[String]] = []
    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        // /usr/bin/env 로 감싸일 수 있으니 실제 인자만 기록.
        let args = arguments.first == "magick" || arguments.first == "rembg" || arguments.first == "pngquant"
            ? Array(arguments.dropFirst()) : arguments
        calls.append(arguments)
        if arguments.contains("identify") {
            return CommandResult(stdout: "64 64", stderr: "", exitCode: 0)
        }
        if let last = args.last, last.hasSuffix(".png") {
            FileManager.default.createFile(atPath: last, contents: Data([0x89, 0x50]))
        }
        return CommandResult(stdout: "", stderr: "", exitCode: 0)
    }
}

final class PixelKitTests: XCTestCase {
    /// width×height RGBA 이미지 생성(alpha 채운 사각형).
    func makeImage(width: Int, height: Int, fillRect: CGRect) -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(fillRect)
        return ctx.makeImage()!
    }

    // MARK: - FrameDrift

    /// w×h RGBA 버퍼. rects[f] = 프레임 f 의 (x0,y0,x1,y1) 채움 영역(전역 좌표, 알파 255).
    private func driftBuffer(w: Int, h: Int, rects: [(Int, Int, Int, Int)]) -> [UInt8] {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for (x0, y0, x1, y1) in rects {
            for y in y0..<y1 {
                for x in x0..<x1 {
                    px[(y * w + x) * 4 + 3] = 255
                }
            }
        }
        return px
    }

    func testFrameDriftLowForIdenticalFrames() {
        // 8x8, 2프레임(cellW 4). 두 프레임 동일 위치/크기 사각형.
        let px = driftBuffer(w: 8, h: 8, rects: [(1, 2, 3, 7), (5, 2, 7, 7)])
        let r = FrameDrift.analyze(px: px, w: 8, h: 8, frames: 2, alphaThreshold: 24)!
        XCTAssertEqual(r.heightDriftRatio, 0, accuracy: 0.0001)
        XCTAssertEqual(r.baselineDriftPx, 0)
        XCTAssertEqual(r.centroidDriftRatio, 0, accuracy: 0.0001)
        XCTAssertFalse(r.hasEmptyFrame)
        XCTAssertFalse(r.flagged())
    }

    func testFrameDriftFlagsHeightAndBaselineDrift() {
        // 프레임0 높이 5(y2..6), 프레임1 높이 2(y2..3) → 높이·발밑 크게 어긋남.
        let px = driftBuffer(w: 8, h: 8, rects: [(1, 2, 3, 7), (5, 2, 7, 4)])
        let r = FrameDrift.analyze(px: px, w: 8, h: 8, frames: 2, alphaThreshold: 24)!
        XCTAssertGreaterThan(r.heightDriftRatio, 0.12)
        XCTAssertGreaterThan(r.baselineDriftPx, 0)
        XCTAssertTrue(r.flagged())
    }

    // MARK: - PostProcessor palette-lock

    func testPaletteLockEmitsColorsWhenSet() async throws {
        let dir = NSTemporaryDirectory() + "pp_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let raw = dir + "/idle.png"
        FileManager.default.createFile(atPath: raw, contents: Data([0x89, 0x50]))
        let mock = MockCmd()
        let pp = PostProcessor(runner: mock)
        let out = await pp.process(raw: raw, outDir: dir,
                                   options: .init(removeBackground: false, paletteColors: 16))
        XCTAssertTrue(out.ok)
        // 16색 공유 팔레트 락 호출이 있어야 한다.
        XCTAssertTrue(mock.calls.contains { $0.contains("-colors") && $0.contains("16") },
                      "palette-lock (-colors 16) 호출 없음: \(mock.calls)")
    }

    func testPaletteLockSkippedWhenNil() async throws {
        let dir = NSTemporaryDirectory() + "pp_\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let raw = dir + "/idle.png"
        FileManager.default.createFile(atPath: raw, contents: Data([0x89, 0x50]))
        let mock = MockCmd()
        let pp = PostProcessor(runner: mock)
        _ = await pp.process(raw: raw, outDir: dir, options: .init(removeBackground: false))
        XCTAssertFalse(mock.calls.contains { $0.contains("-colors") },
                       "paletteColors nil 인데 -colors 호출됨")
    }

    // MARK: - PaletteQuantizer

    func testQuantizeCollapsesToTargetColorCountAndKeepsAlpha() {
        // 4픽셀: 두 그룹의 비슷한 색(≈검정 2개, ≈흰색 2개) + 투명 1개 → 2색으로 수렴.
        var px = [UInt8]()
        func add(_ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8) { px += [r, g, b, a] }
        add(10, 10, 10, 255); add(14, 12, 9, 255)          // ≈검정
        add(240, 245, 250, 255); add(250, 248, 244, 255)   // ≈흰색
        add(0, 0, 0, 0)                                     // 투명(remap 제외)
        let out = PaletteQuantizer.quantize(px: px, w: 5, h: 1, colors: 2, alphaThreshold: 24)!
        // 불투명 픽셀의 distinct 색 ≤ 2.
        var colors = Set<UInt32>()
        for i in stride(from: 0, to: 5 * 4, by: 4) where out[i + 3] > 24 {
            colors.insert(UInt32(out[i]) << 16 | UInt32(out[i + 1]) << 8 | UInt32(out[i + 2]))
        }
        XCTAssertLessThanOrEqual(colors.count, 2)
        // 투명 픽셀은 그대로.
        XCTAssertEqual(out[16 + 3], 0)
        // 두 그룹이 서로 다른 색으로 남았는지(뭉개져 1색 되지 않음).
        XCTAssertEqual(colors.count, 2)
    }

    func testQuantizeNoOpaquePixelsReturnsInput() {
        let px = [UInt8](repeating: 0, count: 4 * 4)  // 전부 투명
        let out = PaletteQuantizer.quantize(px: px, w: 4, h: 1, colors: 8, alphaThreshold: 24)!
        XCTAssertEqual(out, px)
    }

    func testFrameDriftDetectsEmptyFrame() {
        // 프레임1 비어있음 → 생성 실패 신호.
        let px = driftBuffer(w: 8, h: 8, rects: [(1, 2, 3, 7)])
        let r = FrameDrift.analyze(px: px, w: 8, h: 8, frames: 2, alphaThreshold: 24)!
        XCTAssertTrue(r.hasEmptyFrame)
        XCTAssertTrue(r.flagged())
        XCTAssertTrue(r.frames[1].empty)
    }

    func testSliceCountAndSize() {
        let img = makeImage(width: 80, height: 20, fillRect: CGRect(x: 0, y: 0, width: 80, height: 20))
        let frames = SpriteSlicer.slice(img, frames: 4)
        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(frames[0].width, 20)
        XCTAssertEqual(frames[0].height, 20)
    }

    func testSliceZeroFrames() {
        let img = makeImage(width: 10, height: 10, fillRect: .init(x: 0, y: 0, width: 10, height: 10))
        XCTAssertTrue(SpriteSlicer.slice(img, frames: 0).isEmpty)
    }

    func testDriftZeroForIdenticalFrames() {
        // 같은 사각형 4개 → 드리프트 0.
        let img = makeImage(width: 40, height: 10, fillRect: CGRect(x: 0, y: 0, width: 40, height: 10))
        let frames = SpriteSlicer.slice(img, frames: 4)
        XCTAssertEqual(SpriteSlicer.silhouetteDrift(frames), 0, accuracy: 0.001)
    }

    func testContentBoxFindsFilledRegion() {
        // 40x20 캔버스에 (10,4)~(19,15) 사각형 → bbox top-left (10,4,10,12).
        let img = makeImage(width: 40, height: 20, fillRect: CGRect(x: 10, y: 4, width: 10, height: 12))
        let box = FrameNormalizer.contentBox(img, threshold: 16)
        XCTAssertEqual(box.width, 10)
        XCTAssertEqual(box.height, 12)
        XCTAssertEqual(box.minX, 10)
    }

    func testNormalizeCrossSheetConsistentHeight() {
        // 별개 두 시트(각 1프레임): 하나는 캐릭터 높이 16, 하나는 8. 서로 다른 스케일로 생성된 상황.
        let opts = FrameNormalizer.Options(cellW: 32, cellH: 40, targetCharHeight: 30, baselineFromBottom: 2)
        let big = makeImage(width: 20, height: 20, fillRect: CGRect(x: 6, y: 2, width: 6, height: 16))
        let small = makeImage(width: 20, height: 20, fillRect: CGRect(x: 6, y: 6, width: 6, height: 8))

        let outBig = FrameNormalizer.normalize(big, frames: 1, options: opts)!
        let outSmall = FrameNormalizer.normalize(small, frames: 1, options: opts)!
        XCTAssertEqual(outBig.width, 32); XCTAssertEqual(outBig.height, 40)

        let hBig = FrameNormalizer.contentBox(outBig, threshold: 24).height
        let hSmall = FrameNormalizer.contentBox(outSmall, threshold: 24).height
        // 둘 다 목표 높이 30 근처로 수렴 → 애니 간 캐릭터 크기 일정.
        XCTAssertEqual(hBig, 30, accuracy: 3)
        XCTAssertEqual(hSmall, 30, accuracy: 3)
    }

    func testDriftPositiveWhenShapesDiffer() {
        // 프레임마다 채운 위치가 다르면 드리프트 > 0.
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8,
                            bytesPerRow: 20 * 4, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 5, height: 10))     // 좌측 프레임: 왼쪽 채움
        ctx.fill(CGRect(x: 15, y: 0, width: 5, height: 10))    // 우측 프레임: 오른쪽 채움
        let img = ctx.makeImage()!
        let frames = SpriteSlicer.slice(img, frames: 2)
        XCTAssertGreaterThan(SpriteSlicer.silhouetteDrift(frames), 0.1)
    }
}
