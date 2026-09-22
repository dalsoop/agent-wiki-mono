import XCTest
import AgentSessionKit
import StateRootKit
@testable import AgentContextKit

final class ClaudeProjectSlugTests: XCTestCase {
    /// bare 레포는 `/` 와 `.` 가 각각 대시가 되어 대시 둘이 겹친다 — 실측 경로로 고정한다.
    func testBareRepoSlugDoublesDash() {
        XCTAssertEqual(
            ClaudeProjectSlug.slug("/Users/jeonghan/Documents/WORK/WORKSPACE/apps/swift-app-mono/.bare"),
            "-Users-jeonghan-Documents-WORK-WORKSPACE-apps-swift-app-mono--bare"
        )
    }

    /// 비ASCII 는 **바이트가 아니라 글자마다** 대시 하나가 된다.
    /// 근거: 한글 5자 디렉터리가 `…-WORK------`(대시 6 = 구분자1 + 글자5)로 관측됐고,
    /// 그 하위는 `…-WORK-------godot-games`(대시 7)로 이어졌다. 바이트 기준이면 16이어야 한다.
    func testNonASCIIBecomesOneDashPerCharacter() {
        XCTAssertEqual(ClaudeProjectSlug.slug("/a/한글/b"), "-a----b")
    }

    /// cwd 슬러그에 memory 가 없으면 상위로 올라가 실재하는 것을 찾는다.
    /// Claude 가 memory 를 cwd 가 아니라 프로젝트 루트 기준으로 잡기 때문이다(실측).
    func testMemoryDirWalksUpToProjectRoot() throws {
        let home = try TempDir()
        let project = try TempDir()
        let dir = ClaudeProjectSlug.memoryDir(forCwd: project.path, home: home.path)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let resolved = ClaudeProjectSlug.resolveMemoryDir(forCwd: project.path + "/deep/nested", home: home.path)
        XCTAssertEqual(resolved, dir)
    }

    func testMemoryDirNilWhenNothingExists() throws {
        let home = try TempDir()
        XCTAssertNil(ClaudeProjectSlug.resolveMemoryDir(forCwd: "/tmp/nope-\(UUID().uuidString)", home: home.path))
    }
}

final class MarkdownImportsTests: XCTestCase {
    /// 코드펜스 안의 `@import` 는 예시지 주입이 아니다. 이걸 세면 "이렇게 쓴다"고 설명한
    /// 문서가 자기가 인용한 파일을 주입한 걸로 잡힌다.
    func testFencedImportsAreIgnored() {
        let text = """
        @real/one.md

        ```
        @fake/inside-fence.md
        ```

        @real/two.md
        """
        XCTAssertEqual(
            MarkdownImports.paths(in: text, relativeTo: "/base"),
            ["/base/real/one.md", "/base/real/two.md"]
        )
    }

    func testAbsoluteAndTildePaths() {
        let got = MarkdownImports.paths(in: "@/abs/x.md\n@~/home/y.md", relativeTo: "/base")
        XCTAssertEqual(got.first, "/abs/x.md")
        XCTAssertEqual(got.last, StateRootKit.path("home/y.md"))
    }

    func testNonMarkdownTokensIgnored() {
        XCTAssertTrue(MarkdownImports.paths(in: "@somebody said hi\n@config.json", relativeTo: "/b").isEmpty)
    }
}

final class TokenEstimateTests: XCTestCase {
    /// 바이트/4 를 안 쓰는 이유 — 한글은 UTF-8 3바이트라 그 공식이 크게 부풀린다.
    func testKoreanIsNotInflatedByByteLength() {
        let korean = String(repeating: "가", count: 300)
        XCTAssertLessThan(TokenEstimate.approxTokens(korean), korean.utf8.count / 4)
        XCTAssertEqual(TokenEstimate.approxTokens(korean), 200)
    }

    func testASCIIRoughlyFourCharsPerToken() {
        XCTAssertEqual(TokenEstimate.approxTokens(String(repeating: "a", count: 400)), 100)
    }
}

final class HeadGlanceGrokToolNamesTests: XCTestCase {
    func testGrokTerminalAndReadFileCountAsBashAndRead() {
        let g = HeadAnalysis.glance(
            tools: ["run_terminal_command": 10, "read_file": 4, "search_replace": 2],
            injected: [],
            injectedApproxTokens: 0,
            injectionObservable: false,
            touched: [],
            codeFocus: [],
            truncated: false
        )
        XCTAssertEqual(g.bashCalls, 10)
        XCTAssertEqual(g.readCalls, 4)
        XCTAssertEqual(g.editCalls, 2)
        XCTAssertEqual(g.mode, "bash-heavy")
    }
}

final class LedgerSearchHitsTests: XCTestCase {
    func testHitsFindStdoutUserAndAgent() {
        var d = SessionDigest(ref: SessionRef(
            tool: .grok, id: "s", cwd: "/w", title: nil,
            lastActive: Date(), path: "/p", messageCount: 3
        ))
        d.commandOutputs = [
            CommandOutput(
                command: "git remote -v",
                stdoutLine: "origin\tgit@gitlab-ssh.internal.kr:x.git (fetch)"
            )
        ]
        d.userMessages = ["주소가 gitlab.ranode.net 인데"]
        d.agentMessages = ["SSH HOLD 로 읽었다"]
        let hits = Ledger.hits(in: d, needle: "gitlab-ssh.internal.kr", sessionId: "s", tool: "grok")
        XCTAssertEqual(hits.map(\.matched), ["stdout"])
        let host = Ledger.hits(in: d, needle: "gitlab.ranode.net", sessionId: "s", tool: "grok")
        XCTAssertEqual(host.map(\.matched), ["user"])
        let hold = Ledger.hits(in: d, needle: "HOLD", sessionId: "s", tool: "grok")
        XCTAssertEqual(hold.map(\.matched), ["agent"])
    }
}

final class DocumentTraceTests: XCTestCase {
    /// 셸 명령에서 문서 토큰을 건지는 게 이 앱의 핵심 — 실측상 문서 접근의 대다수가
    /// Read 가 아니라 Bash 안에 있다.
    func testExtractsDocTokensFromShellCommand() {
        XCTAssertEqual(
            DocumentTrace.docTokens(in: "sed -n '1,40p' docs/plan.md | grep -i x README.md"),
            ["docs/plan.md", "README.md"]
        )
    }

    func testStripsQuotesAndPunctuation() {
        XCTAssertEqual(DocumentTrace.docTokens(in: #"cat "a/b.md", 'c.md';"#), ["a/b.md", "c.md"])
    }

    /// 글롭은 개별 문서로 환원할 수 없다 — 세면 존재하지 않는 문서를 세게 된다.
    func testGlobsAreSkipped() {
        XCTAssertTrue(DocumentTrace.docTokens(in: "cat docs/*.md").isEmpty)
    }

    func testCodeFilesAreNotDocuments() {
        XCTAssertTrue(DocumentTrace.docTokens(in: "vim main.swift package.json").isEmpty)
    }

    /// 실재하지 않는 경로는 떨어진다 — 문서에 예시로 적힌 경로가 명령에 섞여도 안 세도록.
    func testNormalizeRejectsMissingFiles() {
        XCTAssertNil(DocumentTrace.normalize("nope-\(UUID().uuidString).md", cwd: "/tmp"))
    }

    func testNormalizeResolvesRelativeToCwd() throws {
        let dir = try TempDir()
        let file = dir.path + "/note.md"
        try "x".write(toFile: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(DocumentTrace.normalize("note.md", cwd: dir.path), file)
    }
}

final class InjectionEvidenceTests: XCTestCase {
    func testBetweenExtractsBlock() {
        XCTAssertEqual(InjectionEvidence.between("a<X>body</X>b", "<X>", "</X>"), "body")
        XCTAssertNil(InjectionEvidence.between("a<X>body", "<X>", "</X>"))
    }

    /// 지문은 헤더·구분선이 아닌 **내용 줄**에서 뽑는다. 헤더는 여러 문서가 공유해서
    /// 엉뚱한 파일을 주입됐다고 판정하게 만든다.
    func testProbeSkipsHeadingsAndRules() {
        let text = """
        # 제목
        ---
        짧음
        이 줄은 대조 지문으로 쓰기에 충분히 길고 고유한 내용을 담고 있는 문장이다.
        """
        XCTAssertEqual(
            InjectionEvidence.probe(text),
            "이 줄은 대조 지문으로 쓰기에 충분히 길고 고유한 내용을 담고 있는 문장이다."
        )
    }

    func testProbeNilWhenNoLongLine() {
        XCTAssertNil(InjectionEvidence.probe("# h\n짧다\n또 짧다"))
    }

    /// 주입 블록이 없으면(= Claude·Grok) 후보를 그대로 둔다. 승격은 증거가 있을 때만.
    func testReconcileWithoutBlocksLeavesCandidatesUntouched() {
        let doc = InjectedDoc(path: "/x.md", layer: "global", provenance: .reconstructedCurrent,
                              bytes: 1, approxTokens: 1)
        XCTAssertEqual(InjectionEvidence.reconcile([doc], with: []), [doc])
    }

    func testReconcilePromotesWhenContentAppearsInBlock() throws {
        let dir = try TempDir()
        let path = dir.path + "/AGENTS.md"
        let body = "이 파일은 주입 대조 테스트를 위한 충분히 긴 고유 문장을 한 줄 담고 있다."
        try "# 제목\n\n\(body)\n".write(toFile: path, atomically: true, encoding: .utf8)

        let candidate = InjectedDoc(path: path, layer: "global", provenance: .reconstructedCurrent,
                                    bytes: nil, approxTokens: nil)
        let block = InjectionEvidence.Block(text: "앞부분\n\(body)\n뒷부분", approxTokens: 0, cwd: nil)

        XCTAssertEqual(InjectionEvidence.reconcile([candidate], with: [block]).first?.provenance, .injected)
    }

    /// 내용이 안 맞으면 승격하지 않는다 — 주입 안 됐거나 그 뒤 파일이 바뀐 것이고,
    /// 둘 중 뭔지 단정하지 않는 게 이 앱의 규율이다.
    func testReconcileLeavesDriftedFileUnpromoted() throws {
        let dir = try TempDir()
        let path = dir.path + "/AGENTS.md"
        try "# 제목\n\n지금 파일에만 있는 내용이며 주입 블록에는 없는 충분히 긴 문장이다.\n"
            .write(toFile: path, atomically: true, encoding: .utf8)

        let candidate = InjectedDoc(path: path, layer: "global", provenance: .reconstructedCurrent,
                                    bytes: nil, approxTokens: nil)
        let block = InjectionEvidence.Block(text: "전혀 다른 내용", approxTokens: 0, cwd: nil)

        XCTAssertEqual(InjectionEvidence.reconcile([candidate], with: [block]).first?.provenance,
                       .reconstructedCurrent)
    }
}

final class ContextResolverTests: XCTestCase {
    /// 얕은 규칙이 먼저, 깊은 규칙이 나중 — 세 런타임 공통 로드 순서.
    func testResolveOrdersGlobalThenAncestorThenCwd() throws {
        let home = try TempDir()
        let root = try TempDir()
        let deep = root.path + "/repo/sub"
        let fm = FileManager.default
        try fm.createDirectory(atPath: deep, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: home.path + "/.claude", withIntermediateDirectories: true)

        try "global".write(toFile: home.path + "/.claude/CLAUDE.md", atomically: true, encoding: .utf8)
        try "repo".write(toFile: root.path + "/repo/CLAUDE.md", atomically: true, encoding: .utf8)
        try "sub".write(toFile: deep + "/CLAUDE.md", atomically: true, encoding: .utf8)

        let got = ContextResolver(home: home.path).resolve(tool: .claude, cwd: deep)
        XCTAssertEqual(got.map(\.layer), ["global", "ancestor", "dir"])
    }

    /// Codex 는 AGENTS.md, Claude 는 CLAUDE.md — 런타임마다 찾는 파일이 다르다.
    func testCodexLooksForAgentsNotClaude() throws {
        let home = try TempDir()
        let root = try TempDir()
        try "claude-only".write(toFile: root.path + "/CLAUDE.md", atomically: true, encoding: .utf8)

        XCTAssertTrue(ContextResolver(home: home.path).resolve(tool: .codex, cwd: root.path).isEmpty)
        XCTAssertEqual(ContextResolver(home: home.path).resolve(tool: .claude, cwd: root.path).count, 1)
    }

    /// `@import` 는 트랜스클루전이라 주입 스택의 일부다.
    func testResolveExpandsImports() throws {
        let home = try TempDir()
        let root = try TempDir()
        try "@shared/rules.md\n".write(toFile: root.path + "/CLAUDE.md", atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(atPath: root.path + "/shared", withIntermediateDirectories: true)
        try "rules".write(toFile: root.path + "/shared/rules.md", atomically: true, encoding: .utf8)

        let got = ContextResolver(home: home.path).resolve(tool: .claude, cwd: root.path)
        XCTAssertEqual(got.map(\.layer), ["dir", "import"])
        XCTAssertEqual(got.last?.importedBy, (root.path + "/CLAUDE.md" as NSString).standardizingPath)
    }

    /// 주입본 관측 가능 여부는 런타임 사실이다 — Claude 는 로그에 안 남긴다(2026-08-04 실측).
    func testOnlyCodexInjectionIsObservable() {
        let r = ContextResolver(home: "/tmp")
        XCTAssertTrue(r.injectionObservable(.codex))
        XCTAssertFalse(r.injectionObservable(.claude))
        XCTAssertFalse(r.injectionObservable(.grok))
    }
}

final class SessionScanTests: XCTestCase {
    /// 슬래시 명령은 tool_use 가 아니라 사용자 메시지 안 `<command-name>` 으로 온다.
    func testCommandNameExtraction() {
        XCTAssertEqual(SessionScan.commandName(in: "<command-name>/loop</command-name>"), "loop")
        XCTAssertEqual(SessionScan.commandName(in: "x <command-name>caveman</command-name> y"), "caveman")
        XCTAssertNil(SessionScan.commandName(in: "no command here"))
    }
}

// MARK: - 테스트 도우미

/// 자동 정리되는 임시 디렉터리. 가짜 홈으로도 쓴다 — 실제 `~/.claude` 를 건드리지 않고
/// 탐색 규칙을 검증하기 위해서다.
final class TempDir {
    let path: String
    init() throws {
        path = ((NSTemporaryDirectory() + "asctl-test-" + UUID().uuidString) as NSString).standardizingPath
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(atPath: path) }
}

final class ActivationTraceTests: XCTestCase {
    /// 스킬 이름 → SKILL.md. 프로젝트 로컬이 홈보다 먼저다(실제 로딩 우선순위).
    func testSkillPathPrefersProjectLocal() throws {
        let home = try TempDir()
        let cwd = try TempDir()
        let fm = FileManager.default
        for base in [home.path + "/.claude/skills/foo", cwd.path + "/.claude/skills/foo"] {
            try fm.createDirectory(atPath: base, withIntermediateDirectories: true)
            try "x".write(toFile: base + "/SKILL.md", atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(
            ActivationTrace.skillPath("foo", cwd: cwd.path, home: home.path),
            cwd.path + "/.claude/skills/foo/SKILL.md"
        )
    }

    /// 플러그인 스킬은 `plugin:skill` 로 온다 — 뒤쪽 이름으로도 찾아야 한다.
    func testSkillPathHandlesPluginScopedName() throws {
        let home = try TempDir()
        let cwd = try TempDir()
        let dir = home.path + "/.claude/skills/cavecrew"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "x".write(toFile: dir + "/SKILL.md", atomically: true, encoding: .utf8)

        XCTAssertEqual(
            ActivationTrace.skillPath("caveman:cavecrew", cwd: cwd.path, home: home.path),
            dir + "/SKILL.md"
        )
    }

    func testAgentPathFindsDefinition() throws {
        let home = try TempDir()
        let cwd = try TempDir()
        let dir = cwd.path + "/.claude/agents"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "x".write(toFile: dir + "/reviewer.md", atomically: true, encoding: .utf8)

        XCTAssertEqual(ActivationTrace.agentPath("reviewer", cwd: cwd.path, home: home.path),
                       dir + "/reviewer.md")
        XCTAssertNil(ActivationTrace.agentPath("nope", cwd: cwd.path, home: home.path))
    }

    /// 알려진 내장 목록은 **힌트**다 — 판정은 verdict 가 파일 시스템을 보고 내린다.
    func testKnownBuiltinListIsAHint() {
        XCTAssertTrue(ActivationTrace.knownBuiltinAgents.contains("general-purpose"))
        XCTAssertFalse(ActivationTrace.knownBuiltinAgents.contains("readme-maker"))
    }

    /// 활성화 → InjectedDoc. 층은 skill/agent, provenance 는 read(관측).
    func testDocsFromActivations() throws {
        let home = try TempDir()
        let cwd = try TempDir()
        let dir = home.path + "/.claude/skills/foo"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "본문".write(toFile: dir + "/SKILL.md", atomically: true, encoding: .utf8)

        let acts = [Activation(kind: .skill, name: "foo", at: 1, thought: nil, mdPath: nil),
                    Activation(kind: .subagent, name: "general-purpose", at: 2, thought: nil, mdPath: nil)]
        let docs = ActivationTrace.docs(from: acts, cwd: cwd.path, home: home.path)

        XCTAssertEqual(docs.count, 1)          // 내장 에이전트는 md 가 없어 안 실린다
        XCTAssertEqual(docs.first?.layer, "skill")
        XCTAssertEqual(docs.first?.provenance, .read)
    }

    /// 같은 스킬을 여러 번 불러도 문서는 한 번만 실린다.
    func testDocsDeduplicate() throws {
        let home = try TempDir()
        let cwd = try TempDir()
        let dir = home.path + "/.claude/skills/foo"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try "x".write(toFile: dir + "/SKILL.md", atomically: true, encoding: .utf8)

        let acts = (1...5).map { Activation(kind: .skill, name: "foo", at: $0, thought: nil, mdPath: nil) }
        XCTAssertEqual(ActivationTrace.docs(from: acts, cwd: cwd.path, home: home.path).count, 1)
    }
}

final class SessionScanSummarizeTests: XCTestCase {
    /// 사고 블록이 있어도 본문이 없는 경우가 흔하다(Claude 는 서명만, Codex 는 암호화).
    /// 빈 문자열을 담으면 "사고가 없었다"와 "못 읽는다"가 구별되지 않는다.
    func testEmptyThoughtBecomesNil() {
        XCTAssertNil(SessionScan.summarize(""))
        XCTAssertNil(SessionScan.summarize("\n   \n"))
        XCTAssertEqual(SessionScan.summarize("첫 줄\n둘째 줄"), "첫 줄")
    }

    func testLongThoughtIsTruncated() {
        let long = String(repeating: "가", count: 300)
        let got = SessionScan.summarize(long, cap: 10)
        XCTAssertEqual(got?.count, 11)   // 10자 + 말줄임표
        XCTAssertTrue(got?.hasSuffix("…") == true)
    }

    /// Codex reasoning 은 summary/content 배열에 텍스트를 담는다(실제로는 대부분 암호화됨).
    func testCodexReasoningExtraction() {
        XCTAssertEqual(SessionScan.codexReasoning(["summary": [["text": "생각"]]]), "생각")
        XCTAssertNil(SessionScan.codexReasoning(["summary": [], "encrypted_content": "gAAA"]))
    }
}

final class LauncherTests: XCTestCase {
    /// help 텍스트에서 `--session-id` 를 **플래그 자리**로만 인정한다.
    ///
    /// 부분 문자열 검색이면 다른 플래그의 설명문이 그 이름을 언급하기만 해도 오판한다.
    /// 실제로 grok `--fork-session` 설명에 "(optionally set via `--session-id`)" 가 있다.
    func testSessionIDFlagDetectionIgnoresProseMentions() {
        XCTAssertTrue(Launcher.declaresSessionIDFlag(in: "  --session-id <uuid>  Use a specific session ID"))
        XCTAssertTrue(Launcher.declaresSessionIDFlag(in: "  -s, --session-id <SESSION_ID>"))
        XCTAssertFalse(Launcher.declaresSessionIDFlag(in: "  --fork-session  ... (optionally set via `--session-id`)"))
        XCTAssertFalse(Launcher.declaresSessionIDFlag(in: "no flags here"))
    }

    func testArgvInjectsSessionID() {
        XCTAssertEqual(Launcher.argv(tool: .claude, userArgs: ["안녕"], sessionId: "abc"),
                       ["claude", "--session-id", "abc", "안녕"])
    }

    /// 재개(`--resume`/`--continue`)에는 id 를 끼우지 않는다 — 기존 세션을 새 id 로 덮어쓰면
    /// 원장이 세션을 두 개로 쪼갠다.
    func testArgvSkipsSessionIDOnResume() {
        XCTAssertEqual(Launcher.argv(tool: .claude, userArgs: ["--resume", "x"], sessionId: "abc"),
                       ["claude", "--resume", "x"])
        XCTAssertEqual(Launcher.argv(tool: .claude, userArgs: ["--continue"], sessionId: "abc"),
                       ["claude", "--continue"])
    }

    func testArgvLeavesOtherToolsAlone() {
        XCTAssertEqual(Launcher.argv(tool: .codex, userArgs: ["--cd", "."], sessionId: nil),
                       ["codex", "--cd", "."])
    }

    func testWhichRejectsMissingProgram() {
        XCTAssertNil(Launcher.which("definitely-not-a-real-binary-\(UUID().uuidString)"))
        XCTAssertNotNil(Launcher.which("/bin/sh"))
    }
}

final class LaunchStoreTests: XCTestCase {
    /// 실행 시점 스냅샷 왕복 — 내용까지 저장돼야 나중에 "그때 그 내용"을 안다.
    func testRecordAndLoadRoundTrip() throws {
        let root = try TempDir()
        let docsDir = try TempDir()
        let path = docsDir.path + "/CLAUDE.md"
        try "지침 본문".write(toFile: path, atomically: true, encoding: .utf8)

        let store = LaunchStore(root: root.path, storeContent: true)
        let doc = InjectedDoc(path: path, layer: "global", provenance: .reconstructedCurrent,
                              bytes: nil, approxTokens: nil)
        let saved = try store.record(sessionId: "sess-1", tool: .claude, cwd: docsDir.path,
                                     argv: ["claude"], docs: [doc])

        XCTAssertEqual(saved.docs.count, 1)
        let loaded = try XCTUnwrap(store.load(sessionId: "sess-1"))
        XCTAssertEqual(loaded.docs.first?.path, path)
        XCTAssertEqual(store.blob(sha256: try XCTUnwrap(loaded.docs.first?.sha256)), "지침 본문")
    }

    /// 세션 id 앞자리만 쳐도 찾힌다(사람은 8자만 친다).
    func testLoadByIDPrefix() throws {
        let root = try TempDir()
        let store = LaunchStore(root: root.path, storeContent: true)
        try store.record(sessionId: "abcdef12-3456", tool: .claude, cwd: "/tmp", argv: [], docs: [])
        XCTAssertNotNil(store.load(sessionId: "abcdef12"))
        XCTAssertNil(store.load(sessionId: "zzzz"))
    }

    /// 같은 내용은 blob 하나로 dedupe — 같은 CLAUDE.md 로 100번 실행해도 한 번만 저장된다.
    func testBlobsAreContentAddressedAndDeduped() throws {
        let root = try TempDir()
        let docsDir = try TempDir()
        let path = docsDir.path + "/CLAUDE.md"
        try "같은 내용".write(toFile: path, atomically: true, encoding: .utf8)

        let store = LaunchStore(root: root.path, storeContent: true)
        let doc = InjectedDoc(path: path, layer: "global", provenance: .reconstructedCurrent,
                              bytes: nil, approxTokens: nil)
        for i in 1...3 {
            try store.record(sessionId: "s\(i)", tool: .claude, cwd: "/tmp", argv: [], docs: [doc])
        }
        let blobs = try FileManager.default.contentsOfDirectory(atPath: root.path + "/blobs")
        XCTAssertEqual(blobs.count, 1)
    }

    /// 기록을 카드용 스택으로 바꾸면 provenance 는 reconstructed-exact —
    /// 시점 내용까지 안다는 뜻이되, 로그 원문(injected)과는 여전히 구분한다.
    func testInjectedDocsUseExactProvenance() throws {
        let root = try TempDir()
        let store = LaunchStore(root: root.path)
        let launch = LaunchStore.Launch(
            sessionId: "s", tool: "claude", cwd: "/tmp", startedAt: Date(),
            docs: [.init(path: "/a.md", layer: "global", sha256: "h", bytes: 3,
                         approxTokens: 1, importedBy: nil)],
            argv: []
        )
        XCTAssertEqual(store.injectedDocs(launch).first?.provenance, .reconstructedExact)
    }
}

final class ProductHardeningTests: XCTestCase {
    /// 제품은 남의 맥에서도 돈다. 설치 안 된 런타임을 있는 것처럼 다루면
    /// "주입 지침 0건" 을 사실처럼 보고하게 된다.
    func testRuntimeDetectionByHomeDirectory() throws {
        let home = try TempDir()
        let fm = FileManager.default
        try fm.createDirectory(atPath: home.path + "/.claude", withIntermediateDirectories: true)

        let r = ContextResolver(home: home.path)
        XCTAssertTrue(r.isInstalled(.claude))
        XCTAssertFalse(r.isInstalled(.codex))
        XCTAssertEqual(r.installedTools(), [.claude])
    }

    /// 본문 보관은 **기본 꺼짐**. 지침 md 에는 회사 규정·자격증명이 들어 있을 수 있고,
    /// 관측 도구가 그걸 조용히 복제해 두면 안 된다.
    func testContentIsNotStoredByDefault() throws {
        let root = try TempDir()
        let docs = try TempDir()
        let path = docs.path + "/CLAUDE.md"
        try "비밀이 들어있을 수 있는 지침".write(toFile: path, atomically: true, encoding: .utf8)

        let store = LaunchStore(root: root.path, storeContent: false)
        let doc = InjectedDoc(path: path, layer: "global", provenance: .reconstructedCurrent,
                              bytes: nil, approxTokens: nil)
        let launch = try store.record(sessionId: "s", tool: .claude, cwd: "/tmp", argv: [], docs: [doc])

        XCTAssertFalse(launch.contentStored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path + "/blobs"))
        // 지문은 남는다 — "그때와 지금이 다른가"는 해시만으로 답해진다.
        XCTAssertEqual(launch.docs.first?.sha256.count, 64)
        XCTAssertGreaterThan(launch.docs.first?.bytes ?? 0, 0)
    }

    func testContentStoredWhenOptedIn() throws {
        let root = try TempDir()
        let docs = try TempDir()
        let path = docs.path + "/CLAUDE.md"
        try "본문".write(toFile: path, atomically: true, encoding: .utf8)

        let store = LaunchStore(root: root.path, storeContent: true)
        let doc = InjectedDoc(path: path, layer: "global", provenance: .reconstructedCurrent,
                              bytes: nil, approxTokens: nil)
        let launch = try store.record(sessionId: "s", tool: .claude, cwd: "/tmp", argv: [], docs: [doc])

        XCTAssertTrue(launch.contentStored)
        XCTAssertEqual(store.blob(sha256: try XCTUnwrap(launch.docs.first?.sha256)), "본문")
    }

    /// 정의 md 를 못 찾은 이유를 **파일 시스템에 물어서** 판정한다.
    /// 하드코딩 목록으로 판정하면 런타임 버전이 다른 맥에서 조용히 틀린다.
    func testMissingVerdictDistinguishesBuiltinFromDeleted() throws {
        let home = try TempDir()
        let cwd = try TempDir()
        let fm = FileManager.default

        // 에이전트 디렉터리 자체가 없다 → 전부 내장으로 본다.
        XCTAssertEqual(
            ActivationTrace.verdict(forMissing: "whatever", kind: .subagent, cwd: cwd.path, home: home.path),
            .noAgentDirectory
        )

        // 형제들은 있는데 이것만 없다 → 삭제·오타 의심.
        let agents = cwd.path + "/.claude/agents"
        try fm.createDirectory(atPath: agents, withIntermediateDirectories: true)
        try "x".write(toFile: agents + "/other.md", atomically: true, encoding: .utf8)
        XCTAssertEqual(
            ActivationTrace.verdict(forMissing: "missing", kind: .subagent, cwd: cwd.path, home: home.path),
            .likelyDeleted(siblings: 1)
        )

        // 알려진 내장은 형제가 있어도 정상.
        XCTAssertEqual(
            ActivationTrace.verdict(forMissing: "general-purpose", kind: .subagent, cwd: cwd.path, home: home.path),
            .knownBuiltin
        )
    }

    /// PATH 에 없는 프로그램은 프로브가 nil 을 준다 — 호출자가 기본값으로 물러난다.
    /// (설치된 런타임에 대고 단정하지 않는다: 이 맥에서 grok 은 실제로 `-s, --session-id`
    /// 를 지원했고, 하드코딩 가정이 틀렸음을 프로브가 잡아냈다.)
    func testProbeReturnsNilWhenBinaryMissing() {
        XCTAssertNil(Launcher.which("definitely-absent-\(UUID().uuidString)"))
    }

    /// 누적 질문에 답하려면 경과일이 필요하다.
    func testDaysSinceLastSeen() {
        let row = DocUsage(path: "/a.md", injectedSessions: 1, touchedSessions: 0, tools: [],
                           lastSeen: Date().addingTimeInterval(-10 * 86_400))
        XCTAssertEqual(row.daysSinceLastSeen(), 10)
        XCTAssertNil(DocUsage(path: "/b.md", injectedSessions: 0, touchedSessions: 0,
                              tools: [], lastSeen: nil).daysSinceLastSeen())
    }
}
