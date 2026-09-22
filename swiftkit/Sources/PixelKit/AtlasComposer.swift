import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// 05 Atlas Composer 엔진 — 승인된 모션 프레임을 고정 셀 그리드 아틀라스 + manifest.json 으로 굽는다.
// 정본 계약: docs/2d-game-assets-create/05-atlas-composer.md.
//
// 균등분할(1/frames) 가정을 근본 제거한다 — 런타임이 manifest 의 프레임 사각형을 직접 샘플한다.
// 시트 = maxFrames*cellWidth × numRows*cellHeight, 행=모션(state), 열=frame 고정 셀.

// MARK: - manifest.json 스키마 (sprite-gen + free-tex-packer 절충)

/// 아틀라스 산출 매니페스트 — sprite-sheet-alpha.png 와 짝을 이루는 게임 입력 계약.
public struct AtlasManifest: Codable, Sendable, Equatable {
    public var game_input: String
    public var frame_layout: FrameLayout
    public var animation: Animation
    public var curation_applied: Bool
    public var frame_variant: String

    /// 프레임 1칸. 좌표계 = 픽셀·top-left(원점 좌상단). 게임 로더가 y 반전으로 소비한다.
    public struct Frame: Codable, Sendable, Equatable {
        public var x: Int
        public var y: Int
        public var w: Int
        public var h: Int
        /// 트림 박스(원본 대비 잘린 실제 그림 영역). r1 정규화 프레임은 셀 전체.
        public var trim: Box?
        /// 트림 전 원본 프레임 크기(발 앵커·복원용).
        public var sourceSize: WH?
        /// pivot(정규화 0~1, top-left 기준). 발 앵커 = (0.5, 1.0).
        public var anchor: XY?

        public init(x: Int, y: Int, w: Int, h: Int, trim: Box? = nil,
                    sourceSize: WH? = nil, anchor: XY? = nil) {
            self.x = x; self.y = y; self.w = w; self.h = h
            self.trim = trim; self.sourceSize = sourceSize; self.anchor = anchor
        }
    }
    public struct Box: Codable, Sendable, Equatable {
        public var x: Int; public var y: Int; public var w: Int; public var h: Int
        public init(x: Int, y: Int, w: Int, h: Int) { self.x = x; self.y = y; self.w = w; self.h = h }
    }
    public struct WH: Codable, Sendable, Equatable {
        public var w: Int; public var h: Int
        public init(w: Int, h: Int) { self.w = w; self.h = h }
    }
    public struct XY: Codable, Sendable, Equatable {
        public var x: Double; public var y: Double
        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public struct FrameLayout: Codable, Sendable, Equatable {
        public var sheetWidth: Int
        public var sheetHeight: Int
        public var cellWidth: Int
        public var cellHeight: Int
        /// 모션명 → 프레임 사각형 배열(왼→오).
        public var rows: [String: [Frame]]
        public init(sheetWidth: Int, sheetHeight: Int, cellWidth: Int, cellHeight: Int, rows: [String: [Frame]]) {
            self.sheetWidth = sheetWidth; self.sheetHeight = sheetHeight
            self.cellWidth = cellWidth; self.cellHeight = cellHeight; self.rows = rows
        }
    }

    /// 모션별 애니메이션 provenance(entity spec 에서 파생 — 하드코딩 금지 계약).
    public struct Row: Codable, Sendable, Equatable {
        public var row: Int
        public var frames: Int
        public var fps: Int
        public var loop: Bool
        /// 비캐릭터 시트 구분(effect|icon). 캐릭터 모션은 nil.
        public var kind: String?
        public init(row: Int, frames: Int, fps: Int, loop: Bool, kind: String? = nil) {
            self.row = row; self.frames = frames; self.fps = fps; self.loop = loop; self.kind = kind
        }
    }
    public struct Animation: Codable, Sendable, Equatable {
        public var rows: [String: Row]
        public init(rows: [String: Row]) { self.rows = rows }
    }

    public init(game_input: String, frame_layout: FrameLayout, animation: Animation,
                curation_applied: Bool, frame_variant: String) {
        self.game_input = game_input
        self.frame_layout = frame_layout
        self.animation = animation
        self.curation_applied = curation_applied
        self.frame_variant = frame_variant
    }

    public static func load(_ path: String) throws -> AtlasManifest {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(AtlasManifest.self, from: data)
    }

    public func save(_ path: String) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

// MARK: - Composer 엔진

public enum AtlasComposer {

    /// 굽기 대상 모션 1건 — 소스 가로 시트 + provenance(entity spec 파생).
    public struct MotionInput: Sendable {
        public var name: String
        /// 소스 가로 스프라이트 시트(norm 산출). frames 등분해 셀로 재배치한다.
        public var sheet: CGImage
        public var frames: Int
        public var fps: Int
        public var loop: Bool
        public var kind: String?

        public init(name: String, sheet: CGImage, frames: Int, fps: Int, loop: Bool, kind: String? = nil) {
            self.name = name; self.sheet = sheet; self.frames = frames
            self.fps = fps; self.loop = loop; self.kind = kind
        }
    }

    public struct Result: Sendable {
        public var image: CGImage
        public var manifest: AtlasManifest
    }

    /// 승인 모션들을 고정 셀 그리드 아틀라스 + manifest 로 굽는다.
    /// - 시트 = maxFrames*cellWidth × count*cellHeight, 행=모션, 열=frame.
    /// - 각 소스 시트를 frames 등분 → 셀에 리샘플 배치(정규화 셀 크기로 통일).
    public static func compose(motions: [MotionInput],
                               cellWidth: Int,
                               cellHeight: Int,
                               gameInput: String = "sprite-sheet-alpha.png",
                               frameVariant: String = "canonical",
                               curationApplied: Bool = true,
                               anchor: (x: Double, y: Double) = (0.5, 1.0)) -> Result? {
        let motions = motions.filter { $0.frames > 0 }
        guard !motions.isEmpty, cellWidth > 0, cellHeight > 0 else { return nil }

        let maxFrames = motions.map(\.frames).max() ?? 1
        let sheetW = maxFrames * cellWidth
        let sheetH = motions.count * cellHeight

        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.clear(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

        var layoutRows: [String: [AtlasManifest.Frame]] = [:]
        var animRows: [String: AtlasManifest.Row] = [:]

        for (rowIndex, m) in motions.enumerated() {
            let srcCellW = m.sheet.width / m.frames
            let srcH = m.sheet.height
            var frames: [AtlasManifest.Frame] = []
            for col in 0..<m.frames {
                // manifest 좌표: 픽셀·top-left(원점 좌상단).
                let px = col * cellWidth
                let py = rowIndex * cellHeight
                frames.append(.init(
                    x: px, y: py, w: cellWidth, h: cellHeight,
                    trim: .init(x: 0, y: 0, w: cellWidth, h: cellHeight),
                    sourceSize: .init(w: cellWidth, h: cellHeight),
                    anchor: .init(x: anchor.x, y: anchor.y)))

                // CGContext 는 bottom-left 원점 — top-left row 를 뒤집어 그린다.
                let dstX = CGFloat(px)
                let dstY = CGFloat(sheetH - py - cellHeight)
                let dstRect = CGRect(x: dstX, y: dstY, width: CGFloat(cellWidth), height: CGFloat(cellHeight))
                if srcCellW > 0,
                   let cell = m.sheet.cropping(to: CGRect(x: col * srcCellW, y: 0, width: srcCellW, height: srcH)) {
                    ctx.draw(cell, in: dstRect)
                }
            }
            layoutRows[m.name] = frames
            animRows[m.name] = .init(row: rowIndex, frames: m.frames, fps: m.fps, loop: m.loop, kind: m.kind)
        }

        guard let image = ctx.makeImage() else { return nil }
        let manifest = AtlasManifest(
            game_input: gameInput,
            frame_layout: .init(sheetWidth: sheetW, sheetHeight: sheetH,
                                cellWidth: cellWidth, cellHeight: cellHeight, rows: layoutRows),
            animation: .init(rows: animRows),
            curation_applied: curationApplied,
            frame_variant: frameVariant)
        return Result(image: image, manifest: manifest)
    }

    /// 아틀라스 PNG 저장.
    @discardableResult
    public static func writePNG(_ image: CGImage, to path: String) -> Bool {
        guard let dest = CGImageDestinationCreateWithURL(
            URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    /// 시트 로드(경로 → CGImage).
    public static func load(_ path: String) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
}
