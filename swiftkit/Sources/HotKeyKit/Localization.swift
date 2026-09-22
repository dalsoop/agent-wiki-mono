#if os(macOS)
import Foundation

/// HotKeyKit 내부 문자열(Recorder 플레이스홀더·경고).
///
/// KeyboardShortcuts 2.x 는 `.bundle`(.lproj 다수)로 i18n 을 제공했고, App Store 샌드박스에서
/// SwiftPM Bundle.module 경로가 깨지는 문제를 배포 패치로 우회했다. HotKeyKit 은 **빌트인
/// 사전**으로 이를 제거한다 — 외부 리소스가 없으므로 샌드박스·배포 환경에서 동일하게 동작한다.
enum HotKeyL10n {
	/// 시스템 선호 언어로 한국어를 쓰는지.
	private static var prefersKorean: Bool {
		let preferred = Bundle.main.preferredLocalizations + Locale.preferredLanguages
		return preferred.first(where: { $0.hasPrefix("ko") }) != nil
	}

	/// 키 → (한국어, 영어).
	private static let table: [String: (ko: String, en: String)] = [
		"record_shortcut": ("단축키 등록", "Record Shortcut"),
		"press_shortcut": ("단축키 입력", "Press Shortcut"),
		"keyboard_shortcut_used_by_menu_item": (
			"이 키보드 단축키는 이미 “%@” 메뉴 항목에 사용되고 있으므로 등록할 수 없습니다.",
			"This keyboard shortcut cannot be used as it’s already used by the “%@” menu item."
		),
		"keyboard_shortcut_used_by_system": (
			"이 키보드 단축키는 이미 시스템상에서 사용되고 있으므로 등록할 수 없습니다.",
			"This keyboard shortcut cannot be used as it’s already a system-wide keyboard shortcut."
		),
		"keyboard_shortcuts_can_be_changed": (
			"대부분의 시스템 키보드 단축키는 “시스템 설정 › 키보드 › 키보드 단축키”에서 변경 가능합니다.",
			"Most system-wide keyboard shortcuts can be changed in “System Settings › Keyboard › Keyboard Shortcuts”."
		),
		"keyboard_shortcut_disallowed": (
			"Option 수정자는 Command 또는 Control과 함께 사용해야 합니다.",
			"Option modifier must be combined with Command or Control."
		),
		"force_use_shortcut": ("그래도 사용", "Use Anyway"),
		"ok": ("확인", "OK"),
		"space_key": ("빈칸", "Space"),
	]

	/// 현재 언어의 문자열. 포맷 인자를 받는 경우 `args` 로 치환.
	static func string(_ key: String, _ args: CVarArg...) -> String {
		guard let entry = table[key] else { return key }
		let template = prefersKorean ? entry.ko : entry.en
		guard args.isEmpty else {
			return String(format: template, arguments: args)
		}
		return template
	}

	/// space 키 표시(description 에서 씀).
	static var spaceKey: String { string("space_key") }
}
#endif
