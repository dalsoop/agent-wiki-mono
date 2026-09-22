import XCTest
@testable import LocalizationKit

/// 번들 API 를 거치지 않는 조회 축. Linux 평면 번들에서 CI 게이트가 키만 뱉던 회귀.
final class LocalizationCatalogTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("L10nCatalog-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    @discardableResult
    private func write(_ code: String, _ body: String, into root: URL? = nil) throws -> URL {
        let base = root ?? tmp!
        let lproj = base.appendingPathComponent("\(code).lproj", isDirectory: true)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        let url = lproj.appendingPathComponent("Localizable.strings")
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testReadsValueFromRequestedLanguage() throws {
        try write("en", "\"cli.ok\" = \"ok\";")
        try write("ko", "\"cli.ok\" = \"좋다\";")
        let catalog = LocalizationCatalog(root: tmp)
        XCTAssertEqual(catalog.string("cli.ok", preferred: ["ko"]), "좋다")
        XCTAssertEqual(catalog.string("cli.ok", preferred: ["en"]), "ok")
    }

    func testFallsBackToEnglishThenAnyLocalization() throws {
        try write("en", "\"cli.ok\" = \"ok\";")
        let catalog = LocalizationCatalog(root: tmp)
        // 없는 언어를 달라고 해도 조용히 빈손이 되면 안 된다 — 영어라도 사람 말이다.
        XCTAssertEqual(catalog.string("cli.ok", preferred: ["ja"]), "ok")
    }

    func testMissingKeyReturnsNil() throws {
        try write("en", "\"cli.ok\" = \"ok\";")
        // 누락은 키 노출로 드러나야 테스트가 잡는다 — 카탈로그가 빈 문자열을 지어내지 않는다.
        XCTAssertNil(LocalizationCatalog(root: tmp).string("cli.absent", preferred: ["en"]))
    }

    func testAvailableLocalizationsExcludesBase() throws {
        try write("en", "\"k\" = \"v\";")
        try write("ko", "\"k\" = \"v\";")
        try write("Base", "\"k\" = \"v\";")
        XCTAssertEqual(LocalizationCatalog(root: tmp).availableLocalizations(), ["en", "ko"])
    }

    func testSystemLocalizationMatchesRegionalVariant() throws {
        try write("en", "\"k\" = \"v\";")
        try write("ko", "\"k\" = \"v\";")
        let catalog = LocalizationCatalog(root: tmp)
        XCTAssertEqual(catalog.systemLocalization(preferences: ["ko-KR"]), "ko")
        XCTAssertEqual(catalog.systemLocalization(preferences: ["ja-JP", "en-US"]), "en")
        XCTAssertNil(LocalizationCatalog(root: tmp.appendingPathComponent("nope")).systemLocalization())
    }

    func testParsesEscapesAndComments() {
        let table = LocalizationCatalog.parse("""
        /* 주석 안의 문장 */
        "a" = "1\\n2";
        // 줄 주석
        "b" = "따옴표 \\"안\\"";
        """)
        XCTAssertEqual(table["a"], "1\n2")
        XCTAssertEqual(table["b"], "따옴표 \"안\"")
    }

    /// 플랫폼 plist 파서가 막혀도 같은 결과가 나와야 한다 — 이 타입의 존재 이유다.
    func testPairParserMatchesPlistParser() {
        let body = "\"a\" = \"1\";\n\"b\" = \"2\";\n"
        XCTAssertEqual(LocalizationCatalog.parsePairs(body), ["a": "1", "b": "2"])
        XCTAssertEqual(LocalizationCatalog.parsePairs(body), LocalizationCatalog.parse(body))
    }
}
