import Foundation

// MARK: - 수락 키 가상 키코드 (US/ANSI 배열 기준)

/// KeyEventTap 이 참조하는 가상 키코드.
/// grave/tab 은 KeyBindingStore 기본 바인딩 값(사용자 변경 가능)이고, escape 만 고정 키다.
public enum AcceptKeyCode: Int64, Sendable {
    /// ` (grave/backquote) — 전체 수락 기본 키. ⌃` 강제 발동, ⌃⌥⌘` 전역 토글 기본값.
    case grave = 50
    /// Tab — 줄 수락 기본 키.
    case tab = 48
    /// Esc — 제안 닫기 (고정 — 바인딩 대상 아님).
    case escape = 53
    /// → (오른쪽 화살표) — 단어 수락 기본 키(⌘→).
    case rightArrow = 124
    /// K — 수정 모드 발동 기본 키(⌥⌘K).
    case k = 40
}
