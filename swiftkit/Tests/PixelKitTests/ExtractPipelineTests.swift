import XCTest
import CoreGraphics
@testable import PixelKit

/// ChromaKeyer · FrameExtractor · FrameNormalizer(개선) — extract 네이티브 엔진 테스트.
/// 모든 픽셀 헬퍼는 top-down(row 0 = 최상단) RGBA8 규약을 쓴다.
final class ExtractPipelineTests: XCTestCase {
    // MARK: - 픽셀 헬퍼 (테스트 자체 구현 — 블랙박스 검증)

    /// top-down RGBA 버퍼(불투명/완전투명만 사용해 premultiplied 이슈 회피)로 CGImage 생성.
    func makeImage(w: Int, h: Int, paint: (inout [UInt8]) -> Void) -> CGImage {
        var px = [UInt8](repeating: 0, count: w * h * 4)
        paint(&px)
        let cs = CGColorSpaceCreateDeviceRGB()
        return px.withUnsafeMutableBytes { raw -> CGImage in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            return ctx.makeImage()!
        }
    }

    func set(_ px: inout [UInt8], _ w: Int, _ x: Int, _ y: Int,
             _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        let p = (y * w + x) * 4
        px[p] = r; px[p + 1] = g; px[p + 2] = b; px[p + 3] = a
    }

    func fillRect(_ px: inout [UInt8], _ w: Int, x: ClosedRange<Int>, y: ClosedRange<Int>,
                  _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        for yy in y { for xx in x { set(&px, w, xx, yy, r, g, b, a) } }
    }

    /// CGImage → top-down RGBA 버퍼.
    func readPx(_ image: CGImage) -> (px: [UInt8], w: Int, h: Int) {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        px.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (px, w, h)
    }

    func alpha(_ buf: (px: [UInt8], w: Int, h: Int), _ x: Int, _ y: Int) -> UInt8 {
        buf.px[(y * buf.w + x) * 4 + 3]
    }

    /// 부분 영역 알파 bbox(top-down, 영역 로컬 좌표). 없으면 nil.
    func regionBox(_ buf: (px: [UInt8], w: Int, h: Int), xRange: Range<Int>, threshold: UInt8 = 24)
        -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<buf.h {
            for x in xRange where buf.px[(y * buf.w + x) * 4 + 3] >= threshold {
                let lx = x - xRange.lowerBound
                minX = min(minX, lx); maxX = max(maxX, lx)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return (minX, minY, maxX, maxY)
    }

    // MARK: - ChromaKeyer

    func testChromaAutoKeyMagentaSoftAlphaAndDespill() {
        // 마젠타 배경 + 빨간 캐릭터 + 경계 블렌드 픽셀(50% 마젠타).
        let img = makeImage(w: 24, h: 16) { px in
            self.fillRect(&px, 24, x: 0...23, y: 0...15, 255, 0, 255)          // bg magenta
            self.fillRect(&px, 24, x: 6...13, y: 4...11, 220, 40, 40)          // char red
            self.set(&px, 24, 5, 8, 237, 20, 147)                              // 50% blend
        }
        guard let keyed = ChromaKeyer.removeBackground(img) else { return XCTFail("keying failed") }
        let out = readPx(keyed)
        // near-key → alpha 0 (자동 감지된 마젠타 키).
        XCTAssertEqual(alpha(out, 0, 0), 0)
        XCTAssertEqual(alpha(out, 23, 15), 0)
        XCTAssertEqual(alpha(out, 2, 8), 0)
        // 캐릭터 내부 → 완전 불투명 + 원색 유지.
        XCTAssertEqual(alpha(out, 9, 8), 255)
        XCTAssertEqual(out.px[(8 * 24 + 9) * 4], 220)
        // 경계 블렌드 → soft alpha (0 < a < 255).
        let edgeA = alpha(out, 5, 8)
        XCTAssertGreaterThan(edgeA, 0, "경계 픽셀이 통째로 제거됨(soft alpha 실패)")
        XCTAssertLessThan(edgeA, 255, "경계 픽셀이 불투명(soft alpha 실패)")
        // despill: 마젠타 성분(blue) 이 제거돼야 함(premultiplied 저장값 기준).
        let edgeB = out.px[(8 * 24 + 5) * 4 + 2]
        XCTAssertLessThan(edgeB, 50, "despill 실패 — 키(마젠타) 성분 잔존")
    }

    func testChromaBlackKeyKeepsDarkColoredCharacter() {
        // 검정 배경 + 어두운 파란 캐릭터(luminance 낮지만 채도 있음) + 회색 픽셀.
        let img = makeImage(w: 20, h: 12) { px in
            self.fillRect(&px, 20, x: 0...19, y: 0...11, 0, 0, 0)              // bg black
            self.fillRect(&px, 20, x: 4...9, y: 3...8, 30, 30, 90)             // dark blue char
            self.set(&px, 20, 12, 6, 160, 160, 160)                            // gray pixel
        }
        guard let keyed = ChromaKeyer.removeBackground(img) else { return XCTFail("keying failed") }
        let out = readPx(keyed)
        // 순수 검정 배경만 제거.
        XCTAssertEqual(alpha(out, 0, 0), 0)
        XCTAssertEqual(alpha(out, 19, 11), 0)
        // 어두운 유채색 캐릭터는 보존 (luminance+채도 결합 판정).
        XCTAssertEqual(alpha(out, 5, 5), 255, "어두운 유채색 캐릭터가 검정 키에 제거됨")
        XCTAssertEqual(out.px[(5 * 20 + 5) * 4 + 2], 90)
        // 밝은 회색도 보존.
        XCTAssertEqual(alpha(out, 12, 6), 255)
    }

    func testChromaExplicitKeyColor() {
        // 초록 배경, 명시 키.
        let img = makeImage(w: 10, h: 10) { px in
            self.fillRect(&px, 10, x: 0...9, y: 0...9, 0, 255, 0)
            self.fillRect(&px, 10, x: 3...6, y: 3...6, 200, 30, 30)
        }
        let opts = ChromaKeyer.Options(keyColor: .init(hex: "#00FF00"))
        guard let keyed = ChromaKeyer.removeBackground(img, options: opts) else { return XCTFail() }
        let out = readPx(keyed)
        XCTAssertEqual(alpha(out, 0, 0), 0)
        XCTAssertEqual(alpha(out, 4, 4), 255)
    }

    // MARK: - FrameExtractor

    func testExtractSeedsSortedAndNoiseAbsorbed() throws {
        // 90x32 캔버스, 3개 큰 blob(y 5..24 — 상하 비대칭으로 y-flip 버그 검출) +
        // 중간 blob 오른쪽의 2x2 노이즈(가로거리상 가운데 seed 로 흡수돼야 함).
        let img = makeImage(w: 90, h: 32) { px in
            self.fillRect(&px, 90, x: 5...14, y: 5...24, 255, 255, 255)
            self.fillRect(&px, 90, x: 35...44, y: 5...24, 255, 255, 255)
            self.fillRect(&px, 90, x: 65...74, y: 5...24, 255, 255, 255)
            self.fillRect(&px, 90, x: 48...49, y: 10...11, 255, 255, 255)      // noise → middle
        }
        let boxes = try FrameExtractor.frameBoxes(img, frameCount: 3)
        XCTAssertEqual(boxes.count, 3)
        // x중심 순 정렬.
        XCTAssertEqual(boxes[0].minX, 5); XCTAssertEqual(boxes[0].width, 10)
        XCTAssertEqual(boxes[2].minX, 65); XCTAssertEqual(boxes[2].width, 10)
        // 노이즈가 가운데 그룹에 흡수 → union bbox 35..49 (w=15).
        XCTAssertEqual(boxes[1].minX, 35)
        XCTAssertEqual(boxes[1].width, 15, "노이즈 blob 이 가장 가까운 seed 에 흡수되지 않음")
        // y 좌표는 top-left 원점(top-down) — flip 됐다면 32-1-24=7 이 나온다.
        XCTAssertEqual(boxes[0].minY, 5, "bbox y 가 상하 반전됨")
        XCTAssertEqual(boxes[0].height, 20)

        let frames = try FrameExtractor.extractFrames(img, frameCount: 3)
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(frames.map(\.width), [10, 15, 10])
        XCTAssertEqual(frames.map(\.height), [20, 20, 20])
    }

    func testExtractArcFragmentAssignedByBBoxGapNotCentroid() throws {
        // 인간 피드백 회귀(atk3 f2/f4 검기 파편 오귀속): 검기 아크 파편은
        // "얇은 꼬리(본체 인접) + 끝쪽 플레어(질량 집중)" 라서 x중심은 이웃 seed 에
        // 더 가깝지만, bbox 간극은 자기 프레임 본체 쪽이 가깝다.
        // centroid-only 귀속이면 B 로 오귀속(boxes[1].minX=23) — bbox 간극 기준이면 A.
        let img = makeImage(w: 100, h: 30) { px in
            self.fillRect(&px, 100, x: 10...20, y: 5...24, 255, 255, 255)   // seed A (본체)
            self.fillRect(&px, 100, x: 60...70, y: 5...24, 255, 255, 255)   // seed B (이웃 본체)
            // 파편(A 의 검기): 얇은 꼬리 x23..44(y8) + 플레어 x44..48(y6..15).
            // 질량중심 ≈ x42 → |42-15|=27 > |42-65|=23 (centroid 는 B 쪽).
            self.fillRect(&px, 100, x: 23...44, y: 8...8, 255, 255, 255)
            self.fillRect(&px, 100, x: 44...48, y: 6...15, 255, 255, 255)
        }
        let boxes = try FrameExtractor.frameBoxes(img, frameCount: 2)
        XCTAssertEqual(boxes.count, 2)
        // 파편이 A 그룹에 귀속 → A union = 10..48 (w=39).
        XCTAssertEqual(boxes[0].minX, 10)
        XCTAssertEqual(boxes[0].width, 39, "검기 파편이 자기 프레임(A)에 귀속되지 않음(centroid 오귀속)")
        // B 는 본체 그대로.
        XCTAssertEqual(boxes[1].minX, 60)
        XCTAssertEqual(boxes[1].width, 11, "파편이 이웃 프레임(B)에 오귀속됨")
    }

    func testExtractFloatingFragmentAboveOwnSeedUsesVerticalGap() throws {
        // 본체 바로 위에 뜬 파편(이펙트 잔광): x범위는 두 seed 중간이어도
        // 세로 간극까지 보는 2D gap 기준이면 자기 본체(겹치는 x구간) 쪽으로 귀속.
        let img = makeImage(w: 80, h: 40) { px in
            self.fillRect(&px, 80, x: 5...20, y: 15...34, 255, 255, 255)    // seed A
            self.fillRect(&px, 80, x: 55...70, y: 15...34, 255, 255, 255)   // seed B
            self.fillRect(&px, 80, x: 14...24, y: 4...8, 255, 255, 255)     // A 위 파편(x 겹침)
        }
        let boxes = try FrameExtractor.frameBoxes(img, frameCount: 2)
        XCTAssertEqual(boxes[0].minX, 5)
        XCTAssertEqual(boxes[0].minY, 4, "본체 위 파편이 자기 seed 에 귀속되지 않음")
        XCTAssertEqual(boxes[1].minX, 55)
        XCTAssertEqual(boxes[1].minY, 15)
    }

    func testExtractThrowsOnTooFewBlobs() {
        // blob 2개뿐인데 3프레임 요구 → frameCountMismatch (silent fallback 금지).
        let img = makeImage(w: 60, h: 20) { px in
            self.fillRect(&px, 60, x: 5...14, y: 5...14, 255, 255, 255)
            self.fillRect(&px, 60, x: 35...44, y: 5...14, 255, 255, 255)
        }
        XCTAssertThrowsError(try FrameExtractor.extractFrames(img, frameCount: 3)) { error in
            XCTAssertEqual(error as? FrameExtractor.ExtractError,
                           .frameCountMismatch(found: 2, expected: 3))
        }
    }

    func testExtractDiagonallyConnectedBlobIsOneComponent() throws {
        // 대각선으로만 이어진 픽셀(8-이웃)은 한 blob — 안티앨리어싱 실루엣 보존.
        let img = makeImage(w: 20, h: 10) { px in
            self.set(&px, 20, 3, 3, 255, 255, 255)
            self.set(&px, 20, 4, 4, 255, 255, 255)
            self.set(&px, 20, 5, 5, 255, 255, 255)
            self.fillRect(&px, 20, x: 12...15, y: 3...6, 255, 255, 255)
        }
        let frames = try FrameExtractor.extractFrames(img, frameCount: 2)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].width, 3)   // 대각선 blob 3x3
    }

    // MARK: - FrameNormalizer (개선)

    func testNormalizerWidthFitLowersWholeSheetScaleNoClipping() {
        // 프레임 A: 4x20 콘텐츠(키 큰 캐릭터), 프레임 B: 40x4 콘텐츠(넓은 이펙트).
        // heightScale=30/20=1.5 지만 B 폭 40 은 cellW-2=30 을 넘음 → 시트 전체 0.75 로 축소.
        let a = makeImage(w: 10, h: 24) { px in
            self.fillRect(&px, 10, x: 3...6, y: 2...21, 255, 255, 255)
        }
        let b = makeImage(w: 44, h: 8) { px in
            self.fillRect(&px, 44, x: 2...41, y: 2...5, 255, 255, 255)
        }
        let opts = FrameNormalizer.Options(cellW: 32, cellH: 40, targetCharHeight: 30,
                                           baselineFromBottom: 2)
        guard let out = FrameNormalizer.normalize(frames: [a, b], options: opts) else {
            return XCTFail("normalize failed")
        }
        XCTAssertEqual(out.width, 64); XCTAssertEqual(out.height, 40)
        let buf = readPx(out)
        // 셀 0(프레임 A): 전체 시트 스케일이 낮아져 목표높이(30) 미달 — 클리핑 대신 축소.
        let boxA = regionBox(buf, xRange: 0..<32)
        XCTAssertNotNil(boxA)
        XCTAssertEqual(boxA!.maxY - boxA!.minY + 1, 15, "전체 시트 스케일(0.75)이 적용돼야 함")
        // 셀 1(프레임 B): 폭이 cellW-2 이내 → 클리핑 없음(셀 경계에 닿지 않음).
        let boxB = regionBox(buf, xRange: 32..<64)
        XCTAssertNotNil(boxB)
        XCTAssertLessThanOrEqual(boxB!.maxX - boxB!.minX + 1, 30)
        XCTAssertGreaterThanOrEqual(boxB!.minX, 1, "콘텐츠가 셀 왼쪽 경계에 클리핑")
        XCTAssertLessThanOrEqual(boxB!.maxX, 30, "콘텐츠가 셀 오른쪽 경계에 클리핑")
        // 발 baseline 앵커: 콘텐츠 하단 = cellH - baseline - 1.
        XCTAssertEqual(boxA!.maxY, 37)
        XCTAssertEqual(boxB!.maxY, 37)
    }

    func testNormalizerAlignsByAlphaWeightedCentroid() {
        // 비대칭 콘텐츠: 왼쪽 무거운 블록(6칸) + 오른쪽 얇은 스트립(2칸).
        // 알파 가중 중심이 셀 중앙에 와야 함(bbox 중심 정렬이면 1px 이상 어긋남).
        let frame = makeImage(w: 20, h: 12) { px in
            self.fillRect(&px, 20, x: 0...5, y: 2...9, 255, 255, 255)
            self.fillRect(&px, 20, x: 8...9, y: 2...9, 255, 255, 255)
        }
        let opts = FrameNormalizer.Options(cellW: 32, cellH: 40, targetCharHeight: 16,
                                           baselineFromBottom: 2)
        guard let out = FrameNormalizer.normalize(frames: [frame], options: opts) else {
            return XCTFail("normalize failed")
        }
        let buf = readPx(out)
        // 출력 알파 가중 중심(α>10) 계산.
        var sum = 0.0, weight = 0.0
        for y in 0..<buf.h {
            for x in 0..<buf.w {
                let a = buf.px[(y * buf.w + x) * 4 + 3]
                guard a > 10 else { continue }
                sum += (Double(x) + 0.5) * Double(a); weight += Double(a)
            }
        }
        XCTAssertGreaterThan(weight, 0)
        let centroid = sum / weight
        // 셀 중앙 = 16. bbox 중심 정렬 구현이면 15.0 이 나와 실패한다.
        XCTAssertEqual(centroid, 16.0, accuracy: 0.6, "알파 가중 중심 정렬이 아님")
    }

    func testNormalizerIntegerNearestUpscale() {
        // scale 1.875 → 정수배 2 로 반올림(비정수 업스케일 금지). 콘텐츠 높이 = 16 이 아니라 8*2=16?
        // 8px 콘텐츠, 목표 15 → scale 1.875 → f=2 → 출력 높이 16 (가장 가까운 정수배).
        let frame = makeImage(w: 12, h: 12) { px in
            self.fillRect(&px, 12, x: 4...7, y: 2...9, 255, 255, 255)
        }
        let opts = FrameNormalizer.Options(cellW: 32, cellH: 40, targetCharHeight: 15,
                                           baselineFromBottom: 2)
        guard let out = FrameNormalizer.normalize(frames: [frame], options: opts) else {
            return XCTFail("normalize failed")
        }
        let buf = readPx(out)
        let box = regionBox(buf, xRange: 0..<32)
        XCTAssertNotNil(box)
        XCTAssertEqual(box!.maxY - box!.minY + 1, 16, "정수배 NEAREST 업스케일이 아님")
        XCTAssertEqual(box!.maxX - box!.minX + 1, 8)
        // NEAREST: 업스케일 후에도 완전 불투명(보간 얼룩 없음).
        let midA = alpha(buf, box!.minX + 4, box!.minY + 8)
        XCTAssertEqual(midA, 255)
    }

    func testNormalizerLegacySheetOverloadStillWorks() {
        // 기존 API(균등 slice 경로) 호환: 시트 → 동일 옵션 결과 유지.
        let sheet = makeImage(w: 40, h: 20) { px in
            self.fillRect(&px, 40, x: 6...11, y: 4...17, 255, 255, 255)   // frame 0
            self.fillRect(&px, 40, x: 26...31, y: 4...17, 255, 255, 255)  // frame 1
        }
        let opts = FrameNormalizer.Options(cellW: 32, cellH: 40, targetCharHeight: 28,
                                           baselineFromBottom: 2)
        guard let out = FrameNormalizer.normalize(sheet, frames: 2, options: opts) else {
            return XCTFail("legacy normalize failed")
        }
        XCTAssertEqual(out.width, 64)
        XCTAssertEqual(out.height, 40)
        let buf = readPx(out)
        XCTAssertNotNil(regionBox(buf, xRange: 0..<32))
        XCTAssertNotNil(regionBox(buf, xRange: 32..<64))
    }

    // MARK: - 파이프라인 통합 (ChromaKeyer → FrameExtractor → FrameNormalizer)

    func testFullExtractPipeline() throws {
        // 마젠타 배경 시트에 크기 다른 캐릭터 2개(불균등 배치) → 키잉 → 추출 → 정규화.
        let sheet = makeImage(w: 80, h: 30) { px in
            self.fillRect(&px, 80, x: 0...79, y: 0...29, 255, 0, 255)
            self.fillRect(&px, 80, x: 8...15, y: 6...25, 220, 40, 40)    // 8x20
            self.fillRect(&px, 80, x: 47...52, y: 12...25, 40, 60, 220)  // 6x14 (불균등 위치)
        }
        guard let keyed = ChromaKeyer.removeBackground(sheet) else { return XCTFail("keying failed") }
        let frames = try FrameExtractor.extractFrames(keyed, frameCount: 2)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0].width, 8)
        XCTAssertEqual(frames[1].width, 6)
        let opts = FrameNormalizer.Options(cellW: 32, cellH: 40, targetCharHeight: 20,
                                           baselineFromBottom: 2)
        guard let out = FrameNormalizer.normalize(frames: frames, options: opts) else {
            return XCTFail("normalize failed")
        }
        XCTAssertEqual(out.width, 64)
        let buf = readPx(out)
        let b0 = regionBox(buf, xRange: 0..<32)
        XCTAssertNotNil(b0)
        XCTAssertEqual(b0!.maxY - b0!.minY + 1, 20, "대표 신장이 목표 높이로 정규화돼야 함")
    }
}
