import XCTest
@testable import YamlKit

final class YamlKitTests: XCTestCase {
    // MARK: load — 스칼라 해석

    func testLoadNull() throws {
        let result = try YamlKit.load(yaml: "key: null")
        XCTAssertEqual((result as? [String: Any])?["key"] as? NSNull, NSNull())
    }

    func testLoadBool() throws {
        let result = try YamlKit.load(yaml: "key: true")
        XCTAssertEqual((result as? [String: Any])?["key"] as? Bool, true)
    }

    func testLoadInt() throws {
        let result = try YamlKit.load(yaml: "key: 42")
        XCTAssertEqual((result as? [String: Any])?["key"] as? Int, 42)
    }

    func testLoadNegativeInt() throws {
        let result = try YamlKit.load(yaml: "maxDepth: -1")
        XCTAssertEqual((result as? [String: Any])?["maxDepth"] as? Int, -1)
    }

    func testLoadDouble() throws {
        let result = try YamlKit.load(yaml: "key: 3.14")
        XCTAssertEqual((result as? [String: Any])?["key"] as? Double, 3.14)
    }

    func testLoadString() throws {
        let result = try YamlKit.load(yaml: "name: hello")
        XCTAssertEqual((result as? [String: Any])?["name"] as? String, "hello")
    }

    func testLoadQuotedStringStaysString() throws {
        let result = try YamlKit.load(yaml: "key: \"42\"")
        XCTAssertEqual((result as? [String: Any])?["key"] as? String, "42")
    }

    func testLoadQuotedBoolStaysString() throws {
        let result = try YamlKit.load(yaml: "key: \"true\"")
        XCTAssertEqual((result as? [String: Any])?["key"] as? String, "true")
    }

    // MARK: load — 구조

    func testLoadNestedMapping() throws {
        let yaml = """
        parent:
          child: value
          num: 7
        """
        let result = try YamlKit.load(yaml: yaml) as? [String: Any]
        let parent = result?["parent"] as? [String: Any]
        XCTAssertEqual(parent?["child"] as? String, "value")
        XCTAssertEqual(parent?["num"] as? Int, 7)
    }

    func testLoadBlockSequence() throws {
        let yaml = """
        aliases:
        - 자료
        - 노트
        """
        let result = try YamlKit.load(yaml: yaml) as? [String: Any]
        let aliases = result?["aliases"] as? [Any]
        XCTAssertEqual(aliases?.count, 2)
        XCTAssertEqual(aliases?[0] as? String, "자료")
        XCTAssertEqual(aliases?[1] as? String, "노트")
    }

    func testLoadSequenceOfMaps() throws {
        let yaml = """
        rules:
        - path: ~/Downloads
          action: move
        - path: ~/Desktop
          action: trash
        """
        let result = try YamlKit.load(yaml: yaml) as? [String: Any]
        let rules = result?["rules"] as? [Any]
        XCTAssertEqual(rules?.count, 2)
        let first = rules?[0] as? [String: Any]
        XCTAssertEqual(first?["path"] as? String, "~/Downloads")
        XCTAssertEqual(first?["action"] as? String, "move")
    }

    func testLoadFlowSequence() throws {
        let result = try YamlKit.load(yaml: "tags: [a, b, c]")
        let tags = (result as? [String: Any])?["tags"] as? [Any]
        XCTAssertEqual(tags as? [String], ["a", "b", "c"])
    }

    func testLoadFlowMapping() throws {
        let result = try YamlKit.load(yaml: "{a: 1, b: 2}")
        let dict = result as? [String: Any]
        XCTAssertEqual(dict?["a"] as? Int, 1)
        XCTAssertEqual(dict?["b"] as? Int, 2)
    }

    func testLoadCommentStripping() throws {
        let result = try YamlKit.load(yaml: "key: value  # 주석")
        XCTAssertEqual((result as? [String: Any])?["key"] as? String, "value")
    }

    func testLoadBlockScalarLiteral() throws {
        let yaml = """
        text: |
          line1
          line2
        """
        let result = try YamlKit.load(yaml: yaml) as? [String: Any]
        XCTAssertEqual(result?["text"] as? String, "line1\nline2\n")
    }

    // MARK: dump

    func testDumpSimpleMapping() throws {
        let dumped = try YamlKit.dump(object: ["name": "hello", "age": 42])
        let back = try YamlKit.load(yaml: dumped) as? [String: Any]
        XCTAssertEqual(back?["name"] as? String, "hello")
        XCTAssertEqual(back?["age"] as? Int, 42)
    }

    func testDumpRoundTripNested() throws {
        let original: [String: Any] = [
            "parent": ["child": "value", "num": 7] as [String: Any],
        ]
        let dumped = try YamlKit.dump(object: original)
        let back = try YamlKit.load(yaml: dumped) as? [String: Any]
        let parent = back?["parent"] as? [String: Any]
        XCTAssertEqual(parent?["child"] as? String, "value")
        XCTAssertEqual(parent?["num"] as? Int, 7)
    }

    func testDumpSequenceAtKeyIndent() throws {
        // Yams 형식 — 시퀀스 항목이 키와 같은 들여쓰기.
        let dumped = try YamlKit.dump(object: ["aliases": ["자료", "노트"]])
        XCTAssertTrue(dumped.contains("aliases:\n- 자료"))
        XCTAssertTrue(dumped.contains("- 노트"))
    }

    func testDumpSortKeys() throws {
        let dumped = try YamlKit.dump(object: ["b": 2, "a": 1], sortKeys: true)
        let aRange = dumped.range(of: "a:")
        let bRange = dumped.range(of: "b:")
        XCTAssertNotNil(aRange)
        XCTAssertNotNil(bRange)
        XCTAssertTrue(aRange!.lowerBound < bRange!.lowerBound)
    }

    func testDumpStringLikeNumberQuoted() throws {
        // 숫자처럼 보이는 문자열은 따옴표 처리.
        let dumped = try YamlKit.dump(object: ["v": "42"])
        XCTAssertTrue(dumped.contains("v: '42'"))
        let back = try YamlKit.load(yaml: dumped) as? [String: Any]
        XCTAssertEqual(back?["v"] as? String, "42")
    }

    func testDumpBoolStaysBool() throws {
        let dumped = try YamlKit.dump(object: ["trash": false, "remove": true])
        XCTAssertTrue(dumped.contains("trash: false"))
        XCTAssertTrue(dumped.contains("remove: true"))
    }

    // MARK: Codable

    struct Person: Codable, Equatable {
        let name: String
        let age: Int
        let active: Bool
    }

    func testEncoderBasic() throws {
        let person = Person(name: "홍길동", age: 30, active: true)
        let yaml = try YAMLEncoder().encode(person)
        XCTAssertTrue(yaml.contains("name: 홍길동"))
        XCTAssertTrue(yaml.contains("age: 30"))
        XCTAssertTrue(yaml.contains("active: true"))
    }

    func testDecoderBasic() throws {
        let yaml = """
        name: 홍길동
        age: 30
        active: true
        """
        let person = try YAMLDecoder().decode(Person.self, from: yaml)
        XCTAssertEqual(person.name, "홍길동")
        XCTAssertEqual(person.age, 30)
        XCTAssertEqual(person.active, true)
    }

    func testCodableRoundTrip() throws {
        let person = Person(name: "abc", age: 5, active: false)
        let yaml = try YAMLEncoder().encode(person)
        let back = try YAMLDecoder().decode(Person.self, from: yaml)
        XCTAssertEqual(person, back)
    }

    func testDecoderFromStringAndData() throws {
        let yaml = "name: x\nage: 1\nactive: true"
        let fromString = try YAMLDecoder().decode(Person.self, from: yaml)
        let fromData = try YAMLDecoder().decode(Person.self, from: yaml.data(using: .utf8)!)
        XCTAssertEqual(fromString, fromData)
    }

    struct WithOptionals: Codable, Equatable {
        let name: String
        let nick: String?
    }

    func testDecodeOptionalMissing() throws {
        let yaml = "name: x"
        let result = try YAMLDecoder().decode(WithOptionals.self, from: yaml)
        XCTAssertEqual(result.name, "x")
        XCTAssertNil(result.nick)
    }

    struct WithArray: Codable, Equatable {
        let items: [String]
    }

    func testDecodeArray() throws {
        let yaml = """
        items:
        - a
        - b
        """
        let result = try YAMLDecoder().decode(WithArray.self, from: yaml)
        XCTAssertEqual(result.items, ["a", "b"])
    }
}
