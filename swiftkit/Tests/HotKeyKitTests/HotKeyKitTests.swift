#if os(macOS)
import XCTest
import Carbon.HIToolbox
@testable import HotKeyKit

/// HotKeyKit 단위테스트.
///
/// 전역 키 후킹은 헤드리스 xctest 에서 신뢰할 수 없으므로, 여기서는 **결정적 로직**만 검증한다:
///  - KeyboardShortcuts 2.x 와 동일한 UserDefaults 저장 포맷(사용자 설정 보존의 핵심)
///  - Shortcut Codable round-trip + carbonKeyCode/carbonModifiers 필드명
///  - Name 기본값 채우기·RawRepresentable·disable sentinel
/// 실제 키 발화는 수동 확인 항목으로 둔다(README/PROGRESS 참조).
final class HotKeyKitTests: XCTestCase {

    // MARK: - Storage format (마이그레이션 호환성)

    /// KeyboardShortcuts 2.x 가 쓰던 키 접두사를 그대로 쓴다. 바뀌면 기존 사용자 설정이 전부 날아간다.
    func testStorageKeyUsesKeyboardShortcutsPrefix() throws {
        let name = HotKeyKit.Name("migrationProbe\(UUID().uuidString)")
        defer { UserDefaults.standard.removeObject(forKey: "KeyboardShortcuts_\(name.rawValue)") }

        // 내부 저장 키 형식: "KeyboardShortcuts_<rawValue>"
        let key = HotKeyKit.userDefaultsKey(for: name)
        XCTAssertTrue(key.hasPrefix("KeyboardShortcuts_"))
        XCTAssertEqual(key, "KeyboardShortcuts_\(name.rawValue)")
    }

    /// KeyboardShortcuts 2.x 가 직렬화하던 JSON 문자열을 HotKeyKit 이 그대로 읽는다.
    /// 이 테스트가 통과하면 앱을 옛 버전에서 쓰다가 HotKeyKit 으로 옮겨도 단축키가 살아있다.
    func testReadsLegacyKeyboardShortcutsJSON() throws {
        let rawValue = "legacyReadProbe"
        let key = "KeyboardShortcuts_\(rawValue)"

        // ⌘⇧S: carbonKeyCode(kVK_ANSI_S=1), carbonModifiers(cmdKey|shiftKey = 0x0100|0x0200 = 0x0300 = 768)
        let legacyJSON = #"{"carbonKeyCode":1,"carbonModifiers":768}"#
        UserDefaults.standard.set(legacyJSON, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let name = HotKeyKit.Name(rawValue: rawValue)
        let shortcut = HotKeyKit.getShortcut(for: name)

        let decoded = try XCTUnwrap(shortcut)
        XCTAssertEqual(decoded.carbonKeyCode, 1)
        XCTAssertEqual(decoded.carbonModifiers, cmdKey | shiftKey)
        XCTAssertEqual(decoded.modifiers, [.command, .shift])
    }

    /// 쓰기→읽기 round-trip 이 일관된 JSON 문자열을 만든다.
    func testShortcutRoundTripPersistsAsJSONString() throws {
        let rawValue = "roundTripProbe\(UUID().uuidString)"
        let key = "KeyboardShortcuts_\(rawValue)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let name = HotKeyKit.Name(rawValue: rawValue)
        let original = HotKeyKit.Shortcut(.v, modifiers: [.option, .command])
        HotKeyKit.setShortcut(original, for: name)

        // 값이 JSON 문자열로 저장됐는지(KeyboardShortcuts 2.x 와 동일 전송).
        let stored = try XCTUnwrap(UserDefaults.standard.string(forKey: key))
        let data = try XCTUnwrap(stored.data(using: .utf8))
        let decoded = try JSONDecoder().decode(HotKeyKit.Shortcut.self, from: data)
        XCTAssertEqual(decoded.carbonKeyCode, original.carbonKeyCode)
        XCTAssertEqual(decoded.carbonModifiers, original.carbonModifiers)

        // getShortcut 도 같은 값을 돌려준다.
        XCTAssertEqual(HotKeyKit.getShortcut(for: name), original)
    }

    /// Shortcut Codable 필드명은 carbonKeyCode / carbonModifiers 다(레거시 호환).
    func testShortcutCodableFieldNames() throws {
        let shortcut = HotKeyKit.Shortcut(carbonKeyCode: 42, carbonModifiers: 256)
        let data = try JSONEncoder().encode(shortcut)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["carbonKeyCode"] as? Int, 42)
        XCTAssertEqual(object?["carbonModifiers"] as? Int, 256)
    }

    // MARK: - Name semantics

    /// 기본 단축키가 있고 저장값이 없으면 첫 init 에 기본값을 채운다(첫 실행부터 동작).
    func testDefaultShortcutIsSeededOnFirstInit() {
        let rawValue = "defaultSeedProbe\(UUID().uuidString)"
        let key = "KeyboardShortcuts_\(rawValue)"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let name = HotKeyKit.Name(rawValue, default: .init(.s, modifiers: [.command, .shift]))
        XCTAssertEqual(HotKeyKit.getShortcut(for: name), .init(.s, modifiers: [.command, .shift]))
        XCTAssertEqual(name.defaultShortcut, .init(.s, modifiers: [.command, .shift]))
    }

    /// 이미 사용자가 설정한 값이 있으면 기본값으로 덮어쓰지 않는다.
    func testDefaultShortcutDoesNotOverrideExistingUserValue() {
        let rawValue = "noOverrideProbe\(UUID().uuidString)"
        let key = "KeyboardShortcuts_\(rawValue)"
        let userValue = HotKeyKit.Shortcut(.x, modifiers: [.control])
        UserDefaults.standard.set(
            try! JSONEncoder().encode(userValue).asString,
            forKey: key
        )
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let name = HotKeyKit.Name(rawValue, default: .init(.s, modifiers: [.command, .shift]))
        XCTAssertEqual(HotKeyKit.getShortcut(for: name), userValue)
    }

    /// reset 은 기본값이 있으면 기본값으로 되돌린다.
    func testResetRestoresDefaultShortcut() {
        let rawValue = "resetDefaultProbe\(UUID().uuidString)"
        let key = "KeyboardShortcuts_\(rawValue)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let name = HotKeyKit.Name(rawValue, default: .init(.r, modifiers: [.command, .shift]))
        // 사용자가 바꿈
        HotKeyKit.setShortcut(.init(.a, modifiers: [.command]), for: name)
        XCTAssertEqual(HotKeyKit.getShortcut(for: name), .init(.a, modifiers: [.command]))

        HotKeyKit.reset(name)
        XCTAssertEqual(HotKeyKit.getShortcut(for: name), .init(.r, modifiers: [.command, .shift]))
    }

    /// 기본값 없는 이름을 nil 로 set 하면 저장값이 완전히 지워진다.
    func testSetNilRemovesEntryWithoutDefault() {
        let rawValue = "nilRemoveProbe\(UUID().uuidString)"
        let key = "KeyboardShortcuts_\(rawValue)"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        let name = HotKeyKit.Name(rawValue) // default 없음
        HotKeyKit.setShortcut(.init(.a, modifiers: [.command]), for: name)
        XCTAssertNotNil(UserDefaults.standard.object(forKey: key))

        HotKeyKit.setShortcut(nil, for: name)
        XCTAssertNil(UserDefaults.standard.object(forKey: key))
    }

    /// Name 은 RawRepresentable 이다(rawValue 복원).
    func testNameIsRawRepresentable() {
        let name = HotKeyKit.Name(rawValue: "rawRepProbe")
        let reconstructed = HotKeyKit.Name(rawValue: name.rawValue)
        XCTAssertEqual(name, reconstructed)
    }

    // MARK: - Modifier / Shortcut construction

    /// Key → Shortcut → carbonKeyCode 가 Key.rawValue 와 일치한다.
    func testShortcutFromKeyPreservesKeyCode() {
        let shortcut = HotKeyKit.Shortcut(.space, modifiers: [.option])
        XCTAssertEqual(shortcut.carbonKeyCode, HotKeyKit.Key.space.rawValue)
        XCTAssertEqual(shortcut.modifiers, .option)
    }

    /// carbonModifiers 정규화 — 온전한 modifier 비트만 남는다.
    func testCarbonModifiersNormalizeToNSEventFlags() {
        let shortcut = HotKeyKit.Shortcut(carbonKeyCode: 0, carbonModifiers: cmdKey | shiftKey)
        XCTAssertEqual(shortcut.modifiers, [.command, .shift])
        XCTAssertEqual(shortcut.carbonModifiers, cmdKey | shiftKey)
    }

    /// Shortcut 은 Hashable(딕셔너리 키로 쓸 수 있다).
    func testShortcutIsHashable() {
        let dict: [HotKeyKit.Shortcut: String] = [
            .init(.a, modifiers: [.command]): "a",
            .init(.b, modifiers: [.command]): "b",
        ]
        XCTAssertEqual(dict[.init(.a, modifiers: [.command])], "a")
    }

    /// Key 의 function key 판정.
    func testKeyIsFunctionKey() {
        XCTAssertTrue(HotKeyKit.Key.f5.isFunctionKey)
        XCTAssertFalse(HotKeyKit.Key.a.isFunctionKey)
    }

    // MARK: - CarbonHotKeyCenter concurrency & thread-safety

    /// 멀티스레드 환경에서 register, updateEventHandler, unregister 가 OSAllocatedUnfairLock 으로
    /// 데이터 레이스 및 크래시 없이 직렬화되어 실행되는지 검증한다.
    func testCarbonHotKeyCenterConcurrentRegisterUnregister() {
        let center = CarbonHotKeyCenter.shared
        DispatchQueue.concurrentPerform(iterations: 100) { index in
            let shortcut = HotKeyKit.Shortcut(
                carbonKeyCode: index % 128,
                carbonModifiers: (index % 4) * 256
            )
            center.register(
                shortcut,
                onKeyDown: { _ in },
                onKeyUp: { _ in }
            )
            center.updateEventHandler()
            center.unregister(shortcut)
        }
    }
}
#endif
