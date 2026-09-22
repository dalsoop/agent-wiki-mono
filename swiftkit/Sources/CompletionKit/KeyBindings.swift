import Foundation
import CoreGraphics

// MARK: - 사용자 정의 단축키 바인딩

/// 단축키 하나 — 가상 키코드 + 정규화된 modifier 비트.
public struct KeyBinding: Codable, Sendable, Equatable {
    /// 가상 키코드 (예: grave 50, tab 48)
    public var keyCode: Int64
    /// ModifierMatcher.normalized 된 CGEventFlags.rawValue (⌘⌃⌥⇧ 비트만)
    public var modifiers: UInt64

    public init(keyCode: Int64, modifiers: UInt64) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// 실제 이벤트가 이 바인딩과 일치하는가 (caps/fn/패드 플래그는 무시).
    /// 저장값이 정규화 안 된 경우도 비교 시 양쪽 정규화로 흡수한다.
    public func matches(keyCode: Int64, flags: CGEventFlags) -> Bool {
        self.keyCode == keyCode
            && ModifierMatcher.matches(flags, exactly: CGEventFlags(rawValue: modifiers))
    }
}

/// 바인딩 가능한 액션. Esc(제안 닫기)는 고정 키라 여기 없다.
public enum BindableAction: String, Codable, CaseIterable, Sendable {
    /// 완성 전체 수락 (기본 `)
    case acceptFull
    /// 다음 단어만 수락 (기본 ⌘→)
    case acceptWord
    /// 첫 줄만 수락 (기본 Tab)
    case acceptLine
    /// 완성 강제 발동 (기본 ⌃`)
    case forceActivate
    /// 전역 on/off 토글 (기본 ⌃⌥⌘`)
    case globalToggle
    /// 수정 모드 발동 (기본 ⌥⌘K) — 선택 코드를 지시대로 재작성.
    case editActivate
}

/// 액션별 바인딩 저장소.
/// UserDefaults[Self.defaultsKey] 에 [action rawValue: KeyBinding] JSON(Data)으로
/// 보존한다. 값이 없거나 깨져 있으면 기본값(Cotypist 동일)으로 동작한다.
@MainActor
public final class KeyBindingStore {
    public static let shared = KeyBindingStore()

    /// 사용자 오버라이드 바인딩을 담는 UserDefaults 키(CompletionKit 자체 네임스페이스).
    public nonisolated static let defaultsKey = "completionkit.keyBindings"

    /// 단축키 레코딩 중 tap 정지 플래그 — true 면 KeyEventTap 이 어떤 키도 소비하지 않고
    /// 전부 통과시킨다 (레코더 UI 가 keyDown 을 직접 받아야 함). 설정은 ShortcutsSection 담당.
    /// 영속화하지 않는다 (세션 상태).
    public var suspendedForRecording = false

    private let defaults: UserDefaults
    /// 사용자 오버라이드만 담는다 (키 없음 = 기본값 사용).
    private var overrides: [BindableAction: KeyBinding]

    /// 테스트용으로 전용 UserDefaults 를 주입할 수 있다.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.overrides = Self.load(from: defaults)
    }

    /// Cotypist 와 동일한 기본 바인딩.
    nonisolated public static func defaultBinding(for action: BindableAction) -> KeyBinding {
        switch action {
        case .acceptFull:
            KeyBinding(keyCode: AcceptKeyCode.grave.rawValue, modifiers: 0)
        case .acceptWord:
            KeyBinding(keyCode: AcceptKeyCode.rightArrow.rawValue,
                       modifiers: CGEventFlags.maskCommand.rawValue)
        case .acceptLine:
            KeyBinding(keyCode: AcceptKeyCode.tab.rawValue, modifiers: 0)
        case .forceActivate:
            KeyBinding(
                keyCode: AcceptKeyCode.grave.rawValue,
                modifiers: CGEventFlags.maskControl.rawValue
            )
        case .globalToggle:
            KeyBinding(
                keyCode: AcceptKeyCode.grave.rawValue,
                modifiers: CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
            )
        case .editActivate:
            KeyBinding(
                keyCode: AcceptKeyCode.k.rawValue,
                modifiers: CGEventFlags([.maskAlternate, .maskCommand]).rawValue
            )
        }
    }

    /// 현재 유효한 바인딩 (오버라이드 없으면 기본값).
    public func binding(for action: BindableAction) -> KeyBinding {
        overrides[action] ?? Self.defaultBinding(for: action)
    }

    /// 바인딩 저장. modifiers 는 저장 전에 정규화한다 (caps/fn/패드 비트 제거).
    public func setBinding(_ b: KeyBinding, for action: BindableAction) {
        var normalized = b
        normalized.modifiers = ModifierMatcher.normalized(CGEventFlags(rawValue: b.modifiers)).rawValue
        overrides[action] = normalized
        persist()
    }

    /// 기본값으로 되돌린다.
    public func reset(_ action: BindableAction) {
        overrides.removeValue(forKey: action)
        persist()
    }

    /// 기본값과 다른 사용자 오버라이드가 저장돼 있는가 (UI 의 "기본값" 버튼 활성 판단용).
    public func isCustomized(_ action: BindableAction) -> Bool {
        overrides[action] != nil
    }

    /// 이벤트(keyCode/flags)가 action 의 현재 바인딩과 일치하는가.
    public func matches(_ action: BindableAction, keyCode: Int64, flags: CGEventFlags) -> Bool {
        binding(for: action).matches(keyCode: keyCode, flags: flags)
    }

    // MARK: - 영속화

    /// 저장값 로드. 알 수 없는 액션 키는 무시, JSON 전체가 깨지면 빈 오버라이드(=기본값).
    nonisolated private static func load(from defaults: UserDefaults) -> [BindableAction: KeyBinding] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let raw = try? JSONDecoder().decode([String: KeyBinding].self, from: data)
        else { return [:] }
        var out: [BindableAction: KeyBinding] = [:]
        for (key, value) in raw {
            guard let action = BindableAction(rawValue: key) else { continue }
            out[action] = value
        }
        return out
    }

    private func persist() {
        var raw: [String: KeyBinding] = [:]
        for (action, binding) in overrides {
            raw[action.rawValue] = binding
        }
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}
