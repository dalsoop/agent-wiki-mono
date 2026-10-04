import Foundation
import Testing
@testable import KnowledgeBaseWikiCore
import WikiLedgerKit

/// 세션 등록(`hook session`)과 모델 기록 우선순위. 경로는 모두 임시 디렉터리로 명시 주입한다 —
/// 기본 경로(상태 루트)를 쓰면 실제 홈에 써질 수 있다(옛 `AuthoringHook` 사고).
@Suite struct LawSessionRegistryTests {
    struct Fixture {
        let root: URL
        var registry: LawSessionRegistry { LawSessionRegistry(directory: root.appendingPathComponent("sessions")) }
        /// 테넌트 context 파일이 없는 홈.
        var emptyHome: String { root.appendingPathComponent("home").path }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    static func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("law-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return Fixture(root: root)
    }

    static let claudeStart = #"""
    {"session_id":"cc-1","transcript_path":"/Users/x/.claude/projects/p/cc-1.jsonl","cwd":"/work/repo",
     "hook_event_name":"SessionStart","source":"startup","model":"claude-opus-5-5"}
    """#
    static let claudeResume = #"""
    {"session_id":"cc-1","transcript_path":"/Users/x/.claude/projects/p/cc-1.jsonl","cwd":"/work/other",
     "hook_event_name":"SessionStart","source":"resume"}
    """#
    static let fixedNow = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func claudeCodeSampleFillsRegistration() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let environment = [
            "CLAUDE_CODE_SESSION_ID": "cc-1", "AI_AGENT": "claude-code_2-1-286_agent", "CLAUDE_EFFORT": "medium",
            "ROOM_TENANT": "tenant:gujo", "ANTHROPIC_API_KEY": "sk-secret",
        ]
        #expect(LawSessionHook.run(
            payload: Data(Self.claudeStart.utf8), registry: fx.registry, environment: environment, device: "macbook",
            tenantHomeDirectory: fx.emptyHome, now: Self.fixedNow))
        let saved = try #require(fx.registry.registration(sessionID: "cc-1"))
        #expect(saved == LawSessionRegistration(
            sessionID: "cc-1", runtime: "claude-code", runtimeVersion: "2.1.286", model: "claude-opus-5-5",
            effort: "medium", tenant: "gujo", device: "macbook", workingDirectory: "/work/repo",
            startedAt: "2026-09-21T14:13:20Z"))
        // 필요한 칸만 — 환경의 비밀 값이 파일에 없다.
        let raw = try String(contentsOf: fx.registry.fileURL(sessionID: "cc-1")!, encoding: .utf8)
        #expect(!raw.contains("sk-secret"))
        let keys = try #require(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any]).keys
        #expect(Set(keys) == [
            "session-id", "runtime", "runtime-version", "model", "effort", "tenant", "device", "cwd", "started-at",
        ])
    }

    @Test func resumeOverwritesOnlyKnownValues() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let start = ["CLAUDE_CODE_SESSION_ID": "cc-1", "CLAUDE_EFFORT": "high"]
        LawSessionHook.run(
            payload: Data(Self.claudeStart.utf8), registry: fx.registry, environment: start, device: "mac",
            tenantHomeDirectory: fx.emptyHome, now: Self.fixedNow)
        // 재개 훅: 모델·추론 강도를 모른다. 작업 디렉터리만 바뀌었다.
        LawSessionHook.run(
            payload: Data(Self.claudeResume.utf8), registry: fx.registry, environment: [:], device: nil,
            tenantHomeDirectory: fx.emptyHome, now: Self.fixedNow.addingTimeInterval(3600))
        let saved = try #require(fx.registry.registration(sessionID: "cc-1"))
        #expect(saved.model == "claude-opus-5-5")
        #expect(saved.effort == "high")
        #expect(saved.device == "mac")
        #expect(saved.runtime == "claude-code")
        #expect(saved.workingDirectory == "/work/other")
        #expect(saved.startedAt == "2026-09-21T14:13:20Z")
    }

    @Test func otherSessionFileUntouched() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let other = #"{"session_id":"cc-2","model":"claude-sonnet-5","cwd":"/a"}"#
        LawSessionHook.run(
            payload: Data(other.utf8), registry: fx.registry, environment: [:], device: "mac",
            tenantHomeDirectory: fx.emptyHome, now: Self.fixedNow)
        let otherURL = try #require(fx.registry.fileURL(sessionID: "cc-2"))
        let before = try Data(contentsOf: otherURL)
        LawSessionHook.run(
            payload: Data(Self.claudeStart.utf8), registry: fx.registry, environment: [:], device: "mac",
            tenantHomeDirectory: fx.emptyHome, now: Self.fixedNow)
        LawSessionHook.run(
            payload: Data(Self.claudeResume.utf8), registry: fx.registry, environment: [:], device: "mac",
            tenantHomeDirectory: fx.emptyHome, now: Self.fixedNow)
        #expect(try Data(contentsOf: otherURL) == before)
        let names = try FileManager.default.contentsOfDirectory(atPath: fx.registry.directory.path).sorted()
        #expect(names == ["cc-1.json", "cc-2.json"])
    }

    @Test func badEmptyInputAndWriteFailureDoNotThrow() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        for payload in ["", "not json", "[1,2]", #"{"session_id":"../../etc/passwd"}"#, #"{"session_id":"  "}"#] {
            #expect(!LawSessionHook.run(
                payload: Data(payload.utf8), registry: fx.registry, environment: [:], device: "mac",
                tenantHomeDirectory: fx.emptyHome))
        }
        #expect(!FileManager.default.fileExists(atPath: fx.registry.directory.path))
        // 쓰기 실패: 등록 디렉터리 자리에 일반 파일이 있다.
        let blocked = fx.root.appendingPathComponent("blocked")
        try Data("x".utf8).write(to: blocked)
        #expect(!LawSessionHook.run(
            payload: Data(Self.claudeStart.utf8), registry: LawSessionRegistry(directory: blocked),
            environment: [:], device: "mac", tenantHomeDirectory: fx.emptyHome))
    }

    @Test func sessionStartSourceIsNeverRuntime() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        for source in ["startup", "clear", "resume", "compact", "fork"] {
            let payload = #"{"session_id":"s-\#(source)","source":"\#(source)","runtime":"\#(source)"}"#
            let registration = try #require(LawSessionHook.registration(
                payload: Data(payload.utf8), explicit: LawModelRecord(runtime: source), environment: [:],
                device: nil, tenantHomeDirectory: fx.emptyHome))
            #expect(registration.runtime == nil)
        }
        // runtime 은 실행 도구에서 온다: 환경 → 대화 기록 경로.
        let codex = #"""
        {"session_id":"cx-1","transcript_path":"/Users/x/.codex/sessions/2026/10/04/rollout.jsonl","cwd":"/w",
         "hook_event_name":"SessionStart","model":"gpt-5.5-codex","permission_mode":"default","source":"fork"}
        """#
        let fromPath = try #require(LawSessionHook.registration(
            payload: Data(codex.utf8), environment: [:], device: nil, tenantHomeDirectory: fx.emptyHome))
        #expect(fromPath.runtime == "codex")
        #expect(fromPath.model == "gpt-5.5-codex")
        let fromEnvironment = try #require(LawSessionHook.registration(
            payload: Data(#"{"source":"startup"}"#.utf8), environment: ["CODEX_THREAD_ID": "cx-2"], device: nil,
            tenantHomeDirectory: fx.emptyHome))
        #expect(fromEnvironment.sessionID == "cx-2")
        #expect(fromEnvironment.runtime == "codex")
    }

    @Test func tenantSlug() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        func tenant(_ environment: [String: String], home: String) -> String? {
            LawSessionHook.registration(
                payload: Data(#"{"session_id":"t"}"#.utf8), environment: environment, device: nil,
                tenantHomeDirectory: home)?.tenant
        }
        #expect(tenant(["ROOM_TENANT": "tenant:wife", "TENANT_ID": "tenant:gujo"], home: fx.emptyHome) == "wife")
        #expect(tenant(["AGENT_TENANT": "gujo"], home: fx.emptyHome) == "gujo")
        #expect(tenant([:], home: fx.emptyHome) == nil)
        let home = fx.root.appendingPathComponent("tenant-home")
        let contextDirectory = home.appendingPathComponent(".agent-tenant-isolation-manager")
        try FileManager.default.createDirectory(at: contextDirectory, withIntermediateDirectories: true)
        try Data(#"{"tenantID":"tenant:company"}"#.utf8)
            .write(to: contextDirectory.appendingPathComponent("current-context.json"))
        #expect(tenant([:], home: home.path) == "company")
    }

    // MARK: - 공포 쪽: 우선순위와 세션 찾기

    @Test func precedenceFourStages() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        fx.registry.register(LawSessionRegistration(
            sessionID: "cc-1", runtime: "claude-code", runtimeVersion: "1.0.0", model: "from-session",
            effort: "low"))
        let session = ["CLAUDE_CODE_SESSION_ID": "cc-1"]
        let onlySession = LawModelRecordSource.collect(explicit: LawModelRecord(), environment: session, sessions: fx.registry)
        #expect(onlySession == LawModelRecord(
            runtime: "claude-code", runtimeVersion: "1.0.0", model: "from-session", effort: "low"))
        // 실행 도구 환경 변수 > 세션 등록.
        var tool = session
        tool["CLAUDE_EFFORT"] = "high"
        tool["AI_AGENT"] = "claude-code_2-1-286_agent"
        let fromTool = LawModelRecordSource.collect(explicit: LawModelRecord(), environment: tool, sessions: fx.registry)
        #expect(fromTool.effort == "high")
        #expect(fromTool.runtimeVersion == "2.1.286")
        #expect(fromTool.model == "from-session")
        // 위키 전용 환경 변수 > 실행 도구 환경 변수.
        var wiki = tool
        wiki[LawModelRecordSource.effortKey] = "xhigh"
        wiki[LawModelRecordSource.modelKey] = "from-wiki"
        let fromWiki = LawModelRecordSource.collect(explicit: LawModelRecord(), environment: wiki, sessions: fx.registry)
        #expect(fromWiki.effort == "xhigh")
        #expect(fromWiki.model == "from-wiki")
        #expect(fromWiki.runtimeVersion == "2.1.286")
        // 명시 인자 > 위키 전용 환경 변수.
        let fromExplicit = LawModelRecordSource.collect(
            explicit: LawModelRecord(model: "from-flag", effort: "max"), environment: wiki, sessions: fx.registry)
        #expect(fromExplicit == LawModelRecord(
            runtime: "claude-code", runtimeVersion: "2.1.286", model: "from-flag", effort: "max"))
    }

    @Test func findsOwnSessionByEnvironmentID() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        fx.registry.register(LawSessionRegistration(sessionID: "a", runtime: "claude-code", model: "model-a"))
        fx.registry.register(LawSessionRegistration(sessionID: "b", runtime: "codex", model: "model-b"))
        let actor = try LawActorResolution.actor(
            author: "agent:codex@mac", environment: ["CODEX_THREAD_ID": "b"], device: "mac", sessions: fx.registry)
        #expect(actor.model == "model-b")
        #expect(actor.runtime == "codex")
        #expect(fx.registry.registration(environment: ["CLAUDE_CODE_SESSION_ID": "a"])?.model == "model-a")
    }

    @Test func agentWithoutSessionOrValuesIsRefused() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        // 다른 세션 등록이 있어도 추정하지 않는다.
        fx.registry.register(LawSessionRegistration(sessionID: "a", runtime: "claude-code", model: "model-a"))
        #expect(throws: LawActorError.sessionUnknown) {
            try LawActorResolution.actor(author: "agent:c@mac", environment: [:], device: "mac", sessions: fx.registry)
        }
        #expect(throws: LawActorError.sessionNotRegistered("zzz")) {
            try LawActorResolution.actor(
                author: "agent:c@mac", environment: ["CLAUDE_CODE_SESSION_ID": "zzz"], device: "mac",
                sessions: fx.registry)
        }
        // 명시 값이 있으면 세션 없이도 진행한다.
        let explicit = try LawActorResolution.actor(
            author: "agent:c@mac", explicit: LawModelRecord(runtime: "codex", model: "m"), environment: [:],
            device: "mac", sessions: fx.registry)
        #expect(explicit.model == "m")
        // 사람·앱 공포는 세션을 보지 않는다.
        let app = try LawActorResolution.actor(
            author: "app:agent-wiki", environment: ["CLAUDE_CODE_SESSION_ID": "a"], device: "mac", sessions: fx.registry)
        #expect(app.model == nil)
        #expect(app.runtime == LawRuntime.app.rawValue)
    }
}
