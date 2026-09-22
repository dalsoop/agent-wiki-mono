import XCTest
@testable import SwiftSourceKit

final class SwiftSourceKitTests: XCTestCase {
    func testBlanksPreserveLineStructure() {
        let src = SwiftSource("""
        let a = 1  // 주석
        /* 블록
           주석 */
        let b = "문자열"
        """)
        XCTAssertEqual(src.code.components(separatedBy: "\n").count,
                       src.original.components(separatedBy: "\n").count)
        XCTAssertFalse(src.code.contains("주석"))
        XCTAssertFalse(src.code.contains("문자열"))
        XCTAssertTrue(src.code.contains("let a = 1"))
        XCTAssertTrue(src.code.contains("let b ="))
    }

    func testNestedBlockComments() {
        let src = SwiftSource("/* 바깥 /* 안쪽 */ 여전히주석 */ let x = 1")
        XCTAssertFalse(src.code.contains("여전히주석"))
        XCTAssertTrue(src.code.contains("let x = 1"))
    }

    func testEscapedQuoteInString() {
        let src = SwiftSource(#"let s = "따옴표 \" 안" ; let y = 2"#)
        XCTAssertFalse(src.code.contains("따옴표"))
        XCTAssertTrue(src.code.contains("let y = 2"))
    }

    func testOriginalLineIsReadable() {
        let src = SwiftSource("a\nb\nc")
        XCTAssertEqual(src.originalLine(2), "b")
    }

    func testCodeAndLiteralsKeepsStringSlashSlash() {
        let src = SwiftSource(#"let s = "// not comment""#)
        XCTAssertTrue(src.codeAndLiterals.contains("// not comment"))
        XCTAssertFalse(src.code.contains("not comment"))
    }

    func testUnparsedSkipsScan() {
        let text = "let x = 1 // keep as-is"
        let src = SwiftSource.unparsed(text)
        XCTAssertEqual(src.original, text)
        XCTAssertEqual(src.code, text)
        XCTAssertFalse(src.isCommentScanned)
    }

    func testLineCommentTailBlanked() {
        let src = SwiftSource("let x = 1 // tail")
        XCTAssertTrue(src.code.contains("let x = 1"))
        XCTAssertFalse(src.code.contains("tail"))
    }
}
