import Foundation

/// `{{var}}` 치환 기반의 얇은 프롬프트 템플릿.
///
/// 셸 히스토리에 흩어지던 프롬프트를 코드/매니페스트로 끌어올려 **재현·버전관리** 가능하게 한다.
public struct PromptTemplate: Sendable, Equatable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }

    /// `{{key}}` 를 values 로 치환. 미치환 토큰은 그대로 남긴다(누락 감지용).
    public func render(_ values: [String: String]) -> String {
        var out = raw
        for (k, v) in values {
            out = out.replacingOccurrences(of: "{{\(k)}}", with: v)
        }
        return out
    }

    /// 아직 치환되지 않은 `{{...}}` 토큰 목록(검증용).
    public var unresolvedTokens: [String] {
        var tokens: [String] = []
        var rest = Substring(raw)
        while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
            tokens.append(String(rest[open.upperBound..<close.lowerBound]))
            rest = rest[close.upperBound...]
        }
        return tokens
    }
}

/// 스프라이트 시트 생성의 공통 규칙 프롬프트.
///
/// 캐릭터 일관성(순수 2D codex 개선 파이프라인)의 핵심 문구를 상수로 고정한다.
/// 정본 근거: docs/23-character-base-pipeline.md.
public enum SpritePromptRules {
    /// 캐논 강참조·미러 금지·프레임 동일성 등 일관성 규칙.
    public static let consistency = """
    STRICT RULES:
    - Use the attached reference image as the EXACT SAME character in every frame. Same outfit, proportions, palette, hair, and details.
    - Do NOT mirror or swap left/right limbs between frames. Keep facing direction consistent.
    - Pixel-art sprite sheet on a SOLID PURE MAGENTA (#FF00FF) chroma-key background for clean background removal.
      Single centered character, full body visible, NO environment, NO ground shadow.
    - Do NOT use magenta or hot pink (#FF00FF) ANYWHERE on the character — reserve that color for the background only, so keying is perfectly clean. Black outfits, black hair and black outlines ARE allowed (the background is magenta, not black).
    - Clean selective outline, 15-16 color palette, 2-3 tone shading.
    - Even horizontal spacing, all frames the same canvas size, character vertically centered on a shared baseline.
    - MOTION CONTINUITY: the frames form ONE continuous motion — each frame follows naturally from the
      previous pose (small pose deltas, no teleporting limbs). For looping motions the LAST frame must
      flow back into the FIRST frame (seamless loop). Effects/arcs must build up and dissipate across
      consecutive frames, never appear fully-formed in a single frame and vanish in the next.
    - Keep the weapon/props attached to the character in every frame (no detached floating pieces).
    - No text, no watermark, no grid lines.
    """

    /// 모션 시트 표준 템플릿. 변수: character, motion, frames, extra, palette.
    public static let sheetTemplate = PromptTemplate("""
    A single horizontal pixel-art sprite sheet of {{character}}.
    Motion: {{motion}}. Exactly {{frames}} frames in one row, left to right, in animation order.
    {{extra}}
    Palette hint: {{palette}}.

    \(consistency)
    """)
}
