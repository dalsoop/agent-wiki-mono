import XCTest
@testable import LocalizationKit

final class TranslationCoverageTests: XCTestCase {
    func testCompleteHasNoNotice() {
        XCTAssertTrue(TranslationCoverage.complete.isComplete)
        XCTAssertNil(TranslationCoverage.complete.notice(displayLanguage: .korean))
        XCTAssertNil(TranslationCoverage.complete.notice(displayLanguage: .english))
    }

    func testIncompleteKoreanNoticeIncludesCount() {
        let c = TranslationCoverage(hardcodedUICount: 12)
        let notice = c.notice(displayLanguage: .korean)
        XCTAssertEqual(c.isIncomplete, true)
        XCTAssertEqual(notice?.contains("12"), true)
        XCTAssertEqual(notice?.contains("번역"), true)
    }

    func testIncompleteEnglishNoticeIncludesCount() {
        let c = TranslationCoverage(hardcodedUICount: 3)
        let notice = c.notice(displayLanguage: .english)
        XCTAssertEqual(notice?.contains("3"), true)
        XCTAssertEqual(notice?.contains("wired"), true)
    }

    func testNegativeCountClampedToZero() {
        XCTAssertEqual(TranslationCoverage(hardcodedUICount: -5).hardcodedUICount, 0)
        XCTAssertTrue(TranslationCoverage(hardcodedUICount: -5).isComplete)
    }
}
