import XCTest
@testable import SessionKit

/// grok 세션 루트는 `<root>/<encoded-cwd>/<session-id>/updates.jsonl` 로 깊이가 고정이다.
/// 트리 전체를 걷지 않고 그 경로만 짚는지(곁가지 파일·더 깊은 잡동사니 무시)를 고정한다 —
/// 전체 walk 는 실측 11만 파일·12초였다(2026-09-03).
final class SessionRootsGrokScanTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-scan-\(UUID().uuidString)", isDirectory: true)
        let fm = FileManager.default
        let group = root.appendingPathComponent("%2FUsers%2Fj%2Fproj", isDirectory: true)
        let big = group.appendingPathComponent("session-big", isDirectory: true)
        let small = group.appendingPathComponent("session-small", isDirectory: true)
        let noLog = group.appendingPathComponent("session-nolog", isDirectory: true)
        let deep = big.appendingPathComponent("attachments", isDirectory: true)
        for dir in [big, small, noLog, deep] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data(repeating: 0x7B, count: 4_096).write(to: big.appendingPathComponent("updates.jsonl"))
        try Data(repeating: 0x7B, count: 16).write(to: small.appendingPathComponent("updates.jsonl"))
        // 세션 디렉터리의 곁가지 로그와 그룹 단위 파일은 세션이 아니다.
        try Data("x".utf8).write(to: big.appendingPathComponent("chat_history.jsonl"))
        try Data("x".utf8).write(to: group.appendingPathComponent("prompt_history.jsonl"))
        // 더 깊은 곳의 updates.jsonl 은 세션 로그가 아니다 — 2단 고정을 지킨다.
        try Data(repeating: 0x7B, count: 4_096).write(to: deep.appendingPathComponent("updates.jsonl"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func testFindsOnlySessionLevelUpdatesLog() {
        let files = SessionRoots.scanGrok(root: root, minSize: 0, since: nil)
        let names = files.map { $0.url.deletingLastPathComponent().lastPathComponent }.sorted()
        XCTAssertEqual(names, ["session-big", "session-small"])
        XCTAssertTrue(files.allSatisfy { $0.runtime == .grok && $0.url.lastPathComponent == "updates.jsonl" })
    }

    func testMinSizeFiltersEmptyShells() {
        let files = SessionRoots.scanGrok(root: root, minSize: 1_024, since: nil)
        XCTAssertEqual(files.map { $0.url.deletingLastPathComponent().lastPathComponent }, ["session-big"])
    }

    func testRuntimeScopedEnumerationSkipsOtherRoots() {
        // codex 만 요청하면 grok 루트는 아예 열지 않는다 — 결과에 grok 이 섞이면 걷은 것이다.
        let files = SessionRoots.enumerateJSONL(runtimes: [.codex])
        XCTAssertFalse(files.contains { $0.runtime == .grok })
        XCTAssertFalse(files.contains { $0.runtime == .claude })
    }
}
