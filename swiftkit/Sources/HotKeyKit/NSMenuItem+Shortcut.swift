#if os(macOS)
@preconcurrency import AppKit

extension HotKeyKit.Shortcut {
	/// `NSMenuItem.keyEquivalent` 에 넣을 단일 문자. 표시용 키보드 레이아웃 문자를 그대로 쓴다.
	var keyEquivalent: String { keyToCharacter() ?? "" }
}

extension NSMenuItem {
	/// 메뉴 항목의 keyEquivalent / modifierMask 를 이름에 할당된 단축키로 맞춘다.
	/// (전역 핫키 자체는 `HotKeyKit.onKeyDown` 으로 동작한다 — 이것은 메뉴 표시용.)
	public func setShortcut(for name: HotKeyKit.Name, withClearedAction: Bool = false) {
		setShortcut(HotKeyKit.Shortcut(name: name), withClearedAction: withClearedAction)
	}

	/// 메뉴 항목의 keyEquivalent / modifierMask 를 직접 지정한다.
	public func setShortcut(_ shortcut: HotKeyKit.Shortcut?, withClearedAction: Bool = false) {
		if withClearedAction {
			action = nil
		}
		keyEquivalent = shortcut?.keyEquivalent ?? ""
		keyEquivalentModifierMask = shortcut?.modifiers ?? []
	}
}
#endif
