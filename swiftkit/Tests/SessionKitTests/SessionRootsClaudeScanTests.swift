import XCTest
@testable import SessionKit

/// Claude 최상위 세션은 `<root>/<slug>/<uuid>.jsonl` 두 단에 고정이다. 곁가지(`subagents/`)는
/// 요청할 때만 재귀로 걷는다 — 기본 목록에서 8,400 항목 walk 를 1,900 항목 listing 으로 줄인다.
final class SessionRootsClaudeScanTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-scan-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        let project = root.appendingPathComponent("-Users-j-proj", isDirectory: true)
        let sidechains = project.appendingPathComponent("aaaa/subagents", isDirectory: true)
        let memory = project.appendingPathComponent("memory", isDirectory: true)
        for dir in [sidechains, memory] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data(repeating: 0x7B, count: 4_096).write(to: project.appendingPathComponent("aaaa.jsonl"))
        try Data(repeating: 0x7B, count: 8).write(to: project.appendingPathComponent("empty.jsonl"))
        try Data(repeating: 0x7B, count: 4_096).write(to: sidechains.appendingPathComponent("agent-1.jsonl"))
        try Data("# notes".utf8).write(to: memory.appendingPathComponent("MEMORY.md"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func testTopLevelListingSkipsSidechains() {
        let files = SessionRoots.scanClaudeTopLevel(root: root, minSize: 0, since: nil)
        XCTAssertEqual(files.map(\.url.lastPathComponent).sorted(), ["aaaa.jsonl", "empty.jsonl"])
        XCTAssertTrue(files.allSatisfy { $0.runtime == .claude })
    }

    func testMinSizeDropsEmptyShells() {
        let files = SessionRoots.scanClaudeTopLevel(root: root, minSize: 1_024, since: nil)
        XCTAssertEqual(files.map(\.url.lastPathComponent), ["aaaa.jsonl"])
    }

    func testRecursiveWalkStillFindsSidechainsWhenAsked() {
        let files = SessionRoots.scan(root: root, runtime: .claude, minSize: 0, since: nil,
                                      includeClaudeSubagents: true)
        XCTAssertTrue(files.contains { $0.url.lastPathComponent == "agent-1.jsonl" })
    }
}
