import XCTest
import Foundation
import os
@testable import FastLintCoreKit
import SwiftSourceKit

final class FastLintCoreKitTests: XCTestCase {

    private var tempDir: URL?

    override func setUp() {
        super.setUp()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("FastLintCoreKitTests-\(UUID().uuidString)")
        tempDir = dir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create temp directory: \(error)")
        }
    }

    override func tearDown() {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    // MARK: - FastSHA256 Tests

    func testFastSHA256() {
        let emptyHash = FastSHA256.hash(string: "")
        XCTAssertEqual(emptyHash, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

        let text = "Hello SwiftKit FastLint"
        let hash = FastSHA256.hash(string: text)
        XCTAssertFalse(hash.isEmpty)
        XCTAssertEqual(hash.count, 64)

        // Pure Swift fallback matches
        let pureHash = FastSHA256.pureSwiftSHA256(Data(text.utf8))
        XCTAssertEqual(hash, pureHash)
    }

    // MARK: - ContentHashCache 2-Stage Tests

    func testContentHashCacheTwoStageHitAndMiss() async throws {
        guard let dir = tempDir else {
            XCTFail("tempDir is nil")
            return
        }
        let fileURL = dir.appendingPathComponent("Sample.swift")
        let sourceContent = "import Foundation\n// Sample code\nlet x = 42\n"
        try sourceContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let diskDir = dir.appendingPathComponent("cache")
        let cache = ContentHashCache(diskCacheDirectory: diskDir)
        let rulesDigest = "ruleset-v1.6.14-sha256"

        // 1st lookup: Cold Miss
        let firstLookup = try await cache.lookup(filePath: fileURL.path, rulesDigest: rulesDigest)
        guard case .miss(let contentHash, _) = firstLookup else {
            XCTFail("Expected cache miss for new file")
            return
        }
        XCTAssertFalse(contentHash.isEmpty)

        // Record verification
        let finding = CachedFinding(
            ruleID: "sample-rule",
            line: 3,
            message: "Test finding",
            severity: "warn"
        )
        try await cache.store(
            filePath: fileURL.path,
            rulesDigest: rulesDigest,
            fileContentSHA256: contentHash,
            findings: [finding]
        )

        // 2nd lookup: Memory Hit
        let secondLookup = try await cache.lookup(filePath: fileURL.path, rulesDigest: rulesDigest)
        guard case .hit(let entry, _) = secondLookup else {
            XCTFail("Expected memory cache hit")
            return
        }
        XCTAssertEqual(entry.findings.count, 1)
        XCTAssertEqual(entry.findings.first?.ruleID, "sample-rule")

        // 3rd lookup from a fresh cache (Disk Hit)
        let diskCache = ContentHashCache(diskCacheDirectory: diskDir)
        let thirdLookup = try await diskCache.lookup(filePath: fileURL.path, rulesDigest: rulesDigest)
        guard case .hit(let diskEntry, _) = thirdLookup else {
            XCTFail("Expected disk cache hit from fresh cache instance")
            return
        }
        XCTAssertEqual(diskEntry.findings.count, 1)

        // 4th lookup with different rulesDigest: Miss (Invalidation)
        let differentDigest = "ruleset-v1.6.15-changed"
        let fourthLookup = try await diskCache.lookup(filePath: fileURL.path, rulesDigest: differentDigest)
        guard case .miss = fourthLookup else {
            XCTFail("Expected cache miss when ruleset digest changed")
            return
        }

        // 5th lookup when file content changed: Miss
        let modifiedContent = "import Foundation\nlet y = 100\n"
        try modifiedContent.write(to: fileURL, atomically: true, encoding: .utf8)

        let fifthLookup = try await cache.lookup(filePath: fileURL.path, rulesDigest: rulesDigest)
        guard case .miss = fifthLookup else {
            XCTFail("Expected cache miss for modified file content")
            return
        }
    }

    // MARK: - SinglePassTokenDispatcher Tests

    private final class TestSubscriber: SourceTokenSubscriber, Sendable {
        let interestedKinds: Set<SourceTokenKind> = Set(SourceTokenKind.allCases)

        private struct State: Sendable {
            var tokens: [DispatchedToken] = []
            var lines: [(Int, String)] = []
            var started = false
            var ended = false
        }
        private let state = OSAllocatedUnfairLock(initialState: State())

        var tokens: [DispatchedToken] { state.withLock { $0.tokens } }
        var lines: [(Int, String)] { state.withLock { $0.lines } }
        var started: Bool { state.withLock { $0.started } }
        var ended: Bool { state.withLock { $0.ended } }

        func onStart(source: SwiftSource) { state.withLock { $0.started = true } }
        func onEnd() { state.withLock { $0.ended = true } }
        func onToken(_ token: DispatchedToken) { state.withLock { $0.tokens.append(token) } }
        func onLine(lineNumber: Int, lineText: String) { state.withLock { $0.lines.append((lineNumber, lineText)) } }
    }

    func testSinglePassTokenDispatcher() {
        let code = """
        import Foundation
        import SwiftSourceKit

        // Line comment
        /* Block comment */
        public struct Foo {
            let message = "Hello"
        }
        """

        let subscriber = TestSubscriber()
        let dispatcher = SinglePassTokenDispatcher(subscribers: [subscriber])
        dispatcher.dispatch(text: code)

        XCTAssertTrue(subscriber.started)
        XCTAssertTrue(subscriber.ended)
        XCTAssertFalse(subscriber.lines.isEmpty)

        let imports = subscriber.tokens.filter { $0.kind == .importStatement }
        XCTAssertEqual(imports.count, 2)
        XCTAssertTrue(imports.contains { $0.text.contains("Foundation") })
        XCTAssertTrue(imports.contains { $0.text.contains("SwiftSourceKit") })

        let comments = subscriber.tokens.filter { $0.kind == .comment }
        XCTAssertEqual(comments.count, 2)

        let keywords = subscriber.tokens.filter { $0.kind == .keyword }
        XCTAssertTrue(keywords.contains { $0.text == "public" })
        XCTAssertTrue(keywords.contains { $0.text == "struct" })
        XCTAssertTrue(keywords.contains { $0.text == "let" })

        let strings = subscriber.tokens.filter { $0.kind == .stringLiteral }
        XCTAssertEqual(strings.count, 1)
        XCTAssertEqual(strings.first?.text, "\"Hello\"")
    }

    // MARK: - AhoCorasickMatcher Tests

    func testAhoCorasickMatcher() {
        let matcher = AhoCorasickMatcher(patterns: ["DateFormatter", "ISO8601DateFormatter", "sleep", "Task.sleep"])
        let text = "let f = DateFormatter()\nThread.sleep(forTimeInterval: 1)\nlet s = Task.sleep(nanoseconds: 100)"

        let matches = matcher.match(in: text)
        XCTAssertGreaterThanOrEqual(matches.count, 3)

        let matchedKeywords = Set(matches.map(\.pattern))
        XCTAssertTrue(matchedKeywords.contains("DateFormatter"))
        XCTAssertTrue(matchedKeywords.contains("sleep"))
        XCTAssertTrue(matchedKeywords.contains("Task.sleep"))
    }
}
