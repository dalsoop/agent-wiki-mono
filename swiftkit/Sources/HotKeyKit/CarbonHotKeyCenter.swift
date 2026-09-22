#if os(macOS)
@preconcurrency import AppKit
import Carbon.HIToolbox
import Foundation
import os

private let hotKeyLog = Logger(subsystem: "net.ranode.HotKeyKit", category: "carbon")

// MARK: - Sendable wrappers for Carbon C types & closures

private struct EventHotKeyRefBox: @unchecked Sendable {
	let ref: EventHotKeyRef
}

private struct EventHandlerRefBox: @unchecked Sendable {
	let ref: EventHandlerRef
}

private struct ActionPayload: @unchecked Sendable {
	let action: (HotKeyKit.Shortcut) -> Void
	let shortcut: HotKeyKit.Shortcut
}

/// Carbon `RegisterEventHotKey` / `InstallEventHandler` 로 전역 핫키를 등록·해제한다.
///
/// 두 가지 이벤트 경로를 쓴다(KeyboardShortcuts 2.x 와 동일):
/// 1. 보통 때 — `kEventClassKeyboard` 의 `kEventHotKeyPressed`/`Released`.
/// 2. NSMenu 가 tracking 중일 때 — 메뉴가 이벤트를 삼키므로 raw key down/up 을
///    `RunLoop` 모니터로 가로챈다(macOS 14+).
///
/// `os.OSAllocatedUnfairLock` 으로 핸들러 딕셔너리(`handlers`), 카운터(`nextID`), 이벤트 핸들러 참조를
/// 감싸 백그라운드 이벤트 콜백 및 메인 스레드 등록/해제 시 Swift 6 Data Race 를 방지한다.
public final class CarbonHotKeyCenter: @unchecked Sendable {
	public static let shared = CarbonHotKeyCenter()

	private struct HotKey: @unchecked Sendable {
		let shortcut: HotKeyKit.Shortcut
		let carbonHotKeyId: Int
		var carbonHotKey: EventHotKeyRef?
		let onKeyDown: (HotKeyKit.Shortcut) -> Void
		let onKeyUp: (HotKeyKit.Shortcut) -> Void

		init(
			shortcut: HotKeyKit.Shortcut,
			carbonHotKeyID: Int,
			carbonHotKey: EventHotKeyRef?,
			onKeyDown: @escaping (HotKeyKit.Shortcut) -> Void,
			onKeyUp: @escaping (HotKeyKit.Shortcut) -> Void
		) {
			self.shortcut = shortcut
			self.carbonHotKeyId = carbonHotKeyID
			self.carbonHotKey = carbonHotKey
			self.onKeyDown = onKeyDown
			self.onKeyUp = onKeyUp
		}
	}

	private struct State: @unchecked Sendable {
		var handlers = [Int: HotKey]()
		var nextID = 0
		var eventHandler: EventHandlerRef?

		var hotKeys: [Int: HotKey] {
			get { handlers }
			set { handlers = newValue }
		}
	}

	private let lock = OSAllocatedUnfairLock(initialState: State())

	// "HKHS" — HotKeyKit Hotkey Signature. OSType 4문자를 정수로 표현한 서명.
	// (UTGetOSTypeFromString("HKHS") deprecated 대응.)
	private let hotKeySignature: UInt32 = 0x484B4853

	private let hotKeyEventTypes = [
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
	]
	private let rawKeyEventTypes = [
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyDown)),
		EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventRawKeyUp)),
	]

	/// NSMenu tracking 중에 raw key 이벤트를 가로챈다.
	private let keyEventMonitor: RunLoopLocalEventMonitor

	private init() {
		self.keyEventMonitor = RunLoopLocalEventMonitor(
			events: [.keyDown, .keyUp],
			runLoopMode: .eventTracking
		) { event in
			guard
				let eventRef = OpaquePointer(event.eventRef),
				CarbonHotKeyCenter.shared.handleRawKeyEvent(eventRef) == noErr
			else {
				return event
			}
			return nil
		}
	}

	// MARK: - EventHandler lifecycle

	private func setUpEventHandlerIfNeeded() {
		let needsInstall = lock.withLock { $0.eventHandler == nil }
		guard needsInstall, let dispatcher = GetEventDispatcherTarget() else { return }

		var handler: EventHandlerRef?
		let error = InstallEventHandler(
			dispatcher,
			{ _, event, _ in CarbonHotKeyCenter.shared.handleEvent(event) },
			0,
			nil,
			nil,
			&handler
		)

		guard error == noErr, let handler else { return }
		let boxedHandler = EventHandlerRefBox(ref: handler)
		let shouldUpdate = lock.withLock { state -> Bool in
			if state.eventHandler == nil {
				state.eventHandler = boxedHandler.ref
				return true
			}
			return false
		}
		if shouldUpdate {
			updateEventHandler()
		}
	}

	/// `isEnabled` / `isMenuOpen` 변화에 맞춰 이벤트 핸들러 종류를 전환한다.
	public func updateEventHandler() {
		let handlerBox: EventHandlerRefBox? = lock.withLock { state in
			state.eventHandler.map(EventHandlerRefBox.init)
		}
		guard let handlerBox else { return }
		let handler = handlerBox.ref

		if HotKeyKit.isEnabled {
			if HotKeyKit.isMenuOpen {
				softUnregisterAll()
				RemoveEventTypesFromHandler(handler, hotKeyEventTypes.count, hotKeyEventTypes)
				if #available(macOS 14, *) {
					keyEventMonitor.start()
				} else {
					AddEventTypesToHandler(handler, rawKeyEventTypes.count, rawKeyEventTypes)
				}
			} else {
				softRegisterAll()
				if #available(macOS 14, *) {
					keyEventMonitor.stop()
				} else {
					RemoveEventTypesFromHandler(handler, rawKeyEventTypes.count, rawKeyEventTypes)
				}
				AddEventTypesToHandler(handler, hotKeyEventTypes.count, hotKeyEventTypes)
			}
		} else {
			softUnregisterAll()
			RemoveEventTypesFromHandler(handler, hotKeyEventTypes.count, hotKeyEventTypes)
			if #available(macOS 14, *) {
				keyEventMonitor.stop()
			} else {
				RemoveEventTypesFromHandler(handler, rawKeyEventTypes.count, rawKeyEventTypes)
			}
		}
	}

	// MARK: - Register / unregister

	public func register(
		_ shortcut: HotKeyKit.Shortcut,
		onKeyDown: @escaping (HotKeyKit.Shortcut) -> Void,
		onKeyUp: @escaping (HotKeyKit.Shortcut) -> Void
	) {
		let id = lock.withLock { state -> Int in
			state.nextID += 1
			return state.nextID
		}

		var eventHotKey: EventHotKeyRef?
		let error = RegisterEventHotKey(
			UInt32(shortcut.carbonKeyCode),
			UInt32(shortcut.carbonModifiers),
			EventHotKeyID(signature: hotKeySignature, id: UInt32(id)),
			GetEventDispatcherTarget(),
			0,
			&eventHotKey
		)

		// 헤드리스(xctest) 등에서는 등록이 실패할 수 있다 — 콜백만 남기고 조용히 넘어간다.
		// 저장값은 UserDefaults 에 그대로 있으므로 사용자 설정은 유지된다.
		guard error == noErr, let carbonHotKey = eventHotKey else {
			#if DEBUG
			hotKeyLog.error("핫키 등록 실패 \(String(describing: shortcut)): OSStatus \(error)")
			#endif
			return
		}

		let hotKey = HotKey(
			shortcut: shortcut,
			carbonHotKeyID: id,
			carbonHotKey: carbonHotKey,
			onKeyDown: onKeyDown,
			onKeyUp: onKeyUp
		)

		lock.withLock { state in
			state.handlers[id] = hotKey
		}

		setUpEventHandlerIfNeeded()
	}

	/// 등록은 됐으나 soft-unregister 된 핫키를 다시 Carbon 에 붙인다.
	private func softRegisterAll() {
		let targets: [(id: Int, shortcut: HotKeyKit.Shortcut)] = lock.withLock { state in
			state.handlers.compactMap { id, hotKey in
				hotKey.carbonHotKey == nil ? (id, hotKey.shortcut) : nil
			}
		}

		guard !targets.isEmpty, let dispatcher = GetEventDispatcherTarget() else { return }

		for target in targets {
			var eventHotKey: EventHotKeyRef?
			let error = RegisterEventHotKey(
				UInt32(target.shortcut.carbonKeyCode),
				UInt32(target.shortcut.carbonModifiers),
				EventHotKeyID(signature: hotKeySignature, id: UInt32(target.id)),
				dispatcher,
				0,
				&eventHotKey
			)

			guard error == noErr, let eventHotKey else {
				#if DEBUG
				hotKeyLog.error("핫키 재등록 실패 \(String(describing: target.shortcut)): OSStatus \(error)")
				#endif
				lock.withLock { state in
					_ = state.handlers.removeValue(forKey: target.id)
				}
				continue
			}

			let boxedEventHotKey = EventHotKeyRefBox(ref: eventHotKey)
			let shouldUnregister: Bool = lock.withLock { state in
				if state.handlers[target.id] != nil {
					state.handlers[target.id]?.carbonHotKey = boxedEventHotKey.ref
					return false
				} else {
					return true
				}
			}

			if shouldUnregister {
				UnregisterEventHotKey(boxedEventHotKey.ref)
			}
		}
	}

	public func unregister(_ shortcut: HotKeyKit.Shortcut) {
		let refsToUnregister: [EventHotKeyRefBox] = lock.withLock { state in
			var refs = [EventHotKeyRefBox]()
			let matchingIDs = state.handlers.filter { $0.value.shortcut == shortcut }.map { $0.key }
			for id in matchingIDs {
				if let hotKey = state.handlers.removeValue(forKey: id), let ref = hotKey.carbonHotKey {
					refs.append(EventHotKeyRefBox(ref: ref))
				}
			}
			return refs
		}

		for box in refsToUnregister {
			UnregisterEventHotKey(box.ref)
		}
	}

	/// Carbon 등록만 해제하고 메타데이터는 남긴다(메뉴 tracking 중 전환용).
	private func softUnregisterAll() {
		let refsToUnregister: [EventHotKeyRefBox] = lock.withLock { state in
			var refs = [EventHotKeyRefBox]()
			for id in state.handlers.keys {
				if let ref = state.handlers[id]?.carbonHotKey {
					refs.append(EventHotKeyRefBox(ref: ref))
					state.handlers[id]?.carbonHotKey = nil
				}
			}
			return refs
		}

		for box in refsToUnregister {
			UnregisterEventHotKey(box.ref)
		}
	}

	// MARK: - Event dispatch

	fileprivate func handleEvent(_ event: EventRef?) -> OSStatus {
		guard let event else { return OSStatus(eventNotHandledErr) }

		switch Int(GetEventKind(event)) {
		case kEventHotKeyPressed, kEventHotKeyReleased:
			return handleHotKeyEvent(event)
		case kEventRawKeyDown, kEventRawKeyUp:
			return handleRawKeyEvent(event)
		default:
			break
		}
		return OSStatus(eventNotHandledErr)
	}

	private func handleHotKeyEvent(_ event: EventRef) -> OSStatus {
		var eventHotKeyId = EventHotKeyID()
		let error = GetEventParameter(
			event,
			UInt32(kEventParamDirectObject),
			UInt32(typeEventHotKeyID),
			nil,
			MemoryLayout<EventHotKeyID>.size,
			nil,
			&eventHotKeyId
		)
		guard error == noErr else { return error }

		let signature = eventHotKeyId.signature
		let hotKeyID = Int(eventHotKeyId.id)
		let kind = Int(GetEventKind(event))

		let payload: ActionPayload? = lock.withLock { state in
			guard
				signature == hotKeySignature,
				let hotKey = state.handlers[hotKeyID]
			else {
				return nil
			}

			switch kind {
			case kEventHotKeyPressed:
				return ActionPayload(action: hotKey.onKeyDown, shortcut: hotKey.shortcut)
			case kEventHotKeyReleased:
				return ActionPayload(action: hotKey.onKeyUp, shortcut: hotKey.shortcut)
			default:
				return nil
			}
		}

		guard let payload else {
			return OSStatus(eventNotHandledErr)
		}

		payload.action(payload.shortcut)
		return noErr
	}

	fileprivate func handleRawKeyEvent(_ event: EventRef) -> OSStatus {
		var eventKeyCode = UInt32()
		let keyCodeError = GetEventParameter(
			event, UInt32(kEventParamKeyCode), typeUInt32, nil,
			MemoryLayout<UInt32>.size, nil, &eventKeyCode
		)
		guard keyCodeError == noErr else { return keyCodeError }

		var eventKeyModifiers = UInt32()
		let modsError = GetEventParameter(
			event, UInt32(kEventParamKeyModifiers), typeUInt32, nil,
			MemoryLayout<UInt32>.size, nil, &eventKeyModifiers
		)
		guard modsError == noErr else { return modsError }

		let shortcut = HotKeyKit.Shortcut(
			carbonKeyCode: Int(eventKeyCode),
			carbonModifiers: Int(eventKeyModifiers)
		)

		let kind = Int(GetEventKind(event))
		let payload: ActionPayload? = lock.withLock { state in
			guard let hotKey = state.handlers.values.first(where: { $0.shortcut == shortcut }) else {
				return nil
			}

			switch kind {
			case kEventRawKeyDown:
				return ActionPayload(action: hotKey.onKeyDown, shortcut: hotKey.shortcut)
			case kEventRawKeyUp:
				return ActionPayload(action: hotKey.onKeyUp, shortcut: hotKey.shortcut)
			default:
				return nil
			}
		}

		guard let payload else {
			return OSStatus(eventNotHandledErr)
		}

		payload.action(payload.shortcut)
		return noErr
	}
}
#endif
