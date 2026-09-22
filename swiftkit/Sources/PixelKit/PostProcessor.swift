import Foundation
import CommandKit

/// 원본 png → 인게임 도트 에셋 후처리 파이프라인.
///
/// 정본 스크립트(game-agent-of-gaya/scripts/process_sprite.sh)를 앱/CLI 재사용 가능한 형태로 흡수:
/// rembg(배경분리) → ImageMagick point 다운샘플 + 팔레트 remap → pngquant 최적화.
/// dotify-lab-swift 의 코어가 된다.
public struct PostProcessor: Sendable {
    public struct Tools: Sendable {
        public var rembg: String
        public var magick: String
        public var pngquant: String
        public init(rembg: String = "rembg", magick: String = "magick", pngquant: String = "pngquant") {
            self.rembg = rembg
            self.magick = magick
            self.pngquant = pngquant
        }
    }

    public struct Options: Sendable {
        /// 다운샘플 목표 세로 픽셀(예: 캐릭터 128, 잡몹 64). 가로는 비율 유지.
        public var gridHeight: Int
        /// 고정 팔레트 png 경로(remap). nil 이면 팔레트 고정 생략.
        public var palette: String?
        /// 배경분리 수행 여부.
        public var removeBackground: Bool
        /// 가로 프레임 수(>0이면 최종 폭을 이 배수로 crop 정규화 → 균등 슬라이스 밀림 방지).
        public var frames: Int
        /// 지정 시 배경제거 후 **캐릭터 크기·발 앵커 정규화**(FrameNormalizer)로 최종 시트를 만든다.
        /// 액션(시트)마다 캐릭터 크기가 달라지는 문제를 표준화한다. nil 이면 기존 magick 다운샘플.
        public var normalize: FrameNormalizer.Options?
        /// rembg 모델 id. nil = rembg 기본(u2net). gpt-image/god-tibo 산출물의 머리카락·아웃라인
        /// 경계를 살리려면 `birefnet-general`(MIT) 또는 `birefnet-portrait`/`ben2` 권장.
        /// ⚠️ `bria-rmbg` 계열은 비상업 라이선스 — 상업 용도면 birefnet/u2net 계열을 쓴다.
        public var rembgModel: String?
        /// 시트 전체를 N색 **공유 팔레트**로 양자화 → 프레임 간 색 깜빡임(palette flicker) 제거.
        /// 도트 애니 퀄리티의 핵심(프레임마다 미세하게 다른 셰이드로 재생 시 아른거림 방지).
        /// nil = 생략. 픽셀아트는 16~32 권장. `palette`(고정 팔레트 png) 지정 시엔 그쪽이 우선.
        public var paletteColors: Int?
        public init(gridHeight: Int = 128, palette: String? = nil, removeBackground: Bool = true,
                    frames: Int = 0, normalize: FrameNormalizer.Options? = nil, rembgModel: String? = nil,
                    paletteColors: Int? = nil) {
            self.gridHeight = gridHeight
            self.palette = palette
            self.removeBackground = removeBackground
            self.frames = frames
            self.normalize = normalize
            self.rembgModel = rembgModel
            self.paletteColors = paletteColors
        }
    }

    public struct Outcome: Sendable {
        public let outputPath: String
        public let ok: Bool
        public let log: String
    }

    let runner: CommandRunning
    let tools: Tools

    public init(runner: CommandRunning = ProcessCommandRunner(), tools: Tools = .init()) {
        self.runner = runner
        self.tools = tools
    }

    /// raw png 을 후처리해 outDir/<name>.png 로 저장. PATH 에 도구(.venv 등)가 있어야 한다.
    public func process(raw: String, outDir: String, options: Options) async -> Outcome {
        let fm = FileManager.default
        do { try fm.createDirectory(atPath: outDir, withIntermediateDirectories: true) } catch { _ = error }
        let name = ((raw as NSString).lastPathComponent as NSString).deletingPathExtension
        let nobg = (outDir as NSString).appendingPathComponent("\(name)_nobg.png")
        let final = (outDir as NSString).appendingPathComponent("\(name).png")
        var log = ""

        // 1) rembg
        let src: String
        if options.removeBackground {
            // rembg i [-m <model>] <in> <out> — 모델 지정 시 BiRefNet 등 고품질 매팅.
            let modelArgs = options.rembgModel.map { ["-m", $0] } ?? []
            let r = await exec(tools.rembg, ["i"] + modelArgs + [raw, nobg])
            log += "[rembg\(options.rembgModel.map { " \($0)" } ?? "")] exit \(r.exitCode)\n\(r.stderr)\n"
            src = fm.fileExists(atPath: nobg) ? nobg : raw
        } else {
            src = raw
        }

        // 2a) 정규화 경로: 배경제거본 → FrameNormalizer(캐릭터 크기·발 앵커 표준화) → 최종.
        if let normOpts = options.normalize, options.frames > 0 {
            if let img = SpriteSlicer.load(src),
               let out = FrameNormalizer.normalize(img, frames: options.frames, options: normOpts),
               SpriteSlicer.writePNG(out, to: final) {
                log += "[normalize] char \(normOpts.targetCharHeight)px, cell \(normOpts.cellW)x\(normOpts.cellH), \(options.frames)f\n"
                if fm.fileExists(atPath: final) {
                    log += await lockPalette(final, options: options)
                    _ = await exec(tools.pngquant, ["--force", "--quality", "60-95", final, "-o", final])
                }
                return Outcome(outputPath: final, ok: fm.fileExists(atPath: final), log: log)
            } else {
                log += "[normalize] 실패 → magick 다운샘플로 폴백\n"
            }
        }

        // 2b) magick: point 다운샘플 (+ 팔레트 remap)
        var magickArgs = [src, "-filter", "point", "-resize", "x\(options.gridHeight)"]
        if let pal = options.palette, fm.fileExists(atPath: pal) {
            magickArgs += ["-dither", "None", "-remap", pal]
        }
        magickArgs.append(final)
        let m = await exec(tools.magick, magickArgs)
        log += "[magick] exit \(m.exitCode)\n\(m.stderr)\n"

        // 프레임수 배수로 폭 정규화(오른쪽 잉여 픽셀 crop) → 균등 슬라이스가 정확히 맞음.
        if options.frames > 0, fm.fileExists(atPath: final) {
            let dim = await exec(tools.magick, ["identify", "-format", "%w %h", final])
            let parts = dim.trimmedStdout.split(separator: " ").compactMap { Int($0) }
            if parts.count == 2 {
                let w = parts[0], h = parts[1]
                let normW = (w / options.frames) * options.frames
                if normW > 0 && normW != w {
                    let c = await exec(tools.magick, [final, "-crop", "\(normW)x\(h)+0+0", "+repage", final])
                    log += "[normalize] \(w)→\(normW) (÷\(options.frames)) exit \(c.exitCode)\n"
                }
            }
        }

        // 2c) 공유 팔레트 락 (프레임 간 색 깜빡임 제거)
        if fm.fileExists(atPath: final) {
            log += await lockPalette(final, options: options)
        }

        // 3) pngquant (실패해도 무시)
        if fm.fileExists(atPath: final) {
            let p = await exec(tools.pngquant, ["--force", "--quality", "60-95", final, "-o", final])
            log += "[pngquant] exit \(p.exitCode)\n"
        }

        // 정수배 미리보기
        let preview = (final as NSString).deletingPathExtension + "_preview.png"
        _ = await exec(tools.magick, [final, "-filter", "point", "-resize", "400%", preview])

        return Outcome(outputPath: final, ok: fm.fileExists(atPath: final), log: log)
    }

    /// 시트 전체를 N색 공유 팔레트로 양자화(프레임 간 색 깜빡임 제거). 고정 팔레트 png 를 쓰는
    /// 경우(options.palette)엔 이미 공유 remap 이라 생략. dither 없이 하드 매핑 → 도트 보존.
    func lockPalette(_ path: String, options: Options) async -> String {
        guard let n = options.paletteColors, n > 1, options.palette == nil else { return "" }
        let r = await exec(tools.magick, [path, "-colors", "\(n)", "-dither", "None", path])
        return "[palette-lock] \(n)색 공유 · exit \(r.exitCode)\n"
    }

    /// 절대경로면 직접, 아니면 /usr/bin/env 로 PATH 검색 실행.
    func exec(_ tool: String, _ args: [String]) async -> CommandResult {
        if tool.hasPrefix("/") {
            return await runner.run(tool, args)
        }
        return await runner.run("/usr/bin/env", [tool] + args)
    }
}
