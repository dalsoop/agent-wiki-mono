import Foundation
import Testing
@testable import RoomKit

@Suite("RoomWalls 경로 정규화 및 프리셋")
struct RoomWallsTests {
    @Test("RoomWalls.resolved(workdir:) — 상대경로는 workdir 기준, 절대경로는 그대로 유지")
    func testResolvedPaths() {
        let walls = RoomWalls(
            filesystem: FilesystemWall(
                denyRead: ["secret/**", "/absolute/deny"],
                allowRead: ["docs/**"],
                allowWrite: ["src/**", "/abs/write"],
                denyWrite: [".git/hooks"]
            ),
            network: .closed,
            unixSockets: [],
            executables: .allowList(["swift"]),
            shell: .restricted
        )

        let resolved = walls.resolved(workdir: "/repo/my-app")
        #expect(resolved.filesystem.denyRead == ["/repo/my-app/secret", "/absolute/deny"])
        #expect(resolved.filesystem.allowRead == ["/repo/my-app/docs"])
        #expect(resolved.filesystem.allowWrite == ["/repo/my-app/src", "/abs/write"])
        #expect(resolved.filesystem.denyWrite == ["/repo/my-app/.git/hooks"])

        // workdir 가 nil 일 때는 상대경로 그대로 유지
        let unresolved = walls.resolved(workdir: nil)
        #expect(unresolved.filesystem.allowWrite == ["src/**", "/abs/write"])
    }

    @Test("RoomWallPreset -> RoomWalls 변환 — open 은 hostPath + normal shell")
    func testPresetConversion() {
        let readOnly = RoomWalls.preset(.readOnly, toolbelt: ["swift"])
        #expect(readOnly.shell == .restricted)
        #expect(readOnly.executables == .allowList(["swift"]))
        #expect(readOnly.isReadOnly)

        let toolbelt = RoomWalls.preset(.toolbelt, toolbelt: ["swift", "git"])
        #expect(toolbelt.shell == .restricted)
        #expect(toolbelt.executables == .allowList(["swift", "git"]))

        let open = RoomWalls.preset(.open, toolbelt: ["swift"])
        #expect(open.shell == .normal)
        #expect(open.executables == .hostPath)
        #expect(open.network == .open)
    }

    @Test("withDefaultToolchainWrites — 숨은 예외 없이 스펙에 명시적 기록")
    func testWithDefaultToolchainWrites() {
        let baseWalls = RoomWalls.preset(.open)
        let wallsWithTools = baseWalls.withDefaultToolchainWrites(
            for: .claude,
            workdir: "/repo/my-app",
            homeDirectory: "/Users/tester",
            gitDir: "/repo/.bare"
        )
        #expect(wallsWithTools.filesystem.allowWrite.contains("/Users/tester/.claude"))
        #expect(wallsWithTools.filesystem.allowWrite.contains("/Users/tester/.claude.json"))
        #expect(wallsWithTools.filesystem.allowWrite.contains("/Users/tester/.swiftpm"))
        #expect(wallsWithTools.filesystem.allowWrite.contains("/repo/.bare"))
    }
}

@Suite("ExecRule — 파괴적 명령 격리 및 제한 셸 판정")
struct ExecRuleTests {
    @Test("파괴적 명령 rm -rf 는 restricted/normal 불문하고 quarantine")
    func testDestructiveRmQuarantine() {
        let restrictedWalls = RoomWalls(shell: .restricted)
        let normalWalls = RoomWalls(shell: .normal)

        #expect(ExecRule.decide(argv: ["rm", "-rf", "dir"], walls: restrictedWalls)
                == .quarantine(reason: "destructive command is quarantined (rm -rf)"))
        #expect(ExecRule.decide(argv: ["rm", "-r", "-f", "dir"], walls: normalWalls)
                == .quarantine(reason: "destructive command is quarantined (rm -rf)"))
        #expect(ExecRule.decide(argv: ["rm", "--recursive", "--force", "dir"], walls: normalWalls)
                == .quarantine(reason: "destructive command is quarantined (rm -rf)"))
    }

    @Test("파괴적 명령 git push --force 및 kubectl delete 격리")
    func testDestructiveGitPushAndKubectlQuarantine() {
        let walls = RoomWalls(shell: .normal)
        #expect(ExecRule.decide(argv: ["git", "push", "--force", "origin", "main"], walls: walls)
                == .quarantine(reason: "destructive command is quarantined (git push --force)"))
        #expect(ExecRule.decide(argv: ["git", "push", "-f", "origin", "main"], walls: walls)
                == .quarantine(reason: "destructive command is quarantined (git push --force)"))
        #expect(ExecRule.decide(argv: ["kubectl", "delete", "pod", "test"], walls: walls)
                == .quarantine(reason: "destructive command is quarantined (kubectl delete)"))
    }

    @Test("제한 셸 환경에서 경로 실행 및 셸 우회 차단, toolbelt 밖 도구 거부")
    func testRestrictedShellExecutionDeny() {
        let restrictedWalls = RoomWalls(executables: .allowList(["swift"]), shell: .restricted)

        #expect(ExecRule.decide(argv: ["/bin/ls"], walls: restrictedWalls)
                == .deny(reason: "restricted room: path execution is not allowed (/bin/ls)"))
        #expect(ExecRule.decide(argv: ["./script.sh"], walls: restrictedWalls)
                == .deny(reason: "restricted room: path execution is not allowed (./script.sh)"))
        #expect(ExecRule.decide(argv: ["sh", "-c", "ls"], walls: restrictedWalls)
                == .deny(reason: "restricted room: shell bypass is not allowed (sh)"))
        #expect(ExecRule.decide(argv: ["bash"], walls: restrictedWalls)
                == .deny(reason: "restricted room: shell bypass is not allowed (bash)"))
        #expect(ExecRule.decide(argv: ["zsh"], walls: restrictedWalls)
                == .deny(reason: "restricted room: shell bypass is not allowed (zsh)"))
        #expect(ExecRule.decide(argv: ["env", "VAR=1", "swift"], walls: restrictedWalls)
                == .deny(reason: "restricted room: shell bypass is not allowed (env)"))

        // 단독 도구명 호출은 통과 (POSIX 및 toolbelt 내 도구)
        #expect(ExecRule.decide(argv: ["ls"], walls: restrictedWalls) == .allow)
        #expect(ExecRule.decide(argv: ["swift", "test"], walls: restrictedWalls) == .allow)

        // toolbelt 밖 도구는 거부
        #expect(ExecRule.decide(argv: ["kubectl"], walls: restrictedWalls)
                == .deny(reason: "command not in toolbelt: kubectl"))
    }

    @Test("비제한 셸 환경(open)에서는 경로 실행 및 셸 호출 허용")
    func testNormalShellExecutionAllow() {
        let normalWalls = RoomWalls(shell: .normal)
        #expect(ExecRule.decide(argv: ["/bin/ls"], walls: normalWalls) == .allow)
        #expect(ExecRule.decide(argv: ["sh", "-c", "echo hello"], walls: normalWalls) == .allow)
    }
}

@Suite("골든 스냅샷 테스트 — 프리셋 3종 x workdir 유무 x 도구 4종 (총 24조합)")
struct GoldenSnapshotTests {
    struct Scenario {
        let preset: RoomWallPreset
        let workdir: String?
        let tool: AgentTool
    }

    static let allScenarios: [Scenario] = {
        let presets: [RoomWallPreset] = [.readOnly, .toolbelt, .open]
        let workdirs: [String?] = ["/repo/my-app", nil]
        let tools: [AgentTool] = [.claude, .codex, .grok, .agy]

        var list: [Scenario] = []
        for p in presets {
            for w in workdirs {
                for t in tools {
                    list.append(Scenario(preset: p, workdir: w, tool: t))
                }
            }
        }
        return list
    }()

    static let sampleTools: [String: String] = [
        "cat": "/bin/cat",
        "ls": "/bin/ls",
        "sh": "/bin/sh",
        "env": "/usr/bin/env",
        "agent-room-terminal": "/usr/local/bin/agent-room-terminal",
        "swift": "/usr/bin/swift",
        "git": "/usr/bin/git",
        "security": "/usr/bin/security",
        "claude": "/usr/local/bin/claude",
        "codex": "/usr/local/bin/codex",
        "grok": "/usr/local/bin/grok",
        "agy": "/usr/local/bin/agy",
    ]

    private func verifyScenario(_ s: Scenario) {
        // 1. 벽 스펙 생성 및 명시적 툴체인 쓰기 적용
        var walls = RoomWalls.preset(s.preset, toolbelt: ["swift", "git"])
        walls = walls.withDefaultToolchainWrites(
            for: s.tool,
            workdir: s.workdir,
            homeDirectory: "/Users/testuser",
            gitDir: s.workdir.map { "\($0)/.bare" }
        )

        // 2. Seatbelt Scheme 컴파일
        let profile = SeatbeltCompiler.profile(
            walls: walls,
            workdir: s.workdir,
            roomDir: "/rooms/test-room",
            home: "/Users/testuser",
            proxyPort: s.preset == .open ? nil : 8080
        )
        #expect(profile.contains(";; Pure One-Way Room Sandbox Seatbelt Profile (v1)"))
        #expect(profile.contains("(allow default)"))
        #expect(profile.contains("(deny file-write* (subpath \"/Users/testuser\"))"))
        #expect(profile.contains("(allow file-write* (subpath \"/rooms/test-room\"))"))

        // 3. PATH 계획 컴파일
        let plan = PathPlanner.plan(walls: walls, availableTools: Self.sampleTools)
        if s.preset == .open {
            // open 은 hostPath — 방 bin 링크 없이 호스트 PATH 를 그대로 쓴다.
            #expect(plan.links.isEmpty)
        } else {
            #expect(!plan.links.isEmpty)
            #expect(plan.names.contains("cat"))
            #expect(plan.names.contains("agent-room-terminal"))
        }

        // 4. 기동 argv 컴파일
        let launch = RoomLaunch(
            tool: s.tool,
            model: "test-model",
            promptText: "Fix the bug",
            promptFile: "/tmp/prompt.txt",
            workdir: s.workdir
        )
        let argv = LaunchArgv.build(launch: launch)
        #expect(!argv.isEmpty)
        #expect(argv.first == s.tool.rawValue)

        let display = LaunchArgv.displayCommand(launch: launch, argv: argv)
        #expect(!display.isEmpty)
    }

    @Test("24종 조합에 대해 Seatbelt 프로필, PATH 계획, 기동 argv 결정론적 산출 검증")
    func testAll24CombinationsDeterministic() {
        #expect(Self.allScenarios.count == 24)
        for s in Self.allScenarios {
            verifyScenario(s)
        }
    }

    @Test("LaunchArgv 세부 도구별 플래그 검증")
    func testLaunchArgvSpecificFlags() {
        let agyLaunch = RoomLaunch(
            tool: .agy,
            model: "o3-pro",
            promptText: "Solve problem",
            promptFile: "/tmp/p.txt"
        )
        let agyArgv = LaunchArgv.build(launch: agyLaunch)
        #expect(agyArgv == [
            "agy", "-p", "Solve problem",
            "--model", "o3-pro",
            "--dangerously-skip-permissions",
            "--input-format", "text",
            "--output-format", "stream-json",
            "--print-timeout", "3h"
        ])

        let grokLaunch = RoomLaunch(
            tool: .grok,
            model: "grok-beta",
            promptText: "Solve",
            promptFile: "/tmp/p.txt",
            workdir: "/repo"
        )
        let grokArgv = LaunchArgv.build(launch: grokLaunch)
        #expect(grokArgv == [
            "grok", "--cwd", "/repo",
            "--always-approve",
            "--output-format", "streaming-messages-json",
            "--max-turns", "200",
            "--model", "grok-beta",
            "--prompt-file", "/tmp/p.txt"
        ])

        let claudeLaunch = RoomLaunch(
            tool: .claude,
            model: "claude-3-5-sonnet",
            promptText: "Task prompt"
        )
        let claudeArgv = LaunchArgv.build(launch: claudeLaunch)
        #expect(claudeArgv == [
            "claude", "-p", "Task prompt",
            "--dangerously-skip-permissions",
            "--output-format", "text",
            "--model", "claude-3-5-sonnet"
        ])
    }

    @Test("codex 0.147 — `codex exec`, -p 없음, 프롬프트는 마지막 위치 인수")
    func testCodexExecArgvSnapshot() {
        let launch = RoomLaunch(
            tool: .codex,
            model: "gpt-5-codex",
            promptText: "Fix the failing test",
            promptFile: "/tmp/p.txt",
            workdir: "/repo"
        )
        let argv = LaunchArgv.build(launch: launch)
        #expect(argv == [
            "codex", "exec",
            "--model", "gpt-5-codex",
            "--cd", "/repo",
            "--dangerously-bypass-approvals-and-sandbox",
            "--skip-git-repo-check",
            "Fix the failing test"
        ])
        #expect(argv[1] == "exec")
        #expect(!argv.contains("-p"))
        #expect(!argv.contains("--prompt-file"))
        #expect(argv.last == "Fix the failing test")

        let display = LaunchArgv.displayCommand(launch: launch, argv: argv)
        #expect(display.hasSuffix("@/tmp/p.txt"))
        #expect(!display.contains("Fix the failing test"))
    }

    @Test("codex — promptFile 만 있으면 본문을 읽어 마지막 위치 인수로 넘긴다")
    func testCodexPromptFileOnly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("roomkit-argv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("brief.md")
        try "Do the task\nwith two lines\n".write(to: file, atomically: true, encoding: .utf8)

        let launch = RoomLaunch(tool: .codex, promptFile: file.path)
        let argv = LaunchArgv.build(launch: launch)
        #expect(argv.first == "codex")
        #expect(argv.dropFirst().first == "exec")
        #expect(argv.last == "Do the task\nwith two lines\n")
        #expect(!argv.contains("--model"))
        #expect(!argv.contains("--cd"))

        // 파일이 없거나 프롬프트가 아예 없으면 기동하지 않는다.
        let missing = RoomLaunch(tool: .codex, promptFile: dir.appendingPathComponent("none.md").path)
        #expect(LaunchArgv.build(launch: missing).isEmpty)
        #expect(LaunchArgv.build(launch: RoomLaunch(tool: .codex)).isEmpty)
    }

    @Test("buildExecArgv 호환 — 네 도구 모두 build(launch:) 와 동일")
    func testBuildExecArgvCompatibility() {
        for tool in AgentTool.allCases {
            let viaExec = LaunchArgv.buildExecArgv(
                tool: tool,
                promptFile: "/tmp/p.txt",
                promptText: "Prompt body",
                model: "m1",
                workdir: "/repo"
            )
            let viaLaunch = LaunchArgv.build(launch: RoomLaunch(
                tool: tool,
                model: "m1",
                promptText: "Prompt body",
                promptFile: "/tmp/p.txt",
                workdir: "/repo"
            ))
            #expect(viaExec == viaLaunch)
            #expect(viaExec.first == (tool == .cursor ? "cursor-agent" : tool.rawValue))
        }
        let codex = LaunchArgv.buildExecArgv(
            tool: .codex, promptFile: "", promptText: "Prompt body", model: nil, workdir: nil
        )
        #expect(codex == [
            "codex", "exec",
            "--dangerously-bypass-approvals-and-sandbox",
            "--skip-git-repo-check",
            "Prompt body"
        ])
        let agy = LaunchArgv.buildExecArgv(
            tool: .agy, promptFile: "", promptText: "Prompt body", model: "m1", workdir: nil
        )
        #expect(agy.contains("-p"))
        #expect(agy.contains("--print-timeout"))
        #expect(agy.contains("--input-format"))
    }
}

@Suite("RoomPaths — 정본 경로 규약 및 탐색")
struct RoomPathsTests {
    @Test("cleanTenantSlug — tenant: 및 @ 접두사 정규화")
    func testCleanTenantSlug() {
        #expect(RoomPaths.cleanTenantSlug("tenant:alpha") == "alpha")
        #expect(RoomPaths.cleanTenantSlug("@beta") == "beta")
        #expect(RoomPaths.cleanTenantSlug("gamma") == "gamma")
    }

    @Test("roomDirectory 및 specURL — 정본 경로 조립")
    func testCanonicalPaths() {
        let fakeHome = "/tmp/test-home"
        let dir = RoomPaths.roomDirectory(tenant: "tenant:proj", roomID: "room-123", environment: [:], homeDirectory: fakeHome)
        #expect(dir.path == "/tmp/test-home/.tenants/proj/rooms/room-123")

        let spec = RoomPaths.specURL(tenant: "tenant:proj", roomID: "room-123", environment: [:], homeDirectory: fakeHome)
        #expect(spec.path == "/tmp/test-home/.tenants/proj/rooms/room-123/spec.json")
    }

    @Test("findRoomDirectory — 정본 경로 및 레거시 2-depth fallback 탐색")
    func testFindRoomDirectory() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        let fm = FileManager.default
        try fm.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempHome) }

        // 1. 정본 경로 생성: ~/.tenants/alpha/rooms/canon-room
        let canonDir = RoomPaths.roomDirectory(tenant: "alpha", roomID: "canon-room", environment: [:], homeDirectory: tempHome.path)
            .resolvingSymlinksInPath()
        try fm.createDirectory(at: canonDir, withIntermediateDirectories: true)

        // 2. 레거시 경로 생성: ~/.tenants/beta/rooms/layout-99/legacy-room
        let legacyDir = RoomPaths.tenantsRoot(environment: [:], homeDirectory: tempHome.path)
            .appendingPathComponent("beta", isDirectory: true)
            .appendingPathComponent("rooms", isDirectory: true)
            .appendingPathComponent("layout-99", isDirectory: true)
            .appendingPathComponent("legacy-room", isDirectory: true)
            .resolvingSymlinksInPath()
        try fm.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        // 정본 찾기 (tenant 지정)
        let foundCanon = RoomPaths.findRoomDirectory(roomID: "canon-room", tenant: "alpha", environment: [:], homeDirectory: tempHome.path)?
            .resolvingSymlinksInPath()
        #expect(foundCanon?.path == canonDir.path)

        // 레거시 찾기 (tenant 지정)
        let foundLegacy = RoomPaths.findRoomDirectory(roomID: "legacy-room", tenant: "beta", environment: [:], homeDirectory: tempHome.path)?
            .resolvingSymlinksInPath()
        #expect(foundLegacy?.path == legacyDir.path)

        // tenant=nil 로 순회 탐색
        let foundAnyCanon = RoomPaths.findRoomDirectory(roomID: "canon-room", tenant: nil, environment: [:], homeDirectory: tempHome.path)?
            .resolvingSymlinksInPath()
        #expect(foundAnyCanon?.path == canonDir.path)

        let foundAnyLegacy = RoomPaths.findRoomDirectory(roomID: "legacy-room", tenant: nil, environment: [:], homeDirectory: tempHome.path)?
            .resolvingSymlinksInPath()
        #expect(foundAnyLegacy?.path == legacyDir.path)

        // 없는 방
        let notFound = RoomPaths.findRoomDirectory(roomID: "ghost-room", tenant: nil, environment: [:], homeDirectory: tempHome.path)
        #expect(notFound == nil)
    }

    @Test("macOS NFD 한글 폴더명 정규화 매칭 검증 (NFC vs NFD)")
    func testHangulUnicodeNormalizationMatching() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        let fm = FileManager.default
        try fm.createDirectory(at: tempHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempHome) }

        let nfcName = "부엉이"
        let nfdName = nfcName.decomposedStringWithCanonicalMapping
        #expect(nfcName.utf8.count != nfdName.utf8.count)

        // 1. cleanTenantSlug NFD -> NFC 변환
        #expect(RoomPaths.cleanTenantSlug("tenant:\(nfdName)") == nfcName)

        // 2. 디스크에 NFD 이름으로 방 디렉토리 생성
        let tenant = "owl-tenant"
        let roomsDir = RoomPaths.tenantsRoot(environment: [:], homeDirectory: tempHome.path)
            .appendingPathComponent(tenant, isDirectory: true)
            .appendingPathComponent(RoomPaths.roomsDirectoryName, isDirectory: true)
        let nfdRoomDir = roomsDir.appendingPathComponent(nfdName, isDirectory: true)
        try fm.createDirectory(at: nfdRoomDir, withIntermediateDirectories: true)

        // NFC로 검색 시 발견 확인
        let foundNfc = RoomPaths.findRoomDirectory(roomID: nfcName, tenant: tenant, environment: [:], homeDirectory: tempHome.path)?
            .resolvingSymlinksInPath()
        #expect(foundNfc != nil)
        #expect(foundNfc?.lastPathComponent.precomposedStringWithCanonicalMapping == nfcName)

        // NFD로 검색 시 발견 확인
        let foundNfd = RoomPaths.findRoomDirectory(roomID: nfdName, tenant: tenant, environment: [:], homeDirectory: tempHome.path)?
            .resolvingSymlinksInPath()
        #expect(foundNfd != nil)
        #expect(foundNfd?.lastPathComponent.precomposedStringWithCanonicalMapping == nfcName)
    }
}

@Suite("RoomEvents — 이벤트 원장 및 상태 투영")
struct RoomEventsTests {
    @Test("RoomEventLog append 및 read 순서 보장")
    func testEventLogAppendRead() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let log = RoomEventLog(roomURL: tempDir)
        let ev1 = try log.append(RoomEvent.created(by: "system"))
        #expect(ev1.seq == 1)
        #expect(ev1.kind == RoomEventKind.created)

        let ev2 = try log.append(RoomEvent.occupied(agent: "agent:claude@macbook", sessionID: "s-1"))
        #expect(ev2.seq == 2)
        #expect(ev2.kind == RoomEventKind.occupied)

        let result = log.read(since: 0)
        #expect(result.events.count == 2)
        #expect(result.corruptCount == 0)
        #expect(result.events[0].seq == 1)
        #expect(result.events[1].seq == 2)
    }

    @Test("RoomStatusProjection — 이벤트 스트림 누적 투영")
    func testStatusProjection() {
        var ev1 = RoomEvent.created(by: "system")
        ev1.seq = 1
        var ev2 = RoomEvent.occupied(agent: "agent:claude@macbook", sessionID: "sess-abc")
        ev2.seq = 2
        var ev3 = RoomEvent.vacated(reason: "task done")
        ev3.seq = 3
        var ev4 = RoomEvent.closed(sessionID: "sess-abc")
        ev4.seq = 4

        var status = RoomStatusProjection.reduce(events: [ev1])
        #expect(status.phase == .created)

        status = RoomStatusProjection.reduce(events: [ev1, ev2])
        #expect(status.phase == .occupied)
        #expect(status.occupant == "agent:claude@macbook")
        #expect(status.sessionID == "sess-abc")

        status = RoomStatusProjection.reduce(events: [ev1, ev2, ev3])
        #expect(status.phase == .open)
        #expect(status.occupant == nil)

        status = RoomStatusProjection.reduce(events: [ev1, ev2, ev3, ev4])
        #expect(status.phase == .closed)
    }
}

@Suite("LaunchArgvExtended — 확장 파라미터 및 출력 파싱")
struct LaunchArgvExtendedTests {
    @Test("buildOpenArgv with specURL and json")
    func testBuildOpenArgvSpec() {
        let specURL = URL(fileURLWithPath: "/tmp/spec.json")
        let argv = LaunchArgv.buildOpenArgv(
            specURL: specURL,
            tool: .claude,
            preset: .open,
            json: true
        )
        #expect(argv == [
            "agent-room-terminal", "open",
            "--spec", "/tmp/spec.json",
            "--tool", "claude", "--execute",
            "--preset", "open",
            "--json"
        ])
    }

    @Test("parseOpenPath — 정상 및 비정상 응답 파싱")
    func testParseOpenPath() throws {
        let validJSON = try #require("""
        {"ok": true, "result": {"path": "/rooms/alpha/test-1"}}
        """.data(using: .utf8))
        let parsed = LaunchArgv.parseOpenPath(from: validJSON)
        #expect(parsed.path == "/rooms/alpha/test-1")
        #expect(parsed.note == nil)

        let errJSON = try #require("""
        {"ok": false, "error": "room not found"}
        """.data(using: .utf8))
        let parsedErr = LaunchArgv.parseOpenPath(from: errJSON)
        #expect(parsedErr.path == nil)
        #expect(parsedErr.note?.contains("room not found") == true)
    }
}

@Suite("SeatbeltCompiler.compile 및 PathPlanner 규칙 검증")
struct SeatbeltCompilerCompileTests {
    @Test("SeatbeltCompiler.compile — RoomSpec 으로부터 프로필, env, writePaths 결정론적 산출")
    func testCompileSpec() throws {
        let roomID = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let spec = RoomSpec(
            roomID: roomID,
            tenant: "tenant:alpha",
            task: "compile task",
            verdict: "true",
            workdir: "/wt/project",
            walls: RoomWalls(
                filesystem: FilesystemWall(allowWrite: ["apps/x/**"]),
                network: .allow(domains: ["api.openai.com"])
            ),
            launch: RoomLaunch(tool: .claude, promptText: "Fix something")
        )

        let result = SeatbeltCompiler.compile(
            spec: spec,
            roomDir: "/rooms/r1",
            home: "/Users/testuser",
            proxyPort: 9090
        )

        #expect(result.profile.contains(";; Pure One-Way Room Sandbox Seatbelt Profile (v1)"))
        #expect(result.profile.contains("(allow file-write* (subpath \"/wt/project/apps/x\"))"))
        #expect(result.profile.contains("(allow file-write* (subpath \"/Users/testuser/.claude\"))"))
        #expect(result.env["HTTP_PROXY"] == "http://localhost:9090")
        #expect(result.writePaths.contains("/wt/project/apps/x"))
        #expect(result.writePaths.contains("/Users/testuser/.claude"))
    }

    @Test("PathPlanner 규칙 일관성 검증")
    func testPathPlannerRules() {
        let writes = PathPlanner.resolvedWritePaths(
            roomPath: "/rooms/r1",
            workdir: "/wt/app",
            writePaths: ["apps/x/**", "/abs/y"]
        )
        #expect(writes == ["/wt/app/apps/x", "/abs/y"])

        let agentPaths = PathPlanner.agentStatePaths(
            agentTools: ["claude", "agy"],
            homeDirectory: "/Users/tester"
        )
        #expect(agentPaths.contains("/Users/tester/.claude"))
        #expect(agentPaths.contains("/Users/tester/.gemini"))

        let openToolchain = PathPlanner.buildToolchainStatePaths(
            preset: .open,
            workdir: nil,
            homeDirectory: "/Users/tester"
        )
        #expect(openToolchain.contains("/Users/tester/.swiftpm"))

        let gitDir = PathPlanner.gitCommonDirectory(
            fromGitFile: "gitdir: ../../.bare/worktrees/w1",
            workdir: "/repo/.worktrees/w1"
        )
        #expect(gitDir == "/repo/.bare")
    }
}


