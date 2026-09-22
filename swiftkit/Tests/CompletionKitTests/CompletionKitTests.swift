import CoreGraphics
import XCTest
@testable import CompletionKit

final class CompletionKitTests: XCTestCase {

    // MARK: - TextContext (prefix+suffix, FIM 지원)

    func testTextContextCarriesPrefixAndSuffix() {
        let ctx = TextContext(
            app: .init(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
            prefix: "let x = ", suffix: "\nprint(x)",
            geometry: .init(caretScreenRect: nil, fontPointSize: 13),
            document: .init(elementID: 42)
        )
        XCTAssertEqual(ctx.prefix, "let x = ")
        XCTAssertEqual(ctx.suffix, "\nprint(x)")   // 코드(code-ghost)용 캐럿 뒤 문맥
    }

    // MARK: - InsertIssue 코드

    func testInsertIssueCodes() {
        XCTAssertEqual(InsertIssue.failed.code, "E03")
        XCTAssertEqual(InsertIssue.appIgnored.code, "E05")
        XCTAssertTrue(InsertIssue.failed.isPermissionRelated)
        XCTAssertFalse(InsertIssue.appIgnored.isPermissionRelated)
    }

    // MARK: - TextInserter.backwardDeletionRange (순수)

    func testBackwardDeletionRangeClampsToCaret() {
        // 캐럿 앞 유닛이 충분하면 요청대로.
        let r = TextInserter.backwardDeletionRange(caretLocation: 10, utf16Count: 3)
        XCTAssertEqual(r?.location, 7); XCTAssertEqual(r?.length, 3)
        // 부족하면 있는 만큼만(캐럿 뒤 오선택 방지).
        let r2 = TextInserter.backwardDeletionRange(caretLocation: 2, utf16Count: 5)
        XCTAssertEqual(r2?.location, 0); XCTAssertEqual(r2?.length, 2)
        // 지울 게 없으면 nil.
        XCTAssertNil(TextInserter.backwardDeletionRange(caretLocation: 0, utf16Count: 3))
    }

    // MARK: - KeyBinding 매칭

    func testKeyBindingMatchesExactModifiers() {
        // ⌃` (grave + control)
        let binding = KeyBinding(keyCode: 50, modifiers: CGEventFlags.maskControl.rawValue)
        XCTAssertTrue(binding.matches(keyCode: 50, flags: .maskControl))
        XCTAssertFalse(binding.matches(keyCode: 50, flags: []))            // 수식 없음 → 불일치
        XCTAssertFalse(binding.matches(keyCode: 48, flags: .maskControl))  // 다른 키 → 불일치
    }

    // MARK: - 기본 바인딩

    @MainActor
    func testDefaultBindingsPresent() {
        let store = KeyBindingStore.shared
        // 기본 전체수락 = ` (grave), 줄수락 = ⇥ (tab), 단어수락 = ⌘→ (rightArrow+cmd)
        XCTAssertEqual(store.binding(for: .acceptFull).keyCode, AcceptKeyCode.grave.rawValue)
        XCTAssertEqual(store.binding(for: .acceptLine).keyCode, AcceptKeyCode.tab.rawValue)
        XCTAssertEqual(store.binding(for: .acceptWord).keyCode, AcceptKeyCode.rightArrow.rawValue)
        XCTAssertTrue(
            CGEventFlags(rawValue: store.binding(for: .acceptWord).modifiers).contains(.maskCommand))
    }
}
