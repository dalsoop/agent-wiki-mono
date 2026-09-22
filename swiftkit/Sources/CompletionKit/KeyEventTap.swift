import Foundation
import CoreGraphics

// MARK: - 시스템 전역 keyDown 이벤트 tap

/// 제안이 떠 있을 때 수락 키를 소비하고 전역 토글·강제 발동 단축키를 처리한다.
/// 키 조합은 KeyBindingStore 의 액션별 바인딩을 따르고, Esc(제안 닫기)만 고정이다.
/// Accessibility(입력 감시) 권한이 없으면 tapCreate 가 실패해 start() 가 false 를 반환한다.
@MainActor
public final class KeyEventTap {
    /// 수락 키 이벤트 수신자 (CompletionCoordinator).
    public weak var handler: AcceptKeyHandling?
    public private(set) var isRunning: Bool = false

    /// TextInserter 합성 이벤트 식별 magic ("KTyp"). eventSourceUserData 필드에 실린다.
    nonisolated public static let syntheticEventMagic: Int64 = 0x4B54_7970

    /// ANSI 숫자열 keyCode → 1~9 (대체 후보 선택용)
    nonisolated static let digitKeyCodes: [Int64: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]

    // deinit(nonisolated)에서 방어적 무효화를 해야 해서 unsafe 표기 — 실제 접근은 전부 메인 스레드
    nonisolated(unsafe) private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init() {}

    deinit {
        // stop() 없이 해제될 경우 refcon(unretained self)이 dangling 되지 않게 포트 무효화 (방어).
        if let tapPort { CFMachPortInvalidate(tapPort) }
    }

    /// tap 설치. 이미 실행 중이면 true. AX 권한이 없으면 tapCreate 실패 → false.
    @discardableResult
    public func start() -> Bool {
        if isRunning { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyEventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tapPort = port
        runLoopSource = source
        isRunning = true
        return true
    }

    public func stop() {
        guard isRunning else { return }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        tapPort = nil
        isRunning = false
    }

    // MARK: - C 콜백에서 넘어오는 진입점 (main run loop → MainActor 보장)

    /// timeout / user-input 으로 시스템이 꺼 버린 tap 을 다시 켠다.
    func reenableTap() {
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    /// keyDown 하나에 대한 소비 여부 판정. true = 이벤트 소비(콜백이 nil 반환).
    ///
    /// 판정 순서 (KeyBindingStore 바인딩 기준, Esc 만 고정):
    /// 0. 단축키 레코딩 중(suspendedForRecording)이면 전 키 통과 — 레코더가 직접 받는다.
    /// 1. globalToggle → 2. forceActivate — 둘은 wantsAcceptKeys 와 무관하게 소비.
    /// 3. wantsAcceptKeys 게이트 (제안이 안 떠 있으면 이하 통과).
    /// 4. acceptFull → 5. acceptWord — 사용자가 실수로 두 액션에 같은 키를
    ///    바인딩한 경우 먼저 검사하는 acceptFull 이 우선한다.
    /// 6. Esc(keyCode 53, 무수식) 닫기 — 고정 키, 바인딩 대상 아님.
    /// 수식키 포함 바인딩도 그대로 비교한다 (caps/fn/패드 플래그는 무시).
    func shouldConsume(keyCode: Int64, flags: CGEventFlags) -> Bool {
        let bindings = KeyBindingStore.shared

        // 0. 단축키 레코딩 중 — 어떤 키도 소비하지 않고 전부 통과.
        if bindings.suspendedForRecording { return false }

        // 1. 전역 토글 — 핸들러가 실제로 처리(true)할 때만 소비. 빈 구현(false)이면
        //    키를 삼키지 않아 다른 앱의 ⌃⌥⌘` 단축키를 가리지 않는다.
        if bindings.matches(.globalToggle, keyCode: keyCode, flags: flags) {
            return handler?.handleGlobalToggle() ?? false
        }

        // 2. 강제 발동 — 제안 유무와 무관하게 소비.
        if bindings.matches(.forceActivate, keyCode: keyCode, flags: flags) {
            handler?.handleForceActivate()
            return true
        }

        // 2.5. 수정 모드 발동(⌥⌘K) — 선택 유무와 무관하게 소비.
        if bindings.matches(.editActivate, keyCode: keyCode, flags: flags) {
            return handler?.handleEditActivate() ?? false
        }

        // 3. 핸들러 없음 / 제안 안 떠 있음 → 통과.
        guard let handler, handler.wantsAcceptKeys else { return false }

        // 4~5. 수락 키 — 바인딩 일치 비교 (isUnmodified 가드 대신 binding.matches).
        if bindings.matches(.acceptFull, keyCode: keyCode, flags: flags) {
            return handler.handleAcceptFull()
        }
        if bindings.matches(.acceptWord, keyCode: keyCode, flags: flags) {
            return handler.handleAcceptWord()
        }
        if bindings.matches(.acceptLine, keyCode: keyCode, flags: flags) {
            return handler.handleAcceptLine()
        }

        // 5.5. 대체 후보 숫자 선택 (1~9, 무수식) — 대체 목록 표시 중일 때만.
        if handler.wantsDigitKeys, ModifierMatcher.isUnmodified(flags),
           let digit = Self.digitKeyCodes[keyCode] {
            return handler.handleAlternative(digit)
        }

        // 6. Esc 닫기 — 고정.
        if keyCode == AcceptKeyCode.escape.rawValue, ModifierMatcher.isUnmodified(flags) {
            return handler.handleDismiss()
        }
        // 7. 통과하는 콘텐츠 키(글자·숫자·기호·스페이스·리턴·백스페이스)는 소비하지 않고
        //    타이핑 활동만 알린다 → 자동 트리거(디바운스). 내비/펑션/수식 단독은 제외.
        if Self.isContentKey(keyCode: keyCode, flags: flags) {
            handler.handleTypingActivity()
        }
        return false // 그 외 통과
    }

    /// 텍스트를 만들거나 지우는 키인지(내비게이션·펑션·⌘/⌃/⌥ 조합 제외).
    nonisolated static func isContentKey(keyCode: Int64, flags: CGEventFlags) -> Bool {
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return false
        }
        return !nonContentKeyCodes.contains(keyCode)
    }

    /// 콘텐츠가 아닌 keyCode — 화살표/홈엔드/펑션/esc 등.
    nonisolated static let nonContentKeyCodes: Set<Int64> = [
        53,                              // esc
        123, 124, 125, 126,              // ← → ↓ ↑
        115, 116, 117, 119, 121,         // home, pgup, fwd-del, end, pgdn
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, // F1~F12
        48,                              // tab (들여쓰기보다 오발동 방지 — 트리거 제외)
    ]
}

/// C 콜백. refcon 으로 KeyEventTap 을 복귀시킨다.
/// run loop source 를 CFRunLoopGetMain() 에 붙였으므로 메인 스레드 호출이 보장된다
/// → MainActor.assumeIsolated 안전. CGEvent(비 Sendable)는 MainActor 경계를 넘기지 않고
/// 여기서 Sendable 값(keyCode/flags)만 뽑아 전달한다.
private func keyEventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let passthrough = Unmanaged.passUnretained(event)
    guard let refcon else { return passthrough }
    let tap = Unmanaged<KeyEventTap>.fromOpaque(refcon).takeUnretainedValue()

    // a. 시스템이 tap 을 비활성화 → 재활성화 후 통과.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenableTap() }
        return passthrough
    }
    guard type == .keyDown else { return passthrough }

    // b. 자기 합성 이벤트 재처리 금지.
    if event.getIntegerValueField(.eventSourceUserData) == KeyEventTap.syntheticEventMagic {
        return passthrough
    }

    // c~g. 판정은 MainActor 로직으로.
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    let consume = MainActor.assumeIsolated {
        tap.shouldConsume(keyCode: keyCode, flags: flags)
    }
    return consume ? nil : passthrough
}
