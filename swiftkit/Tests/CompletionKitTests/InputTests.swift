import XCTest
import CompletionKit
import CoreGraphics
@testable import CompletionKit

/// Input 모듈 순수 로직 테스트 — 시스템 이벤트 발송·tap 생성 없음.
final class InputTests: XCTestCase {

    // MARK: - AcceptKeyCode

    func testAcceptKeyCodeRawValues() {
        XCTAssertEqual(AcceptKeyCode.grave.rawValue, 50)
        XCTAssertEqual(AcceptKeyCode.tab.rawValue, 48)
        XCTAssertEqual(AcceptKeyCode.escape.rawValue, 53)
    }

    // MARK: - ModifierMatcher

    func testNormalizedKeepsOnlyFourModifiers() {
        var flags: CGEventFlags = [.maskCommand, .maskShift]
        flags.insert(.maskAlphaShift)   // caps lock
        flags.insert(.maskSecondaryFn)  // fn
        flags.insert(.maskNumericPad)   // 숫자패드/방향키
        flags.insert(.maskNonCoalesced)
        XCTAssertEqual(ModifierMatcher.normalized(flags), [.maskCommand, .maskShift])
    }

    func testMatchesIgnoresIrrelevantFlags() {
        let toggle: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        var pressed = toggle
        pressed.insert(.maskAlphaShift)
        pressed.insert(.maskSecondaryFn)
        pressed.insert(.maskNonCoalesced)
        XCTAssertTrue(ModifierMatcher.matches(pressed, exactly: toggle))
    }

    func testMatchesRequiresExactSet() {
        let toggle: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand]
        // 부분집합 → 불일치
        XCTAssertFalse(ModifierMatcher.matches([.maskControl, .maskAlternate], exactly: toggle))
        // 초과집합(⇧ 추가) → 불일치
        XCTAssertFalse(ModifierMatcher.matches(
            [.maskControl, .maskAlternate, .maskCommand, .maskShift], exactly: toggle
        ))
        // 정확 일치
        XCTAssertTrue(ModifierMatcher.matches(toggle, exactly: toggle))
    }

    func testIsUnmodified() {
        XCTAssertTrue(ModifierMatcher.isUnmodified([]))
        // caps/fn/패드만 켜져 있으면 무수정 취급
        XCTAssertTrue(ModifierMatcher.isUnmodified([.maskAlphaShift, .maskNumericPad, .maskSecondaryFn]))
        XCTAssertFalse(ModifierMatcher.isUnmodified([.maskShift]))
        XCTAssertFalse(ModifierMatcher.isUnmodified([.maskCommand]))
        XCTAssertFalse(ModifierMatcher.isUnmodified([.maskAlphaShift, .maskControl]))
    }

    // MARK: - TextInserter.backwardDeletionRange (length 클램프)

    func testBackwardDeletionRangeNormal() {
        let range = TextInserter.backwardDeletionRange(caretLocation: 10, utf16Count: 4)
        XCTAssertEqual(range?.location, 6)
        XCTAssertEqual(range?.length, 4)
    }

    func testBackwardDeletionRangeClampsLengthToCaret() {
        // 캐럿 앞 유닛(3)이 요청(10)보다 적으면 length 도 3 — 캐럿 뒤 텍스트가 절대 선택 안 되게
        let range = TextInserter.backwardDeletionRange(caretLocation: 3, utf16Count: 10)
        XCTAssertEqual(range?.location, 0)
        XCTAssertEqual(range?.length, 3)
    }

    func testBackwardDeletionRangeExactCaret() {
        let range = TextInserter.backwardDeletionRange(caretLocation: 5, utf16Count: 5)
        XCTAssertEqual(range?.location, 0)
        XCTAssertEqual(range?.length, 5)
    }

    func testBackwardDeletionRangeNilWhenNothingToDelete() {
        // 캐럿이 맨 앞(0)·비정상 음수·요청 0 → nil (지울 게 없음)
        XCTAssertNil(TextInserter.backwardDeletionRange(caretLocation: 0, utf16Count: 4))
        XCTAssertNil(TextInserter.backwardDeletionRange(caretLocation: -1, utf16Count: 4))
        XCTAssertNil(TextInserter.backwardDeletionRange(caretLocation: 7, utf16Count: 0))
    }

    // MARK: - TextChunker

    func testEmptyTextProducesNoChunks() {
        XCTAssertEqual(TextChunker.split(""), [])
    }

    func testAsciiSplitsAtTwentyUnits() {
        let text = String(repeating: "a", count: 45)
        let chunks = TextChunker.split(text)
        XCTAssertEqual(chunks.map { $0.utf16.count }, [20, 20, 5])
        XCTAssertEqual(chunks.joined(), text)
    }

    func testHangulSyllableIsOneUnit() {
        // 한글 음절은 BMP → 1유닛
        let text = String(repeating: "한", count: 25)
        let chunks = TextChunker.split(text)
        XCTAssertEqual(chunks.map { $0.utf16.count }, [20, 5])
        XCTAssertEqual(chunks.joined(), text)
    }

    func testSurrogatePairNeverSplitAtBoundary() {
        // 19 ASCII + 😀(2유닛): 20번째 자리에서 페어를 자르면 안 됨 → 첫 청크는 19유닛
        let text = String(repeating: "x", count: 19) + "😀" + "tail"
        let chunks = TextChunker.split(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 20 })
        XCTAssertEqual(chunks[0].utf16.count, 19)
        XCTAssertTrue(chunks.count >= 2 && chunks[1].hasPrefix("😀"))
        assertNoLoneSurrogates(chunks)
    }

    func testEmojiOnlyChunking() {
        // 😀 = 2유닛. 15개 = 30유닛 → 10개(20유닛) + 5개(10유닛)
        let text = String(repeating: "😀", count: 15)
        let chunks = TextChunker.split(text)
        XCTAssertEqual(chunks.map { $0.utf16.count }, [20, 10])
        XCTAssertEqual(chunks.joined(), text)
        assertNoLoneSurrogates(chunks)
    }

    func testMixedKoreanAndEmoji() {
        // 스킨톤·ZWJ 시퀀스 포함 — 그래핌은 쪼개질 수 있지만 서로게이트 페어는 보존
        let text = "안녕하세요 👋🏻 반갑습니다 🙇‍♂️ 잘 부탁드려요 😀😀😀"
        let chunks = TextChunker.split(text)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.utf16.count <= 20 })
        assertNoLoneSurrogates(chunks)
    }

    func testCustomMaxUnits() {
        XCTAssertEqual(TextChunker.split("abcdef", maxUTF16Units: 4), ["abcd", "ef"])
    }

    func testMaxUnitsClampedToHoldSurrogatePair() {
        // maxUnits 1 을 줘도 내부에서 2로 올려 페어(2유닛)가 살아남는다
        let chunks = TextChunker.split("😀😀", maxUTF16Units: 1)
        XCTAssertEqual(chunks, ["😀", "😀"])
        assertNoLoneSurrogates(chunks)
    }

    // MARK: - 헬퍼

    /// 각 청크의 UTF-16 열에 짝 잃은 서로게이트가 없는지 검사.
    private func assertNoLoneSurrogates(
        _ chunks: [String], file: StaticString = #filePath, line: UInt = #line
    ) {
        for chunk in chunks {
            let units = Array(chunk.utf16)
            var i = 0
            while i < units.count {
                let unit = units[i]
                if (0xD800...0xDBFF).contains(unit) {
                    // high surrogate 는 반드시 바로 뒤 low surrogate 와 짝이어야 한다
                    guard i + 1 < units.count, (0xDC00...0xDFFF).contains(units[i + 1]) else {
                        XCTFail("짝 잃은 high surrogate: \(chunk)", file: file, line: line)
                        return
                    }
                    i += 2
                    continue
                }
                if (0xDC00...0xDFFF).contains(unit) {
                    XCTFail("고아 low surrogate: \(chunk)", file: file, line: line)
                    return
                }
                i += 1
            }
        }
    }
}
