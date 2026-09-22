#if os(macOS)
@preconcurrency import AppKit.NSMenu

import os

/// 전역 단축키 모듈.
///
/// sindresorhus/KeyboardShortcuts 2.x 를 순수 Swift 로 재구현한 드롭인 대체품.
/// Carbon `RegisterEventHotKey` / `InstallEventHandler` 기반 전역 핫키와 SwiftUI
/// 녹화(Recorder) 뷰를 제공한다. 외부 SPM 의존이 없다.
///
/// - Important: UserDefaults 저장 포맷은 KeyboardShortcuts 와 **바이트 단위로 동일**하다.
///   키 `KeyboardShortcuts_<name>`, 값은 `Shortcut` 의 JSON 문자열. 덕분에 사용자가
///   이전 버전에서 설정한 단축키가 마이그레이션 후에도 그대로 살아 있다.
public enum HotKeyKit {
	// MARK: - Storage prefix (마이그레이션 호환 — 절대 바꾸지 말 것)

	/// KeyboardShortcuts 2.x 가 쓰던 UserDefaults 키 접두사.
	/// 사용자 기존 설정 보존을 위해 동일하게 유지한다.
	static let userDefaultsPrefix = "KeyboardShortcuts_"

	static func userDefaultsKey(for shortcutName: Name) -> String {
		"\(userDefaultsPrefix)\(shortcutName.rawValue)"
	}

	// MARK: - Handler registries & Facade State

	private struct FacadeState: @unchecked Sendable {
		var keyDownHandlers = [Name: [() -> Void]]()
		var keyUpHandlers = [Name: [() -> Void]]()
		var registeredShortcuts = Set<Shortcut>()
		var isPaused = false
		var isEnabled = true
		var isMenuOpen = false
		var isInitialized = false
		var openMenuObserver: NSObjectProtocol?
		var closeMenuObserver: NSObjectProtocol?

		var shortcutsForHandlers: Set<Shortcut> {
			let names = Set(keyDownHandlers.keys).union(keyUpHandlers.keys)
			return Set(names.compactMap { $0.shortcut })
		}
	}

	private static let stateLock = OSAllocatedUnfairLock(initialState: FacadeState())

	/// 녹화(Recorder) 중에는 전역 핫키 발화를 잠시 끈다.
	public static var isPaused: Bool {
		get { stateLock.withLock { $0.isPaused } }
		set { stateLock.withLock { $0.isPaused = newValue } }
	}

	/// 전역 단축키 모니터링의 전체 on/off. 기본 true.
	public static var isEnabled: Bool {
		get { stateLock.withLock { $0.isEnabled } }
		set {
			let changed = stateLock.withLock { state -> Bool in
				guard state.isEnabled != newValue else { return false }
				state.isEnabled = newValue
				return true
			}
			if changed {
				CarbonHotKeyCenter.shared.updateEventHandler()
			}
		}
	}

	// MARK: - NSMenu tracking (메뉴 열림 중에도 핫키 동작)

	/// 메뉴바 앱에서 NSMenu 가 열려 있을 때 전역 핫키가 동작하게 하는 스위치.
	/// NSMenu 가 tracking run mode 로 들어가 이벤트를 막기 때문 — raw key 이벤트로 전환한다.
	public fileprivate(set) static var isMenuOpen: Bool {
		get { stateLock.withLock { $0.isMenuOpen } }
		set {
			let changed = stateLock.withLock { state -> Bool in
				guard state.isMenuOpen != newValue else { return false }
				state.isMenuOpen = newValue
				return true
			}
			if changed {
				CarbonHotKeyCenter.shared.updateEventHandler()
			}
		}
	}

	/// NSMenu tracking 알림 리스너를 단다. Name 초기화 시 최초 1회 자동 호출.
	static func initialize() {
		let needsInit = stateLock.withLock { state -> Bool in
			if !state.isInitialized {
				state.isInitialized = true
				return true
			}
			return false
		}
		guard needsInit else { return }

		let openObserver = NotificationCenter.default.addObserver(
			forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil
		) { _ in
			isMenuOpen = true
		}

		let closeObserver = NotificationCenter.default.addObserver(
			forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil
		) { _ in
			isMenuOpen = false
		}

		stateLock.withLock { state in
			state.openMenuObserver = openObserver
			state.closeMenuObserver = closeObserver
		}
	}

	// MARK: - Register / unregister (내부)

	private static func register(_ shortcut: Shortcut) {
		let shouldRegister = stateLock.withLock { state -> Bool in
			if !state.registeredShortcuts.contains(shortcut) {
				state.registeredShortcuts.insert(shortcut)
				return true
			}
			return false
		}
		guard shouldRegister else { return }

		CarbonHotKeyCenter.shared.register(
			shortcut,
			onKeyDown: handleOnKeyDown,
			onKeyUp: handleOnKeyUp
		)
	}

	/// 이름에 Shortcut 이 있으면 Carbon 에 등록한다.
	fileprivate static func registerShortcutIfNeeded(for name: Name) {
		guard let shortcut = getShortcut(for: name) else { return }
		register(shortcut)
	}

	private static func unregister(_ shortcut: Shortcut) {
		let shouldUnregister = stateLock.withLock { state -> Bool in
			if state.registeredShortcuts.contains(shortcut) {
				state.registeredShortcuts.remove(shortcut)
				return true
			}
			return false
		}
		guard shouldUnregister else { return }
		CarbonHotKeyCenter.shared.unregister(shortcut)
	}

	/// 더 이상 콜백이 붙어 있지 않은 Shortcut 만 Carbon 에서 해제한다.
	private static func unregisterIfNeeded(_ shortcut: Shortcut) {
		let shouldUnregister = stateLock.withLock { state -> Bool in
			if !state.shortcutsForHandlers.contains(shortcut), state.registeredShortcuts.contains(shortcut) {
				state.registeredShortcuts.remove(shortcut)
				return true
			}
			return false
		}
		guard shouldUnregister else { return }
		CarbonHotKeyCenter.shared.unregister(shortcut)
	}

	// MARK: - Event dispatch
 
	private struct ActionBox: @unchecked Sendable {
		let actions: [() -> Void]
	}

	private static func handleOnKeyDown(_ shortcut: Shortcut) {
		let box = stateLock.withLock { state -> ActionBox in
			guard !state.isPaused else { return ActionBox(actions: []) }
			var actions = [() -> Void]()
			for (name, handlers) in state.keyDownHandlers {
				guard getShortcut(for: name) == shortcut else { continue }
				actions.append(contentsOf: handlers)
			}
			return ActionBox(actions: actions)
		}
		for handler in box.actions { handler() }
	}

	private static func handleOnKeyUp(_ shortcut: Shortcut) {
		let box = stateLock.withLock { state -> ActionBox in
			guard !state.isPaused else { return ActionBox(actions: []) }
			var actions = [() -> Void]()
			for (name, handlers) in state.keyUpHandlers {
				guard getShortcut(for: name) == shortcut else { continue }
				actions.append(contentsOf: handlers)
			}
			return ActionBox(actions: actions)
		}
		for handler in box.actions { handler() }
	}

	// MARK: - Public listener API

	/// 단축키가 눌릴 때(keyDown) 실행할 콜백을 등록한다. 여러 리스너 등록 가능.
	/// 아직 사용자가 단축키를 설정하지 않았어도 안전하게 호출할 수 있다(설정 전까지 대기).
	public static func onKeyDown(for name: Name, action: @escaping () -> Void) {
		nonisolated(unsafe) let unsafeAction = action
		stateLock.withLock { state in
			state.keyDownHandlers[name, default: []].append(unsafeAction)
		}
		registerShortcutIfNeeded(for: name)
	}

	/// 단축키가 떼질 때(keyUp) 실행할 콜백을 등록한다.
	public static func onKeyUp(for name: Name, action: @escaping () -> Void) {
		nonisolated(unsafe) let unsafeAction = action
		stateLock.withLock { state in
			state.keyUpHandlers[name, default: []].append(unsafeAction)
		}
		registerShortcutIfNeeded(for: name)
	}

	/// legacy 핸들러를 모두 제거한다(재등록으로 중복 발화를 막을 때 사용).
	public static func removeAllHandlers() {
		let shortcutsToUnregister = stateLock.withLock { state -> Set<Shortcut> in
			let shortcuts = state.shortcutsForHandlers
			state.registeredShortcuts.subtract(shortcuts)
			state.keyDownHandlers = [:]
			state.keyUpHandlers = [:]
			return shortcuts
		}
		for shortcut in shortcutsToUnregister {
			CarbonHotKeyCenter.shared.unregister(shortcut)
		}
	}

	// MARK: - Shortcut storage (UserDefaults — KeyboardShortcuts 호환)

	/// 이름에 단축키를 저장한다. nil 이면 제거한다.
	public static func setShortcut(_ shortcut: Shortcut?, for name: Name) {
		if let shortcut {
			userDefaultsSet(name: name, shortcut: shortcut)
		} else {
			if name.defaultShortcut != nil {
				userDefaultsDisable(name: name)
			} else {
				userDefaultsRemove(name: name)
			}
		}
	}

	/// 이름의 단축키를 읽는다. 없으면 nil.
	public static func getShortcut(for name: Name) -> Shortcut? {
		guard
			let raw = UserDefaults.standard.string(forKey: userDefaultsKey(for: name)),
			let data = raw.data(using: .utf8),
			let decoded = try? JSONDecoder().decode(Shortcut.self, from: data)
		else {
			return nil
		}
		return decoded
	}

	/// 한 개 이상의 이름 단축키를 disable(등록 해제) 한다. 값은 보존.
	public static func disable(_ names: [Name]) {
		for name in names {
			guard let shortcut = getShortcut(for: name) else { continue }
			unregister(shortcut)
		}
	}

	/// - Note: Swift 가 splatting 을 지원하지 않아 존재하는 오버로드.
	public static func disable(_ names: Name...) { disable(names) }

	/// 한 개 이상의 이름 단축키를 enable(재등록) 한다.
	public static func enable(_ names: [Name]) {
		for name in names {
			guard let shortcut = getShortcut(for: name) else { continue }
			register(shortcut)
		}
	}

	public static func enable(_ names: Name...) { enable(names) }

	/// 단축키를 기본값(defaultShortcut)으로 되돌린다. 기본값이 없으면 nil.
	public static func reset(_ names: [Name]) {
		for name in names {
			setShortcut(name.defaultShortcut, for: name)
		}
	}

	public static func reset(_ names: Name...) { reset(names) }

	// MARK: - UserDefaults low-level (KeyboardShortcuts 2.x 포맷 호환)

	static func userDefaultsContains(name: Name) -> Bool {
		UserDefaults.standard.object(forKey: userDefaultsKey(for: name)) != nil
	}

	static func userDefaultsSet(name: Name, shortcut: Shortcut) {
		guard let encoded = try? JSONEncoder().encode(shortcut).asString else { return }

		if let oldShortcut = getShortcut(for: name) {
			unregister(oldShortcut)
		}

		register(shortcut)
		UserDefaults.standard.set(encoded, forKey: userDefaultsKey(for: name))
		userDefaultsDidChange(name: name)
	}

	/// 기본 단축키가 있는 이름을 nil 로 둘 때 — 값을 `false` 로 써서 "명시적 빈 값"을 표시.
	/// KeyboardShortcuts 2.x 와 동일한 sentinel(getShortcut 이 nil 을 반환).
	static func userDefaultsDisable(name: Name) {
		guard getShortcut(for: name) != nil else { return }
		UserDefaults.standard.set(false, forKey: userDefaultsKey(for: name))
		if let shortcut = getShortcut(for: name) { unregister(shortcut) }
		userDefaultsDidChange(name: name)
	}

	static func userDefaultsRemove(name: Name) {
		guard let shortcut = getShortcut(for: name) else {
			UserDefaults.standard.removeObject(forKey: userDefaultsKey(for: name))
			return
		}
		UserDefaults.standard.removeObject(forKey: userDefaultsKey(for: name))
		unregister(shortcut)
		userDefaultsDidChange(name: name)
	}

	static func userDefaultsDidChange(name: Name) {
		NotificationCenter.default.post(name: .hotKeyShortcutDidChange, object: nil, userInfo: ["name": name])
	}
}

extension Notification.Name {
	/// 단축키 이름의 저장값이 바뀌었을 때. Recorder 가 자신의 표시를 갱신한다.
	static let hotKeyShortcutDidChange = Self("KeyboardShortcuts_shortcutByNameDidChange")
}
#endif
