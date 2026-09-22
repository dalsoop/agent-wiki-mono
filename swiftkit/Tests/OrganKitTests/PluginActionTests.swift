import XCTest
@testable import OrganKit

final class PluginActionTests: XCTestCase {
    func testPlainSubcommandIsAccepted() throws {
        for raw in ["get", "set", "list", "ship-queue", "read_page", "v2"] {
            let a = try PluginAction(validating: raw)
            XCTAssertEqual(a.token, raw)
            XCTAssertEqual(a.description, raw)
        }
    }

    func testDottedNameCannotBecomeAnAction() {
        XCTAssertThrowsError(try PluginAction(validating: "secret.get")) { err in
            XCTAssertEqual(err as? PluginAction.Invalid, .dotted("secret.get"))
        }
    }

    func testDottedRefusalNamesTheRealSubcommand() {
        let reason = PluginAction.Invalid.dotted("secret.get")
        XCTAssertTrue(reason.description.contains("'get'"),
                      "거절 사유가 대신 쓸 토큰을 말해야 한다: \(reason.description)")
    }

    func testEmptyWhitespaceAndFlagShapesAreRefused() {
        XCTAssertThrowsError(try PluginAction(validating: "")) {
            XCTAssertEqual($0 as? PluginAction.Invalid, .empty)
        }
        XCTAssertThrowsError(try PluginAction(validating: "two words")) {
            XCTAssertEqual($0 as? PluginAction.Invalid, .whitespace("two words"))
        }
        XCTAssertThrowsError(try PluginAction(validating: "--payload")) {
            XCTAssertEqual($0 as? PluginAction.Invalid, .looksLikeFlag("--payload"))
        }
        XCTAssertThrowsError(try PluginAction(validating: "get/all")) {
            XCTAssertEqual($0 as? PluginAction.Invalid, .unsupportedCharacter("get/all", "/"))
        }
    }

    /// 이 테스트가 이 타입의 존재 이유다. `ExpressibleByStringLiteral` 을 채택하는 순간
    /// `actions: ["secret.get"]` 이 다시 컴파일되고, 검사는 런타임으로 미뤄진다.
    func testStringLiteralConformanceIsDeliberatelyAbsent() {
        XCTAssertFalse(PluginAction.self is any ExpressibleByStringLiteral.Type,
                       "PluginAction 이 문자열 리터럴을 받으면 점 찍힌 이름이 컴파일을 통과한다")
    }

    func testDecodingRefusesDottedName() {
        let json = Data(#"["get","secret.get"]"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([PluginAction].self, from: json),
                             "JSON 카탈로그로 우회 입력되면 안 된다")
    }

    func testDecodingAcceptsPlainNamesAndRoundTrips() throws {
        let json = Data(#"["get","set"]"#.utf8)
        let actions = try JSONDecoder().decode([PluginAction].self, from: json)
        XCTAssertEqual(actions.map(\.token), ["get", "set"])
        let back = try JSONEncoder().encode(actions)
        XCTAssertEqual(String(decoding: back, as: UTF8.self), #"["get","set"]"#)
    }

    func testPartitionReportsWhyEachNameWasRejected() {
        let (ok, bad) = PluginAction.partition(["get", "secret.get", "", "--payload"])
        XCTAssertEqual(ok.map(\.token), ["get"])
        XCTAssertEqual(bad.map(\.raw), ["secret.get", "", "--payload"])
        XCTAssertEqual(bad.map(\.reason),
                       [.dotted("secret.get"), .empty, .looksLikeFlag("--payload")])
    }

    func testActionsAreUsableAsDictionaryKeys() throws {
        let get = try PluginAction(validating: "get")
        let same = try PluginAction(validating: "get")
        let set = try PluginAction(validating: "set")
        XCTAssertEqual(get, same)
        XCTAssertNotEqual(get, set)
        XCTAssertEqual(Set([get, same, set]).count, 2)
    }
}
