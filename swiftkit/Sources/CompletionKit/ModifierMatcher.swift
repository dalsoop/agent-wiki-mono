import CoreGraphics

// MARK: - Modifier 정규화·정확 일치 비교 (순수 함수 — 테스트 대상)

/// 수락 키 판정용 modifier 비교기.
/// caps lock(alphaShift)·fn(secondaryFn)·numeric pad·nonCoalesced 등
/// 판정과 무관한 플래그는 무시하고, ⌘⌃⌥⇧ 4개만 본다.
public enum ModifierMatcher {
    /// 비교 대상 4개 modifier.
    public static let relevant: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift,
    ]

    /// 판정과 관계있는 플래그만 남긴 정규화 값.
    public static func normalized(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(relevant)
    }

    /// 정규화 후 required 와 정확히 일치하는가 (부분집합/초과집합은 불일치).
    public static func matches(_ flags: CGEventFlags, exactly required: CGEventFlags) -> Bool {
        normalized(flags) == normalized(required)
    }

    /// ⌘⌃⌥⇧ 가 하나도 눌리지 않았는가 (caps/fn/패드만 켜져 있으면 무수정 취급).
    public static func isUnmodified(_ flags: CGEventFlags) -> Bool {
        normalized(flags).isEmpty
    }
}
