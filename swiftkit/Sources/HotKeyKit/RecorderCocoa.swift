#if os(macOS)
@preconcurrency import AppKit
import Carbon.HIToolbox

extension HotKeyKit {
	/// 단축키를 녹화하는 `NSView`. 보통 설정 창에 둔다.
	///
	/// SwiftUI `Recorder` 가 내부적으로 사용한다. AppKit 에서 직접 쓸 수도 있다.
	/// 시스템/메뉴가 점유한 조합은 경고로 막고, 조합은 UserDefaults 에 자동 저장한다.
	public final class RecorderCocoa: NSSearchField, NSSearchFieldDelegate {
		private let minimumWidth = 130.0
		private let onChange: ((_ shortcut: Shortcut?) -> Void)?
		private var canBecomeKey = false
		private var eventMonitor: LocalEventMonitor?
		private var shortcutNameChangeObserver: NSObjectProtocol?
		private var windowDidResignKeyObserver: NSObjectProtocol?
		private var windowDidBecomeKeyObserver: NSObjectProtocol?

		/// 녹화 대상 단축키 이름. 동적으로 바꿀 수 있다.
		public var shortcutName: Name {
			didSet {
				guard shortcutName != oldValue else { return }
				setStringValue(name: shortcutName)
			}
		}

		/// :nodoc:
		override public var canBecomeKeyView: Bool { canBecomeKey }

		/// :nodoc:
		override public var intrinsicContentSize: CGSize {
			var size = super.intrinsicContentSize
			size.width = minimumWidth
			return size
		}

		private var cancelButton: NSButtonCell?

		private var showsCancelButton: Bool {
			get { (cell as? NSSearchFieldCell)?.cancelButtonCell != nil }
			set { (cell as? NSSearchFieldCell)?.cancelButtonCell = newValue ? cancelButton : nil }
		}

		/// - Parameters:
		///   - name: 단축키 이름.
		///   - onChange: 사용자가 조합을 바꾸거나 지웠을 때 호출.
		public required init(
			for name: Name,
			onChange: ((_ shortcut: Shortcut?) -> Void)? = nil
		) {
			self.shortcutName = name
			self.onChange = onChange

			super.init(frame: .zero)
			self.delegate = self
			self.placeholderString = HotKeyL10n.string("record_shortcut")
			self.alignment = .center
			(cell as? NSSearchFieldCell)?.searchButtonCell = nil

			self.wantsLayer = true
			setContentHuggingPriority(.defaultHigh, for: .vertical)
			setContentHuggingPriority(.defaultHigh, for: .horizontal)

			// 조합이 없을 땐 cancel 버튼을 숨겨 플레이스홀더가 가운데 정렬되게 한다. 제일 마지막.
			self.cancelButton = (cell as? NSSearchFieldCell)?.cancelButtonCell

			setStringValue(name: name)
			setUpEvents()
		}

		@available(*, unavailable)
		public required init?(coder: NSCoder) {
			nil
		}

		private func setStringValue(name: HotKeyKit.Name) {
			// UI 컨텍스트(메인 스레드)에서만 불린다.
			stringValue = getShortcut(for: shortcutName).map { "\($0)" } ?? ""
			showsCancelButton = !stringValue.isEmpty
		}

		private func setUpEvents() {
			shortcutNameChangeObserver = NotificationCenter.default.addObserver(
				forName: .hotKeyShortcutDidChange, object: nil, queue: nil
			) { [weak self] notification in
				guard
					let self,
					let nameInNotification = notification.userInfo?["name"] as? HotKeyKit.Name,
					nameInNotification == shortcutName
				else { return }
				setStringValue(name: nameInNotification)
			}
		}

		private func endRecording() {
			eventMonitor = nil
			placeholderString = HotKeyL10n.string("record_shortcut")
			showsCancelButton = !stringValue.isEmpty
			restoreCaret()
			HotKeyKit.isPaused = false
		}

		private func preventBecomingKey() {
			canBecomeKey = false
			// 초기 포커스를 받지 않게 다음 런루프에서 다시 켠다.
			DispatchQueue.main.async { [self] in
				canBecomeKey = true
			}
		}

		/// :nodoc:
		public func controlTextDidChange(_ object: Notification) {
			if stringValue.isEmpty {
				saveShortcut(nil)
			}
			showsCancelButton = !stringValue.isEmpty
			if stringValue.isEmpty { focus() } // 플레이스홀더 가운데 정렬 트릭.
		}

		/// :nodoc:
		public func controlTextDidEndEditing(_ object: Notification) {
			endRecording()
		}

		/// :nodoc:
		override public func viewDidMoveToWindow() {
			guard let window else {
				windowDidResignKeyObserver = nil
				windowDidBecomeKeyObserver = nil
				endRecording()
				return
			}

			// 설정 창이 숨김으로 전환될 때 녹화를 멈춘다(macOS 13.5 설정 창은 닫기≠숨김).
			windowDidResignKeyObserver = NotificationCenter.default.addObserver(
				forName: NSWindow.didResignKeyNotification, object: window, queue: nil
			) { [weak self] _ in
				guard let self, let window = self.window else { return }
				endRecording()
				window.makeFirstResponder(nil)
			}

			// 숨겨진 창이 다시 떠도 초기 포커스를 받지 않게 한다.
			windowDidBecomeKeyObserver = NotificationCenter.default.addObserver(
				forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil
			) { [weak self] _ in
				self?.preventBecomingKey()
			}

			preventBecomingKey()
		}

		/// :nodoc:
		override public func becomeFirstResponder() -> Bool {
			let shouldBecomeFirstResponder = super.becomeFirstResponder()
			guard shouldBecomeFirstResponder else { return shouldBecomeFirstResponder }

			placeholderString = HotKeyL10n.string("press_shortcut")
			showsCancelButton = !stringValue.isEmpty
			hideCaret()
			HotKeyKit.isPaused = true // 위치 중요.
			eventMonitor = LocalEventMonitor(events: [.keyDown, .leftMouseUp, .rightMouseUp]) { [weak self] event in
				self?.handleRecordingEvent(event)
			}.start()

			return shouldBecomeFirstResponder
		}

		private func handleRecordingEvent(_ event: NSEvent) -> NSEvent? {
			let clickPoint = convert(event.locationInWindow, from: nil)
			let clickMargin = 3.0

			// 뷰 바깥 클릭이면 녹화를 끝내고 이벤트를 흘린다.
			if
				event.type == .leftMouseUp || event.type == .rightMouseUp,
				!bounds.insetBy(dx: -clickMargin, dy: -clickMargin).contains(clickPoint)
			{
				blur()
				return event
			}

			guard event.isKeyEvent else { return nil }

			// 수정자 없는 Tab 은 다음 responder 로 포커스를 넘긴다.
			if event.realModifiers.isEmpty, event.specialKey == .tab {
				blur()
				return event
			}

			// Esc 로 취소.
			if event.realModifiers.isEmpty, event.keyCode == kVK_Escape {
				blur()
				return nil
			}

			// Delete/Backspace 로 조합 삭제.
			if event.realModifiers.isEmpty,
			   event.specialKey == .delete || event.specialKey == .deleteForward || event.specialKey == .backspace
			{
				clear()
				return nil
			}

			// Shift 단독은 동작하지 않으므로 거른다(다른 수정자 또는 function key 필요).
			guard
				!event.realModifiers.subtracting(.shift).isEmpty || event.specialKey?.isFunctionKey == true,
				let shortcut = Shortcut(event: event)
			else {
				NSSound.beep()
				return nil
			}

			// 앱 메인 메뉴가 이미 쓰는 조합이면 막는다.
			if let menuItem = shortcut.takenByMainMenu {
				blur()
				NSAlert.showModal(
					for: window,
					title: HotKeyL10n.string("keyboard_shortcut_used_by_menu_item", menuItem.title)
				)
				focus()
				return nil
			}

			// 샌드박스+macOS15 에서 Option 단독 계열은 금지.
			if shortcut.isDisallowed {
				blur()
				NSAlert.showModal(for: window, title: HotKeyL10n.string("keyboard_shortcut_disallowed"))
				focus()
				return nil
			}

			// 시스템 단축키 충돌 — "그래도 사용" 선택 시 계속 진행.
			if shortcut.isTakenBySystem {
				blur()
				let response = NSAlert.showModal(
					for: window,
					title: HotKeyL10n.string("keyboard_shortcut_used_by_system"),
					message: HotKeyL10n.string("keyboard_shortcuts_can_be_changed"),
					buttonTitles: [HotKeyL10n.string("ok"), HotKeyL10n.string("force_use_shortcut")]
				)
				focus()
				guard response == .alertSecondButtonReturn else { return nil }
			}

			stringValue = "\(shortcut)"
			showsCancelButton = true
			saveShortcut(shortcut)
			blur()
			return nil
		}

		/// 현재 조합을 지운다.
		public func clear() {
			saveShortcut(nil)
			stringValue = ""
			showsCancelButton = false
			focus()
		}

		private func saveShortcut(_ shortcut: Shortcut?) {
			setShortcut(shortcut, for: shortcutName)
			onChange?(shortcut)
		}
	}
}
#endif
