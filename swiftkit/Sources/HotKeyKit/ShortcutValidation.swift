#if os(macOS)
@preconcurrency import AppKit
import Carbon.HIToolbox

extension NSEvent.SpecialKey {
	/// function key(F1~F35) 집합.
	// nonisolated(unsafe): NSEvent.SpecialKey 은 Sendable 이 아니지만 불변 값 집합.
	nonisolated(unsafe) static let functionKeys: Set<Self> = Set(
		[.f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
		 .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20,
		 .f21, .f22, .f23, .f24, .f25, .f26, .f27, .f28, .f29, .f30,
		 .f31, .f32, .f33, .f34, .f35]
	)

	/// function key 여부.
	var isFunctionKey: Bool { Self.functionKeys.contains(self) }
}

extension HotKeyKit.Shortcut {
	/// 샌드박스+macOS15 에서 Option 단독 계열은 금지다.
	var isDisallowed: Bool {
		guard
			#available(macOS 15, *),
			Constants.isSandboxed
		else { return false }

		guard modifiers.contains(.option) else { return false }
		// Option 이 있으면 Command/Control/function/capsLock 중 하나라도 함께 있어야 한다.
		let otherModifiers: NSEvent.ModifierFlags = [.command, .control, .function, .capsLock]
		return modifiers.isDisjoint(with: otherModifiers)
	}

	/// 시스템이 이미 점유한 단축키인지.
	var isTakenBySystem: Bool {
		// F12 단독은 시스템 항목이지만 예외로 둔다(KeyboardShortcuts 호환).
		guard self != Self(.f12, modifiers: []) else { return false }
		return Self.system.contains(self)
	}

	/// 시스템 정의 단축키 목록(CopySymbolicHotKeys).
	static var system: [Self] {
		var shortcutsUnmanaged: Unmanaged<CFArray>?
		guard
			CopySymbolicHotKeys(&shortcutsUnmanaged) == noErr,
			let shortcuts = shortcutsUnmanaged?.takeRetainedValue() as? [[String: Any]]
		else {
			return []
		}

		return shortcuts.compactMap {
			guard
				($0[kHISymbolicHotKeyEnabled] as? Bool) == true,
				let carbonKeyCode = $0[kHISymbolicHotKeyCode] as? Int,
				let carbonModifiers = $0[kHISymbolicHotKeyModifiers] as? Int
			else {
				return nil
			}
			return HotKeyKit.Shortcut(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers)
		}
	}
}

enum Constants {
	/// 샌드박스 여부(APP_SANDBOX_CONTAINER_ID 환경변수 유무).
	static let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
}

extension HotKeyKit.Shortcut {
	/// 메인 메뉴에서 같은 key equivalent + modifier 를 가진 항목을 찾는다.
	func menuItemWithMatchingShortcut(in menu: NSMenu) -> NSMenuItem? {
		for item in menu.items {
			var keyEquivalent = item.keyEquivalent
			var keyEquivalentModifierMask = item.keyEquivalentModifierMask

			// Shift 조합인 경우 소문자로 정규화.
			if modifiers.contains(.shift), keyEquivalent.lowercased() != keyEquivalent {
				keyEquivalent = keyEquivalent.lowercased()
				keyEquivalentModifierMask.insert(.shift)
			}

			if keyToCharacter() == keyEquivalent, modifiers == keyEquivalentModifierMask {
				return item
			}

			if let submenu = item.submenu, let menuItem = menuItemWithMatchingShortcut(in: submenu) {
				return menuItem
			}
		}
		return nil
	}

	/// 앱 메인 메뉴에서 매칭 항목.
	/// Recorder(메인 스레드)에서만 호출된다.
	var takenByMainMenu: NSMenuItem? {
		guard let mainMenu = NSApp.mainMenu else { return nil }
		return menuItemWithMatchingShortcut(in: mainMenu)
	}
}
#endif
