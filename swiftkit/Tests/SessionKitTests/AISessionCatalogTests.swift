import Foundation
import XCTest
@testable import SessionKit

final class AISessionCatalogTests: XCTestCase {
    func testModifiedAfterSkipsOldClaudeSessionsBeforeMetadataParsing() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeClaude(id: "old", modifiedAt: now.addingTimeInterval(-7_200))
        try fixture.writeClaude(id: "recent", modifiedAt: now)

        let records = fixture.catalog.discover(
            modifiedAfter: now.addingTimeInterval(-3_600),
            limitPerRuntime: 1
        )

        XCTAssertEqual(records.map(\.id), ["recent"])
    }

    func testGrokCutoffUsesTranscriptModificationDate() throws {
        let fixture = try CatalogFixture()
        defer { fixture.remove() }
        let now = Date()
        try fixture.writeGrok(
            id: "g1",
            summaryModifiedAt: now.addingTimeInterval(-7_200),
            transcriptModifiedAt: now
        )

        let records = fixture.catalog.discover(
            modifiedAfter: now.addingTimeInterval(-3_600),
            limitPerRuntime: 1
        )

        XCTAssertEqual(records.map(\.id), ["g1"])
        XCTAssertEqual(records.first?.runtime, .grok)
    }
}

private final class CatalogFixture {
    let root: URL
    let claude: URL
    let codex: URL
    let grok: URL
    let agy: URL

    var catalog: AISessionCatalog {
        AISessionCatalog(claudeRoot: claude, codexRoot: codex, grokRoot: grok, agyHome: agy)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("session-catalog-\(UUID().uuidString)", isDirectory: true)
        claude = root.appendingPathComponent("claude", isDirectory: true)
        codex = root.appendingPathComponent("codex", isDirectory: true)
        grok = root.appendingPathComponent("grok", isDirectory: true)
        agy = root.appendingPathComponent("agy", isDirectory: true)
        try FileManager.default.createDirectory(at: claude, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: grok, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: agy, withIntermediateDirectories: true)
    }

    func writeClaude(id: String, modifiedAt: Date) throws {
        let url = claude.appendingPathComponent("\(id).jsonl")
        try Data("{\"type\":\"user\",\"message\":{\"content\":\"\(id)\"}}\n".utf8)
            .write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
    }

    func writeGrok(id: String, summaryModifiedAt: Date, transcriptModifiedAt: Date) throws {
        let directory = grok.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let summary = directory.appendingPathComponent("summary.json")
        let transcript = directory.appendingPathComponent("updates.jsonl")
        try Data("{\"info\":{\"id\":\"\(id)\",\"cwd\":\"/tmp\"}}".utf8).write(to: summary)
        let chunkJSON = "{\"method\":\"session/update\",\"params\":{\"update\":"
            + "{\"sessionUpdate\":\"user_message_chunk\",\"content\":{\"text\":\"hello\"}}}}\n"
        try Data(chunkJSON.utf8).write(to: transcript)
        try FileManager.default.setAttributes([.modificationDate: summaryModifiedAt], ofItemAtPath: summary.path)
        try FileManager.default.setAttributes([.modificationDate: transcriptModifiedAt], ofItemAtPath: transcript.path)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
