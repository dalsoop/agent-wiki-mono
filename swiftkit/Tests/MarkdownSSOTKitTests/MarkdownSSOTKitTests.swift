import XCTest
@testable import MarkdownSSOTKit

final class MarkdownSSOTKitTests: XCTestCase {
    var tempDirectory: URL?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarkdownSSOTKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirectory = dir
    }

    override func tearDown() {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    private func scratchDir() throws -> URL {
        try XCTUnwrap(tempDirectory)
    }

    // MARK: - AlignRuleProvider & DomainTermsSSOT Tests

    func testDomainTermsSSOTConformsToAlignRuleProvider() throws {
        let json = """
        {
          "version": "1.0.0",
          "description": "Test SSOT",
          "services": {
            "core": {
              "canonicalName": "Gujo Core",
              "devDomain": "gujo-dev.50.internal.kr",
              "localUrl": "https://gujo.test",
              "deprecated": ["core-dev.50.internal.kr", "gujo.test:8001"]
            },
            "apps": {
              "canonicalName": "Gujo Apps",
              "devDomain": "gujo-dev-apps.50.internal.kr",
              "localUrl": "https://apps.gujo.test",
              "deprecated": ["software-dev.50.internal.kr", "software.gujo.test:8012"],
              "replacements": {
                "software-dev.50.internal.kr": "gujo-dev-apps.50.internal.kr",
                "software.gujo.test:8012": "apps.gujo.test"
              }
            }
          }
        }
        """
        let data = Data(json.utf8)
        let ssot = try JSONDecoder().decode(DomainTermsSSOT.self, from: data)

        // Protocol conformance check
        let provider: any AlignRuleProvider = ssot
        XCTAssertTrue(provider.ledgerIdentifier.contains("DomainTermsSSOT"))
        XCTAssertTrue(provider.validate().isEmpty)

        let rules = provider.replacementRules()
        XCTAssertFalse(rules.isEmpty)
        // Descending order by length
        for i in 0..<(rules.count - 1) {
            XCTAssertGreaterThanOrEqual(rules[i].from.count, rules[i + 1].from.count)
        }
    }

    // MARK: - GenericTermsSSOT Tests

    func testGenericTermsSSOTPolymorphism() {
        let mapping: [String: String] = [
            "old-api": "new-api",
            "legacy-endpoint.com": "v2.endpoint.com",
            "http://insecure.test": "https://secure.test"
        ]
        let genericSSOT = GenericTermsSSOT(identifier: "TestGeneric", mapping: mapping)
        let provider: some AlignRuleProvider = genericSSOT

        XCTAssertEqual(provider.ledgerIdentifier, "TestGeneric")
        XCTAssertTrue(provider.validate().isEmpty)

        let rules = provider.replacementRules()
        XCTAssertEqual(rules.count, 3)
        // Check sorting: legacy-endpoint.com (19) > http://insecure.test (20) - sorted descending
        XCTAssertEqual(rules.first?.from, "http://insecure.test")

        // Validation failures
        let invalid = GenericTermsSSOT(identifier: "Bad", rules: [
            (from: "", to: "something"),
            (from: "same", to: "same")
        ])
        let issues = invalid.validate()
        XCTAssertEqual(issues.count, 2)
    }

    // MARK: - MarkdownFileCollector Tests

    func testDefaultMarkdownFileCollector() throws {
        let root = try scratchDir().appendingPathComponent("collector_repo")
        let gitDir = root.appendingPathComponent(".git")
        let buildDir = root.appendingPathComponent(".build")
        let docsDir = root.appendingPathComponent("docs")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docsDir, withIntermediateDirectories: true)

        try "git md".write(to: gitDir.appendingPathComponent("test.md"), atomically: true, encoding: .utf8)
        try "build md".write(to: buildDir.appendingPathComponent("test.md"), atomically: true, encoding: .utf8)
        try "valid doc 1".write(to: docsDir.appendingPathComponent("doc1.md"), atomically: true, encoding: .utf8)
        try "valid doc 2".write(to: docsDir.appendingPathComponent("doc2.MD"), atomically: true, encoding: .utf8)
        try "valid doc 3".write(to: docsDir.appendingPathComponent("doc3.md"), atomically: true, encoding: .utf8)
        try "not markdown".write(to: docsDir.appendingPathComponent("code.swift"), atomically: true, encoding: .utf8)

        let collector: some MarkdownFileCollector = DefaultMarkdownFileCollector()
        let allDocs = collector.collect(under: root, limit: nil)
        XCTAssertEqual(allDocs.count, 3)
        let filenames = Set(allDocs.map { $0.lastPathComponent.lowercased() })
        XCTAssertEqual(filenames, ["doc1.md", "doc2.md", "doc3.md"])

        // Test limit
        let limited = collector.collect(under: root, limit: 2)
        XCTAssertEqual(limited.count, 2)
    }

    // MARK: - MarkdownSearchEngine Tests

    func testMarkdownSearchEngine() throws {
        let root = try scratchDir().appendingPathComponent("search_dir")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file1 = root.appendingPathComponent("note1.md")
        let file2 = root.appendingPathComponent("note2.md")

        try """
        # System Guide
        Use old-auth-service for credentials.
        More details follow.
        """.write(to: file1, atomically: true, encoding: .utf8)

        try """
        Clean file without target.
        """.write(to: file2, atomically: true, encoding: .utf8)

        let engine: some MarkdownSearchEngine = DefaultMarkdownSearchEngine()
        let result = engine.search(
            query: "old-auth-service",
            isRegex: false,
            caseInsensitive: false,
            in: [file1, file2],
            relativeTo: root
        )

        XCTAssertEqual(result.totalMatches, 1)
        XCTAssertEqual(result.fileCount, 1)
        XCTAssertEqual(result.matches.first?.file, "note1.md")
        XCTAssertEqual(result.matches.first?.lineNumber, 2)
        XCTAssertTrue(result.matches.first?.lineContent.contains("old-auth-service") == true)
    }

    // MARK: - MarkdownAlignEngine Polymorphic Tests

    func testMarkdownAlignEngineWithGenericTermsSSOT() throws {
        let root = try scratchDir().appendingPathComponent("align_generic")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("architecture.md")

        let originalContent = """
        # Architecture
        Connect via http://legacy.domain.internal.
        Deprecated backend: old-gateway-svc.
        """
        try originalContent.write(to: file, atomically: true, encoding: .utf8)

        let genericProvider = GenericTermsSSOT(
            identifier: "LegacyMigration",
            mapping: [
                "http://legacy.domain.internal": "https://gateway.gujo.test",
                "old-gateway-svc": "modern-gateway-svc"
            ]
        )

        // 1. Dry run
        let dryRun = try MarkdownAlignEngine.scanAndAlign(
            files: [file],
            rules: genericProvider,
            relativeTo: root,
            apply: false
        )
        XCTAssertEqual(dryRun.totalFilesScanned, 1)
        XCTAssertEqual(dryRun.filesWithMismatches, 1)
        XCTAssertEqual(dryRun.totalMismatches, 2)
        XCTAssertFalse(dryRun.applied)

        // File unchanged
        let unchanged = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(unchanged, originalContent)

        // 2. Apply
        let applied = try MarkdownAlignEngine.scanAndAlign(
            files: [file],
            rules: genericProvider,
            relativeTo: root,
            apply: true
        )
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.totalMismatches, 2)

        let modified = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(modified.contains("https://gateway.gujo.test"))
        XCTAssertTrue(modified.contains("modern-gateway-svc"))
        XCTAssertFalse(modified.contains("http://legacy.domain.internal"))
        XCTAssertFalse(modified.contains("old-gateway-svc"))

        // 3. Under root with collector
        let collectorReport = try MarkdownAlignEngine.scanAndAlign(
            under: root,
            collector: DefaultMarkdownFileCollector(),
            rules: genericProvider,
            apply: false
        )
        XCTAssertEqual(collectorReport.filesWithMismatches, 0)
        XCTAssertEqual(collectorReport.totalMismatches, 0)
    }

    // MARK: - Custom Mock Provider Polymorphism Test

    struct DynamicCustomRuleProvider: AlignRuleProvider {
        let ledgerIdentifier: String = "DynamicMock"
        func replacementRules() -> [(from: String, to: String)] {
            [("alpha-version", "beta-version")]
        }
        func validate() -> [String] { [] }
    }

    func testCustomMockRuleProvider() throws {
        let root = try scratchDir().appendingPathComponent("custom_provider_test")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("doc.md")

        try "Running alpha-version in test".write(to: file, atomically: true, encoding: .utf8)

        let report = try MarkdownAlignEngine.scanAndAlign(
            files: [file],
            rules: DynamicCustomRuleProvider(),
            relativeTo: root,
            apply: true
        )
        XCTAssertEqual(report.totalMismatches, 1)
        let content = try String(contentsOf: file, encoding: .utf8)
        XCTAssertEqual(content, "Running beta-version in test")
    }
}
