import CoreGraphics

/// 스프라이트 시트의 프레임 경계를 **알파/밝기 열별 투영 프로파일**로 자동 검출한다.
///
/// 참고: mirsella/spritesheet_detector (알파 투영 + 주기 검출). 균등분할(`frameCount` 고정)이
/// 깨지는 codex 불균등 시트 대책 — extract **전** 프레임 수 검증 게이트로 쓴다.
/// - 여백형 불균등 시트: 실제 경계 검출 → 재배치로 살림.
/// - 붙은 시트(경계 없음): "N프레임 미검출" 조기 판정 → 헛된 재생성 방지.
/// SSOT 프로토타입: scripts/sprite-autogrid.py (코퍼스 검증 완료).
public enum FrameGridDetector {
    public struct Detection: Sendable, Equatable {
        public let frames: Int
        public let blocks: [(start: Int, end: Int)]
        public let widths: [Int]
        public static func == (l: Detection, r: Detection) -> Bool {
            l.frames == r.frames && l.widths == r.widths && l.blocks.map(\.start) == r.blocks.map(\.start)
        }
    }

    /// 열별 콘텐츠 투영으로 프레임 블록을 검출. raw(검정 배경)·norm(알파) 양쪽 지원.
    /// - Parameters:
    ///   - gapRatio: 빈 골 판정 임계(peak 대비 비율).
    ///   - minRun: 프레임 내부 얇은 틈 허용 폭(px). 0이면 폭/40 자동.
    public static func detect(_ image: CGImage, gapRatio: Double = 0.04, minRun: Int = 0) -> Detection? {
        guard let raw = PixelOps.readRGBA(image) else { return nil }
        let buf = raw.px, w = raw.w, h = raw.h
        let run = minRun > 0 ? minRun : max(4, w / 40)

        // 콘텐츠 판정: 알파>24 이고 밝기(비검정)>28 — raw/norm 양쪽에서 프레임 사이 gap 검출.
        var col = [Int](repeating: 0, count: w)
        for x in 0..<w {
            var c = 0
            for y in 0..<h {
                let i = (y * w + x) * 4
                let r = buf[i], g = buf[i + 1], b = buf[i + 2], a = buf[i + 3]
                if a > 24 && max(r, max(g, b)) > 28 { c += 1 }
            }
            col[x] = c
        }
        let peak = col.max() ?? 0
        guard peak > 0 else { return nil }
        let thr = Double(peak) * gapRatio
        let filled = col.map { Double($0) > thr }

        func shortGap(_ j: Int) -> Bool {
            if filled[j] { return true }
            for k in j..<min(j + run, filled.count) where filled[k] { return true }
            return false
        }

        var blocks: [(start: Int, end: Int)] = []
        var i = 0
        while i < w {
            if filled[i] {
                var j = i
                while j < w && (filled[j] || shortGap(j)) { j += 1 }
                blocks.append((i, j))
                i = j
            } else { i += 1 }
        }
        return Detection(frames: blocks.count, blocks: blocks, widths: blocks.map { $0.end - $0.start })
    }

    /// extract 전 게이트: 검출 프레임 수가 기대치와 다르면 사유를 반환(nil=일치).
    public static func mismatchReason(_ image: CGImage, expected: Int) -> String? {
        guard let d = detect(image) else { return "픽셀 버퍼 읽기 실패" }
        if d.frames == expected { return nil }
        if d.frames == 1 { return "프레임 경계 없음(붙은 시트) — 기대 \(expected), 재생성 필요" }
        return "프레임 수 불일치: 검출 \(d.frames) ≠ 기대 \(expected) (불균등 배치)"
    }
}
