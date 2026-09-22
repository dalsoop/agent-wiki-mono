import XCTest
import AgentSessionStorageKit
@testable import AgentSessionKit

/// 이 모듈은 **툴이 저장한 파일을 읽는 지식**을 모은 곳이다. 그 지식은 툴이 바뀔 때마다
/// 조용히 틀리게 되므로(실측: grok 세션은 디렉터리, codex 는 한 줄이 2MB, 이미지가
/// 사용자 지시와 같은 줄에 붙는다) 경계 조건을 여기서 지킨다.
final class AgentSessionKitTests: XCTestCase {
    /// grok 세션은 파일이 아니라 디렉터리다 — 경로 지식은 한 곳에만 둔다.
    func testTranscriptPathPerTool() {
        func ref(_ t: AgentTool) -> SessionRef {
            SessionRef(tool: t, id: "s", cwd: "/ws", title: nil,
                       lastActive: Date(), path: "/p/s", messageCount: 1)
        }
        XCTAssertEqual(ref(.grok).transcriptPath, "/p/s/updates.jsonl")
        XCTAssertEqual(ref(.claude).transcriptPath, "/p/s")
        XCTAssertEqual(ref(.codex).transcriptPath, "/p/s")
    }

    /// 거대한 줄을 통째로 버리면 그 안의 **사람 지시**까지 사라진다.
    func testBlobStrippingKeepsHumanTextBesideAnImage() throws {
        let blob = String(repeating: "A", count: 700_000)
        let line = #"{"payload":{"message":"이거 고쳐줘","images":["\#(blob)"]}}"#
        let out = JSONLine.strippingBlobs(Data(line.utf8))
        let o = try JSONSerialization.jsonObject(with: out) as? [String: Any]
        let p = o?["payload"] as? [String: Any]
        XCTAssertEqual(p?["message"] as? String, "이거 고쳐줘")
        XCTAssertEqual((p?["images"] as? [String])?.first, "")
    }

    /// 워크트리 하위는 같은 프로젝트로 친다. 루트(`/`)는 아니다.
    func testSameProject() {
        XCTAssertTrue(SessionIndex.isSameProject("/ws/p/.worktrees/x", "/ws/p"))
        XCTAssertFalse(SessionIndex.isSameProject("/ws/p", "/ws/q"))
        XCTAssertFalse(SessionIndex.isSameProject("/", "/ws/p"), "루트는 프로젝트가 아니다")
    }

    /// 창이 파일보다 크면 나눠 읽지 않는다 — 같은 줄을 두 번 세면 집계가 틀어진다.
    func testWindowPlan() {
        let w = DigestWindow.recent(head: 100, tail: 100)
        XCTAssertEqual(w.plan(fileSize: 150), .whole)
        XCTAssertEqual(w.plan(fileSize: 1_000), .headAndTail(headBytes: 100, tailOffset: 900))
        XCTAssertEqual(DigestWindow.full.plan(fileSize: 1_000_000), .whole)
    }

    /// 발언은 **읽은 순서 그대로** 모여야 한다(전사본이 여기 기댄다).
    func testReaderCollectsTurnsInOrder() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ask-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let f = dir.appendingPathComponent("s.jsonl")
        try ([#"{"type":"user","message":{"content":"하나"}}"#,
              #"{"type":"assistant","message":{"content":[{"type":"text","text":"둘"}]}}"#]
            .joined(separator: "\n")).write(to: f, atomically: true, encoding: .utf8)
        let ref = SessionRef(tool: .claude, id: "s", cwd: "/ws", title: nil,
                             lastActive: Date(), path: f.path, messageCount: 2)
        let turns = ClaudeSessionReader().digest(ref, window: .full).turns
        XCTAssertEqual(turns.map(\.text), ["하나", "둘"])
        XCTAssertEqual(turns.map(\.speaker), [.user, .agent])
    }

    func testCodexUnwrapsShellWrapper() {
        XCTAssertEqual(AgentSessionKit.CodexSessionReader.readableCommand(["/bin/zsh", "-lc", "git status"]), "git status")
        XCTAssertEqual(AgentSessionKit.CodexSessionReader.readableCommand(["ls", "-la"]), "ls -la")
    }

    func testCodexParsesPatchFileVerbs() {
        let patch = """
        *** Begin Patch
        *** Add File: a.swift
        *** Update File: b/c.swift
        *** Delete File: d.swift
        *** End Patch
        """
        XCTAssertEqual(AgentSessionKit.CodexSessionReader.patchedFiles(patch), ["a.swift", "b/c.swift", "d.swift"])
    }

    func testGrokToolResultKeepsCommandAndFirstStdoutLine() {
        var d = SessionDigest(ref: AgentSessionKit.SessionRef(
            tool: .grok, id: "s", cwd: "/w", title: nil,
            lastActive: Date(), path: "/p", messageCount: 1
        ))
        let u: [String: Any] = [
            "rawOutput": [
                "command": "git remote -v",
                "output_for_prompt": "origin\tgit@gitlab-ssh.internal.kr:x.git (fetch)\norigin push",
            ],
            "content": [[
                "type": "content",
                "content": ["type": "text", "text": "origin\tgit@gitlab-ssh.internal.kr:x.git (fetch)\nnext"],
            ]],
        ]
        AgentSessionKit.GrokSessionReader.absorbToolResult(u, into: &d)
        XCTAssertEqual(d.commands, ["git remote -v"])
        XCTAssertEqual(
            d.commandOutputs.first?.stdoutLine,
            "origin\tgit@gitlab-ssh.internal.kr:x.git (fetch)"
        )
    }

    func testGrokLastActivePrefersLogMtimeOverStaleSummary() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("grok-mtime-\(UUID().uuidString)")
        let sid = "01aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let dir = root.appendingPathComponent("%2Ftmp").appendingPathComponent(sid)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let log = dir.appendingPathComponent("updates.jsonl")
        try Data("{}\n".utf8).write(to: log)
        let stale = Date(timeIntervalSince1970: 1_000_000)
        let recent = Date(timeIntervalSince1970: 2_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: recent], ofItemAtPath: log.path)
        let summary = """
        {"session_summary":"old","updated_at":"\(ISO8601DateFormatter().string(from: stale))","num_chat_messages":1}
        """
        try Data(summary.utf8).write(to: dir.appendingPathComponent("summary.json"))
        let found = AgentSessionKit.GrokSessionReader(root: root.path).discover(limit: 10)
        XCTAssertEqual(found.count, 1)
        XCTAssertGreaterThan(found[0].lastActive, stale.addingTimeInterval(3600))
    }

    func testFastScanAndSinceFilter() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fast-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("transcript.jsonl")
        let lines = [
            #"{"type":"user","message":"hello"}"#,
            #"{"type":"assistant","tool_use":{"name":"read_file"}}"#,
            #"{"type":"assistant","thinking":{"text":"analyzing"}}"#,
            #"{"type":"assistant","random_blob":{"foo":"bar"}}"#
        ]
        try (lines.joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)

        var matchedCount = 0
        let tokens = [Data("tool_use".utf8), Data("thinking".utf8)]
        AgentSessionStorageKit.JSONLine.forEachLine(path: log.path, matchingTokens: tokens) { obj in
            matchedCount += 1
            return true
        }
        XCTAssertEqual(matchedCount, 2)
    }
}
