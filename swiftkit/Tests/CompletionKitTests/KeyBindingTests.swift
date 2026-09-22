import XCTest
import CompletionKit
import CoreGraphics
@testable import CompletionKit

/// KeyBindingStore 순수 로직 테스트 — 전용 UserDefaults suite 사용, 시스템 이벤트 없음.
final class KeyBindingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "KeyBindingTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - 기본값 4종 (Cotypist 동일)

    @MainActor
    func testDefaultBindings() {
        let store = KeyBindingStore(defaults: defaults)
        XCTAssertEqual(store.binding(for: .acceptFull), KeyBinding(keyCode: 50, modifiers: 0))
        // acceptLine=⇥(48), acceptWord=⌘→(124+cmd) — CompletionKit 통합 기본값.
        XCTAssertEqual(store.binding(for: .acceptLine), KeyBinding(keyCode: 48, modifiers: 0))
        XCTAssertEqual(store.binding(for: .acceptWord),
                       KeyBinding(keyCode: 124, modifiers: CGEventFlags.maskCommand.rawValue))
        XCTAssertEqual(
            store.binding(for: .forceActivate),
            KeyBinding(keyCode: 50, modifiers: CGEventFlags.maskControl.rawValue)
        )
        XCTAssertEqual(
            store.binding(for: .globalToggle),
            KeyBinding(
                keyCode: 50,
                modifiers: CGEventFlags([.maskControl, .maskAlternate, .maskCommand]).rawValue
            )
        )
        // 기본 상태에서는 어떤 액션도 커스텀 아님
        for action in BindableAction.allCases {
            XCTAssertFalse(store.isCustomized(action))
        }
    }

    // MARK: - set → 재로드 왕복

    @MainActor
    func testSetBindingRoundTripsThroughDefaults() {
        let store = KeyBindingStore(defaults: defaults)
        let custom = KeyBinding(keyCode: 40, modifiers: CGEventFlags.maskCommand.rawValue) // ⌘K
        store.setBinding(custom, for: .acceptFull)
        XCTAssertTrue(store.isCustomized(.acceptFull))

        // 같은 suite 로 새 store 를 만들어도 저장된 값이 복원된다.
        let reloaded = KeyBindingStore(defaults: defaults)
        XCTAssertEqual(reloaded.binding(for: .acceptFull), custom)
        // 안 건드린 액션은 여전히 기본값.
        XCTAssertEqual(
            reloaded.binding(for: .acceptWord),
            KeyBindingStore.defaultBinding(for: .acceptWord)
        )
        XCTAssertFalse(reloaded.isCustomized(.acceptWord))
    }

    @MainActor
    func testSetBindingNormalizesModifiersBeforeSaving() {
        let store = KeyBindingStore(defaults: defaults)
        // caps/fn 비트가 섞여 들어와도 저장값은 ⌃ 만 남는다.
        var dirty: CGEventFlags = [.maskControl]
        dirty.insert(.maskAlphaShift)
        dirty.insert(.maskSecondaryFn)
        dirty.insert(.maskNonCoalesced)
        store.setBinding(KeyBinding(keyCode: 40, modifiers: dirty.rawValue), for: .acceptWord)
        XCTAssertEqual(
            store.binding(for: .acceptWord).modifiers,
            CGEventFlags.maskControl.rawValue
        )
    }

    // MARK: - reset

    @MainActor
    func testResetRestoresDefaultAndPersists() {
        let store = KeyBindingStore(defaults: defaults)
        store.setBinding(KeyBinding(keyCode: 40, modifiers: 0), for: .globalToggle)
        store.reset(.globalToggle)
        XCTAssertEqual(
            store.binding(for: .globalToggle),
            KeyBindingStore.defaultBinding(for: .globalToggle)
        )
        XCTAssertFalse(store.isCustomized(.globalToggle))
        // 재로드해도 기본값 유지.
        let reloaded = KeyBindingStore(defaults: defaults)
        XCTAssertEqual(
            reloaded.binding(for: .globalToggle),
            KeyBindingStore.defaultBinding(for: .globalToggle)
        )
    }

    // MARK: - matches 수식 정규화

    @MainActor
    func testMatchesIgnoresCapsFnPadFlags() {
        let store = KeyBindingStore(defaults: defaults)
        // 무수식 바인딩: caps/fn/패드만 켜져 있으면 일치.
        XCTAssertTrue(store.matches(
            .acceptFull, keyCode: 50,
            flags: [.maskAlphaShift, .maskSecondaryFn, .maskNumericPad]
        ))
        // 전역 토글: ⌃⌥⌘ + caps → 일치.
        var toggleFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        toggleFlags.insert(.maskAlphaShift)
        XCTAssertTrue(store.matches(.globalToggle, keyCode: 50, flags: toggleFlags))
        // 강제 발동: ⌃ + fn → 일치.
        XCTAssertTrue(store.matches(
            .forceActivate, keyCode: 50, flags: [.maskControl, .maskSecondaryFn]
        ))
    }

    @MainActor
    func testMatchesRequiresExactModifiersAndKeyCode() {
        let store = KeyBindingStore(defaults: defaults)
        // 관련 수식키가 더 눌리면 불일치.
        XCTAssertFalse(store.matches(.acceptFull, keyCode: 50, flags: [.maskShift]))
        // 부분집합도 불일치 (⌃⌥ 만으로는 전역 토글 아님).
        XCTAssertFalse(store.matches(
            .globalToggle, keyCode: 50, flags: [.maskControl, .maskAlternate]
        ))
        // 키코드 다르면 불일치.
        XCTAssertFalse(store.matches(.acceptWord, keyCode: 50, flags: []))
    }

    @MainActor
    func testMatchesCustomModifiedBinding() {
        let store = KeyBindingStore(defaults: defaults)
        // ⌥Space 같은 수식 포함 커스텀 바인딩도 matches 로 판정된다.
        store.setBinding(
            KeyBinding(keyCode: 49, modifiers: CGEventFlags.maskAlternate.rawValue),
            for: .acceptFull
        )
        XCTAssertTrue(store.matches(
            .acceptFull, keyCode: 49, flags: [.maskAlternate, .maskAlphaShift]
        ))
        XCTAssertFalse(store.matches(.acceptFull, keyCode: 49, flags: []))
    }

    // MARK: - 레코딩 중 tap 정지 (suspendedForRecording)

    @MainActor
    func testSuspendedForRecordingDefaultsToFalse() {
        let store = KeyBindingStore(defaults: defaults)
        XCTAssertFalse(store.suspendedForRecording)
    }

    @MainActor
    func testSuspendedForRecordingBypassesKeyEventTap() {
        // shouldConsume 은 KeyBindingStore.shared 를 보므로 shared 플래그로 검증하고 복원한다.
        let shared = KeyBindingStore.shared
        let saved = shared.suspendedForRecording
        defer { shared.suspendedForRecording = saved }

        let tap = KeyEventTap()   // start() 안 함 — 시스템 tap 미설치, 판정 로직만
        // forceActivate 는 handler 유무와 무관하게 무조건 소비된다(shouldConsume return true).
        // (globalToggle 은 handler 반환값에 따르므로 suspend 검증엔 forceActivate 가 적합.)
        let binding = shared.binding(for: .forceActivate)
        let flags = CGEventFlags(rawValue: binding.modifiers)
        shared.suspendedForRecording = false
        XCTAssertTrue(tap.shouldConsume(keyCode: binding.keyCode, flags: flags))
        // 레코딩 중에는 같은 키도 소비하지 않고 전부 통과.
        shared.suspendedForRecording = true
        XCTAssertFalse(tap.shouldConsume(keyCode: binding.keyCode, flags: flags))
    }

    // MARK: - 깨진 저장값 복구

    @MainActor
    func testBrokenJSONFallsBackToDefaults() {
        defaults.set(Data("not-json{{".utf8), forKey: KeyBindingStore.defaultsKey)
        let store = KeyBindingStore(defaults: defaults)
        for action in BindableAction.allCases {
            XCTAssertEqual(store.binding(for: action), KeyBindingStore.defaultBinding(for: action))
        }
    }

    @MainActor
    func testNonDataValueFallsBackToDefaults() {
        defaults.set("oops-not-data", forKey: KeyBindingStore.defaultsKey)
        let store = KeyBindingStore(defaults: defaults)
        for action in BindableAction.allCases {
            XCTAssertEqual(store.binding(for: action), KeyBindingStore.defaultBinding(for: action))
        }
    }

    @MainActor
    func testUnknownActionKeyIsIgnored() throws {
        // 미래 버전이 쓴 알 수 없는 액션 키는 무시하고 아는 것만 복원.
        let json = """
        {"acceptFull":{"keyCode":40,"modifiers":0},"bogusAction":{"keyCode":1,"modifiers":0}}
        """
        defaults.set(Data(json.utf8), forKey: KeyBindingStore.defaultsKey)
        let store = KeyBindingStore(defaults: defaults)
        XCTAssertEqual(store.binding(for: .acceptFull), KeyBinding(keyCode: 40, modifiers: 0))
        XCTAssertEqual(
            store.binding(for: .acceptWord),
            KeyBindingStore.defaultBinding(for: .acceptWord)
        )
    }
}
