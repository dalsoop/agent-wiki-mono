#if os(macOS)
@preconcurrency import AppKit
import Carbon.HIToolbox
import CoreServices
import SwiftUI

extension HotKeyKit {
	/// 단축키 하나(키 + 수정자). Codable 이며, KeyboardShortcuts 2.x 의 저장 포맷과
	/// 동일하게 직렬화된다(`carbonKeyCode` / `carbonModifiers`).
	public struct Shortcut: Hashable, Codable, Sendable {
		/// Carbon 수정자 번호가 환경마다 달라 표준값으로 정규화한다.
		/// (예: 시스템 ⌃F2 = 135168 이지만 입력 시 4096)
		private static func normalizeModifiers(_ carbonModifiers: Int) -> Int {
			NSEvent.ModifierFlags(carbon: carbonModifiers).carbon
		}

		/// 단축키의 키.
		public var key: Key? { Key(rawValue: carbonKeyCode) }

		/// 단축키의 수정자.
		public var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(carbon: carbonModifiers) }

		/// 키의 저수준 표현. 보통 직접 쓸 일이 없다.
		public let carbonKeyCode: Int

		/// 수정자의 저수준 표현. 보통 직접 쓸 일이 없다.
		public let carbonModifiers: Int

		/// strongly-typed 키 + 수정자로 만든다.
		public init(_ key: Key, modifiers: NSEvent.ModifierFlags = []) {
			self.init(
				carbonKeyCode: key.rawValue,
				carbonModifiers: modifiers.carbon
			)
		}

		/// 키 이벤트로 만든다.
		public init?(event: NSEvent) {
			guard event.isKeyEvent else { return nil }
			self.init(
				carbonKeyCode: Int(event.keyCode),
				carbonModifiers: event.modifierFlags.carbon
			)
		}

		/// Recorder 가 저장한 단축키로 만든다.
		public init?(name: Name) {
			guard let shortcut = HotKeyKit.getShortcut(for: name) else { return nil }
			self = shortcut
		}

		/// key code 번호 + 수정자 번호로 만든다. 보통 직접 쓸 일이 없다.
		public init(carbonKeyCode: Int, carbonModifiers: Int = 0) {
			self.carbonKeyCode = carbonKeyCode
			self.carbonModifiers = Self.normalizeModifiers(carbonModifiers)
		}
	}
}

// MARK: - Storage helpers

extension Data {
	/// UTF-8 문자열로 변환.
	var asString: String? { String(data: self, encoding: .utf8) }
}

extension NSEvent {
	var isKeyEvent: Bool { type == .keyDown || type == .keyUp }

	/// 장치 독립적 수정자에서 capsLock/numericPad/function 을 제외한 "실제" 수정자.
	var realModifiers: ModifierFlags {
		modifierFlags
			.intersection(.deviceIndependentFlagsMask)
			.subtracting([.capsLock, .numericPad])
	}
}

extension NSEvent.ModifierFlags {
	/// NSEvent 수정자 → Carbon 수정자 비트.
	var carbon: Int {
		var flags = 0
		if contains(.control) { flags |= controlKey }
		if contains(.option) { flags |= optionKey }
		if contains(.shift) { flags |= shiftKey }
		if contains(.command) { flags |= cmdKey }
		return flags
	}

	/// Carbon 수정자 비트 → NSEvent 수정자.
	init(carbon: Int) {
		self.init()
		if carbon & controlKey == controlKey { insert(.control) }
		if carbon & optionKey == optionKey { insert(.option) }
		if carbon & shiftKey == shiftKey { insert(.shift) }
		if carbon & cmdKey == cmdKey { insert(.command) }
	}

	/// 수정자의 기호 표현(`[.command, .shift]` → `"⇧⌘"`).
	var presentableDescription: String {
		var description = ""
		if contains(.control) { description += "⌃" }
		if contains(.option) { description += "⌥" }
		if contains(.shift) { description += "⇧" }
		if contains(.command) { description += "⌘" }
		if contains(.function) { description += "🌐\u{FE0E}" }
		return description
	}
}

// MARK: - Key → character (description 표시용)

private let keyToCharacterMapping: [HotKeyKit.Key: String] = [
	.return: "↩",
	.delete: "⌫",
	.deleteForward: "⌦",
	.end: "↘",
	.escape: "⎋",
	.help: "?⃝",
	.home: "↖",
	.space: HotKeyL10n.spaceKey,
	.tab: "⇥",
	.pageUp: "⇞",
	.pageDown: "⇟",
	.upArrow: "↑",
	.rightArrow: "→",
	.downArrow: "↓",
	.leftArrow: "←",
	.f1: "F1", .f2: "F2", .f3: "F3", .f4: "F4", .f5: "F5", .f6: "F6",
	.f7: "F7", .f8: "F8", .f9: "F9", .f10: "F10", .f11: "F11", .f12: "F12",
	.f13: "F13", .f14: "F14", .f15: "F15", .f16: "F16", .f17: "F17", .f18: "F18", .f19: "F19", .f20: "F20",
]

extension HotKeyKit.Shortcut {
	/// key code 를 표시용 문자로 변환한다. 매핑이 없으면 현재 키보드 레이아웃에서
	/// UCKeyTranslate 로 글자를 얻는다.
	///
	/// - Note: TISGetInputSourceProperty 가 메인 스레드가 아니면 크래시한다. 실제 호출처는
	///   UI(Recorder·설정)에서만 발생하므로 동기식 non-isolated 로 둔다.
	func keyToCharacter() -> String? {
		if let key, let character = keyToCharacterMapping[key] {
			return character
		}

		guard
			let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
			let layoutDataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
		else {
			return nil
		}

		let layoutData = unsafeBitCast(layoutDataPointer, to: CFData.self)
		let keyLayout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)
		var deadKeyState: UInt32 = 0
		let maxLength = 4
		var length = 0
		var characters = [UniChar](repeating: 0, count: maxLength)

		let error = UCKeyTranslate(
			keyLayout,
			UInt16(carbonKeyCode),
			UInt16(kUCKeyActionDisplay),
			0,
			UInt32(LMGetKbdType()),
			OptionBits(kUCKeyTranslateNoDeadKeysBit),
			&deadKeyState,
			maxLength,
			&length,
			&characters
		)

		guard error == noErr else { return nil }
		return String(utf16CodeUnits: characters, count: length)
	}
}

extension HotKeyKit.Shortcut: CustomStringConvertible {
	/// 단축키의 문자열 표현. `⌘A` 식.
	/// ```swift
	/// print(HotKeyKit.Shortcut(.a, modifiers: [.command])) //=> "⌘A"
	/// ```
	public var description: String {
		modifiers.presentableDescription + (keyToCharacter()?.capitalized ?? "�")
	}
}
#endif
