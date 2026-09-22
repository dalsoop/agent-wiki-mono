#if os(macOS)
@preconcurrency import AppKit
import os

// MARK: - Local event monitors

/// `NSEvent.addLocalMonitorForEvents` 래퍼. `.start()` 로 시작.
// @unchecked Sendable: RecorderCocoa(메인 액터)에서만 생성·해제되며, NSEvent 모니터 API 도
// 메인 스레드에서만 동작한다. swiftkit Swift 6 규약.
final class LocalEventMonitor: @unchecked Sendable {
	private let events: NSEvent.EventTypeMask
	private let callback: (NSEvent) -> NSEvent?
	// deinit(비격리)에서 접근하므로 nonisolated(unsafe).
	nonisolated(unsafe) private weak var monitor: AnyObject?

	init(events: NSEvent.EventTypeMask, callback: @escaping (NSEvent) -> NSEvent?) {
		self.events = events
		self.callback = callback
	}

	deinit { stop() }

	@discardableResult
	func start() -> Self {
		// NSEvent.addLocalMonitorForEvents 는 메인 액터. RecorderCocoa(메인)에서 호출된다.
		MainActor.assumeIsolated {
			monitor = NSEvent.addLocalMonitorForEvents(matching: events, handler: callback) as AnyObject
		}
		return self
	}

	func stop() {
		guard let monitor else { return }
		MainActor.assumeIsolated {
			NSEvent.removeMonitor(monitor)
		}
	}
}

/// NSMenu 가 tracking 중인 run mode 에서도 키 이벤트를 뽑아낸다.
/// 이벤트 큐에서 전부 꺼내 매칭 것만 callback 로 보내고, 나머지는 큐에 되돌린다.
// @unchecked Sendable: 메인 런루프에만 올라가는 옵저버. NSApp 호출은 메인 스레드 보장.
final class RunLoopLocalEventMonitor: @unchecked Sendable {
	/// 비-Sendable 클로저를 @Sendable 옵저버 블록에 넘기기 위한 박스.
	/// 옵저버는 메인 런루프에서만 발화하므로 단일 스레드 접근이 보장된다.
	private struct CallbackBox: @unchecked Sendable {
		let invoke: (NSEvent) -> NSEvent?
	}

	private let runLoopMode: RunLoop.Mode
	private let callback: CallbackBox
	private let observer: CFRunLoopObserver

	init(
		events: NSEvent.EventTypeMask,
		runLoopMode: RunLoop.Mode,
		callback: @escaping (NSEvent) -> NSEvent?
	) {
		self.runLoopMode = runLoopMode
		let callbackBox = CallbackBox(invoke: callback)
		self.callback = callbackBox

		self.observer = CFRunLoopObserverCreateWithHandler(
			nil, CFRunLoopActivity.beforeSources.rawValue, true, 0
		) { _, _ in
			// 옵저버는 메인 런루프에만 add 되므로 메인 스레드 보장. NSApp 접근 안전.
			MainActor.assumeIsolated {
				// 매칭과 무관하게 모든 이벤트를 순서 보존해 꺼낸 뒤 처리한다.
				var eventsToHandle = [NSEvent]()
				while let eventToHandle = NSApp.nextEvent(matching: .any, until: nil, inMode: .default, dequeue: true) {
					eventsToHandle.append(eventToHandle)
				}
				for eventToHandle in eventsToHandle {
					var handledEvent: NSEvent?
					if !events.contains(NSEvent.EventTypeMask(rawValue: 1 << eventToHandle.type.rawValue)) {
						handledEvent = eventToHandle
					} else if let callbackEvent = callbackBox.invoke(eventToHandle) {
						handledEvent = callbackEvent
					}
					guard let handledEvent else { continue }
					NSApp.postEvent(handledEvent, atStart: false)
				}
			}
		}
	}

	private struct MonitorState {
		var isRunning = false
	}

	private let stateLock = OSAllocatedUnfairLock(initialState: MonitorState())

	deinit { stop() }

	@discardableResult
	func start() -> Self {
		let shouldStart = stateLock.withLock { state -> Bool in
			if !state.isRunning {
				state.isRunning = true
				return true
			}
			return false
		}
		guard shouldStart else { return self }

		if Thread.isMainThread {
			CFRunLoopAddObserver(
				CFRunLoopGetMain(), observer,
				CFRunLoopMode(runLoopMode.rawValue as CFString)
			)
		} else {
			DispatchQueue.main.sync {
				CFRunLoopAddObserver(
					CFRunLoopGetMain(), observer,
					CFRunLoopMode(runLoopMode.rawValue as CFString)
				)
			}
		}
		return self
	}

	func stop() {
		let shouldStop = stateLock.withLock { state -> Bool in
			if state.isRunning {
				state.isRunning = false
				return true
			}
			return false
		}
		guard shouldStop else { return }

		if Thread.isMainThread {
			CFRunLoopRemoveObserver(
				CFRunLoopGetMain(), observer,
				CFRunLoopMode(runLoopMode.rawValue as CFString)
			)
		} else {
			DispatchQueue.main.sync {
				CFRunLoopRemoveObserver(
					CFRunLoopGetMain(), observer,
					CFRunLoopMode(runLoopMode.rawValue as CFString)
				)
			}
		}
	}
}

// MARK: - NSTextField caret helpers

extension NSTextField {
	func hideCaret() {
		(currentEditor() as? NSTextView)?.insertionPointColor = .clear
	}

	func restoreCaret() {
		(currentEditor() as? NSTextView)?.insertionPointColor = .labelColor
	}
}

extension NSView {
	func focus() { window?.makeFirstResponder(self) }
	func blur() { window?.makeFirstResponder(nil) }
}

// MARK: - NSAlert helper

extension NSAlert {
	/// 윈도우에 sheet 로, 윈도우가 없으면 app-modal 로 띄운다.
	@discardableResult
	static func showModal(
		for window: NSWindow? = nil,
		title: String,
		message: String? = nil,
		style: Style = .warning,
		icon: NSImage? = nil,
		buttonTitles: [String] = []
	) -> NSApplication.ModalResponse {
		NSAlert(
			title: title, message: message, style: style,
			icon: icon, buttonTitles: buttonTitles
		).runModal(for: window)
	}

	convenience init(
		title: String,
		message: String? = nil,
		style: Style = .warning,
		icon: NSImage? = nil,
		buttonTitles: [String] = []
	) {
		self.init()
		self.messageText = title
		self.alertStyle = style
		self.icon = icon
		for buttonTitle in buttonTitles {
			addButton(withTitle: buttonTitle)
		}
		if let message { self.informativeText = message }
	}

	@discardableResult
	func runModal(for window: NSWindow? = nil) -> NSApplication.ModalResponse {
		guard let window else { return runModal() }
		beginSheetModal(for: window) { returnCode in
			NSApp.stopModal(withCode: returnCode)
		}
		return NSApp.runModal(for: window)
	}
}
#endif
