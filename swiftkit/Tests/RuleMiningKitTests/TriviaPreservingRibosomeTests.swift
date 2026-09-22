//
//  TriviaPreservingRibosomeTests.swift
//  RuleMiningKitTests
//
//  무손실 LST 및 연쇄 소각(Cascading Apoptosis) 단위 테스트.
//

import XCTest
@testable import RuleMiningKit

final class TriviaPreservingRibosomeTests: XCTestCase {

    var ribosome: TriviaPreservingRibosome!

    override func setUp() {
        super.setUp()
        ribosome = TriviaPreservingRibosome()
    }

    override func tearDown() {
        ribosome = nil
        super.tearDown()
    }

    // MARK: - 1. 무손실 LST Round-trip 테스트 (Trivia 100% 보존)

    func testTriviaPreservingRoundtrip() {
        let originalSource = """
        // Top-level file header comment
        import Foundation
        import AppPersistenceKit

        /// User documentation comment
        public struct User: Sendable {
            /* multiline block
               comment inside struct */
            public let id: String
            public let name: String // trailing comment
        }

        func process() {
            // Nested indentation test
            let a = 1
            let b = 2
        }
        """

        let lst = SourceFileLST.parse(originalSource)
        let roundtrip = lst.description

        XCTAssertEqual(roundtrip, originalSource, "LST 파싱 후 재합성 시 원본 소스 코드의 공백과 주석이 단 1바이트도 유실되지 않아야 합니다.")
    }

    // MARK: - 2. Raw JSONDecoder / JSONEncoder ➔ AppPersistence 치환 테스트

    func testRawJsonDecoderToAppPersistenceWithTrivia() {
        let source = """
        import Foundation

        public struct UserService {
            // Fetch user profile securely
            public func loadUser(from data: Data) throws -> User {
                /* critical parsing step */
                return try JSONDecoder().decode(User.self, from: data) // trailing comment
            }

            public func loadUserOptional(from data: Data) -> User? {
                return try? JSONDecoder().decode(User.self, from: data)
            }
        }
        """

        let report = ribosome.transform(source: source)

        XCTAssertEqual(report.replacementCount, 2)
        XCTAssertTrue(report.isModified)
        XCTAssertTrue(report.importsAdded.contains("AppPersistenceKit"))

        let transformed = report.transformedSource

        // Trivia 보존 확인
        XCTAssertTrue(transformed.contains("// Fetch user profile securely"))
        XCTAssertTrue(transformed.contains("/* critical parsing step */"))
        XCTAssertTrue(transformed.contains("// trailing comment"))

        // API 치환 확인
        XCTAssertTrue(transformed.contains("try AppPersistence.decode(User.self, from: data)"))
        XCTAssertTrue(transformed.contains("try? AppPersistence.decode(User.self, from: data)"))
        XCTAssertFalse(transformed.contains("JSONDecoder().decode"))
        XCTAssertTrue(transformed.contains("import AppPersistenceKit"))
    }

    func testRawJsonEncoderToAppPersistence() {
        let source = """
        import Foundation

        public struct UserSerializer {
            public func serialize(_ user: User) throws -> Data {
                return try JSONEncoder().encode(user)
            }

            public func serializeOptional(_ user: User) -> Data? {
                return try? JSONEncoder().encode(user)
            }
        }
        """

        let report = ribosome.transform(source: source)

        XCTAssertEqual(report.replacementCount, 2)
        XCTAssertTrue(report.transformedSource.contains("try AppPersistence.encode(user)"))
        XCTAssertTrue(report.transformedSource.contains("try? AppPersistence.encode(user)"))
        XCTAssertFalse(report.transformedSource.contains("JSONEncoder().encode"))
    }

    // MARK: - 3. DateFormatter / ISO8601DateFormatter ➔ DateCodec 치환 테스트

    func testDateFormatterAndISO8601ToDateCodec() {
        let source = """
        import Foundation

        public struct LogService {
            public func logNow() -> String {
                return ISO8601DateFormatter().string(from: Date())
            }

            public func format(custom date: Date) -> String {
                return DateFormatter().string(from: date)
            }

            public func parse(text: String) -> Date? {
                return ISO8601DateFormatter().date(from: text)
            }
        }
        """

        let report = ribosome.transform(source: source)

        XCTAssertEqual(report.replacementCount, 3)
        XCTAssertTrue(report.importsAdded.contains("ISO8601DateCodecKit"))

        let transformed = report.transformedSource
        XCTAssertTrue(transformed.contains("return DateCodec.isoNow()"))
        XCTAssertTrue(transformed.contains("return DateCodec.formatISO8601(date)"))
        XCTAssertTrue(transformed.contains("return DateCodec.parseISO8601(text)"))
        XCTAssertFalse(transformed.contains("ISO8601DateFormatter()"))
        XCTAssertFalse(transformed.contains("DateFormatter()"))
    }

    // MARK: - 4. 연쇄 소각 (Cascading Apoptosis) - 미사용 변수 선언 제거 테스트

    func testCascadingApoptosisDeadVariableRemoval() {
        let source = """
        import Foundation

        public struct ConfigStore {
            public func loadConfig(from data: Data) throws -> Config {
                let decoder = JSONDecoder()
                return try decoder.decode(Config.self, from: data)
            }
        }
        """

        let report = ribosome.transform(source: source)

        XCTAssertEqual(report.replacementCount, 1)
        XCTAssertEqual(report.deadDeclarationsRemoved, ["decoder"])

        let transformed = report.transformedSource
        XCTAssertTrue(transformed.contains("return try AppPersistence.decode(Config.self, from: data)"))
        XCTAssertFalse(transformed.contains("let decoder = JSONDecoder()"))
        XCTAssertFalse(transformed.contains("decoder.decode"))
    }

    func testCascadingApoptosisMultipleDeadVariables() {
        let source = """
        import Foundation

        public struct SyncService {
            public func process(data: Data, item: Item) throws -> (Item, Data) {
                let decoder = JSONDecoder()
                let encoder = JSONEncoder()
                let decoded = try decoder.decode(Item.self, from: data)
                let encoded = try encoder.encode(item)
                return (decoded, encoded)
            }
        }
        """

        let report = ribosome.transform(source: source)

        XCTAssertEqual(report.replacementCount, 2)
        XCTAssertTrue(report.deadDeclarationsRemoved.contains("decoder"))
        XCTAssertTrue(report.deadDeclarationsRemoved.contains("encoder"))

        let transformed = report.transformedSource
        XCTAssertTrue(transformed.contains("try AppPersistence.decode(Item.self, from: data)"))
        XCTAssertTrue(transformed.contains("try AppPersistence.encode(item)"))
        XCTAssertFalse(transformed.contains("let decoder = JSONDecoder()"))
        XCTAssertFalse(transformed.contains("let encoder = JSONEncoder()"))
    }

    func testCascadingApoptosisPreservesVariablesWithRemainingReferences() {
        let source = """
        import Foundation

        public struct CustomDecoderStore {
            public func loadCustom(from data: Data) throws -> User {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(User.self, from: data)
            }
        }
        """

        let report = ribosome.transform(source: source)

        // decoder 변수가 다른 곳(dateDecodingStrategy)에서 여전히 참조되므로 선언이 소각되지 않아야 함
        XCTAssertFalse(report.deadDeclarationsRemoved.contains("decoder"))
        XCTAssertTrue(report.transformedSource.contains("let decoder = JSONDecoder()"))
    }

    // MARK: - 5. 연쇄 소각 (Cascading Apoptosis) - 미사용 Import 제거 테스트

    func testCascadingApoptosisUnusedImportsRemoval() {
        let source = """
        import Foundation
        import ObsoleteJsonKit

        public struct MessageStore {
            public func decodeMessage(from data: Data) throws -> Message {
                return try JSONDecoder().decode(Message.self, from: data)
            }
        }
        """

        let report = ribosome.transform(source: source)

        XCTAssertTrue(report.importsRemoved.contains("ObsoleteJsonKit"))
        XCTAssertTrue(report.importsAdded.contains("AppPersistenceKit"))

        let transformed = report.transformedSource
        XCTAssertFalse(transformed.contains("import ObsoleteJsonKit"))
        XCTAssertTrue(transformed.contains("import Foundation")) // Data 타입이 남아있으므로 Foundation 유지
        XCTAssertTrue(transformed.contains("import AppPersistenceKit"))
    }

    func testCascadingApoptosisFoundationRemovalWhenCompletelyUnused() {
        let source = """
        import Foundation
        import LegacyDateKit

        public struct ClockTicker {
            public func currentTimestamp() -> String {
                return ISO8601DateFormatter().string(from: Date())
            }
        }
        """

        let report = ribosome.transform(source: source)

        XCTAssertTrue(report.importsRemoved.contains("LegacyDateKit"))
        // 치환 후 DateCodec.isoNow() 로 바뀌어 Data, Date 등 Foundation 심볼이 0개 남으므로 Foundation 소각
        XCTAssertTrue(report.importsRemoved.contains("Foundation"))
        XCTAssertTrue(report.importsAdded.contains("ISO8601DateCodecKit"))

        let transformed = report.transformedSource
        XCTAssertFalse(transformed.contains("import Foundation"))
        XCTAssertFalse(transformed.contains("import LegacyDateKit"))
        XCTAssertTrue(transformed.contains("import ISO8601DateCodecKit"))
        XCTAssertTrue(transformed.contains("DateCodec.isoNow()"))
    }

    // MARK: - 6. RecipeAutoPrescriber 연동 테스트

    func testRecipeAutoPrescriberIntegration() {
        let prescriber = RecipeAutoPrescriber()
        let source = """
        import Foundation

        public struct SimpleItemStore {
            public func load(from data: Data) throws -> Item {
                let decoder = JSONDecoder()
                return try decoder.decode(Item.self, from: data)
            }
        }
        """

        let report = prescriber.applyRibosome(content: source)

        XCTAssertEqual(report.replacementCount, 1)
        XCTAssertEqual(report.deadDeclarationsRemoved, ["decoder"])
        XCTAssertTrue(report.transformedSource.contains("AppPersistence.decode(Item.self, from: data)"))
        XCTAssertTrue(report.transformedSource.contains("import AppPersistenceKit"))
    }
}
