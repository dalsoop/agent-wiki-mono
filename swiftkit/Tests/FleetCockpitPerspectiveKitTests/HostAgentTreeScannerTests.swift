import XCTest
@testable import FleetCockpitPerspectiveKit

final class HostAgentTreeScannerTests: XCTestCase {
    
    let mockProcessTable = """
      PID  PPID TTY      COMMAND
      500     1 ??       herdr --remote host-node-1
      600   500 ??       tmux: server
      700   600 ttys003  /bin/zsh -l
      800   700 ttys003  claude --dangerously-skip-permissions
      900   800 ??       node /Users/jeonghan/.claude/tool-subagent.js
      901   800 ??       /bin/sh -c git status
      902   900 ??       codex worker --task 42
      120     1 ??       /usr/sbin/syslogd
    """

    func testParseProcessTable() {
        let records = HostAgentTreeScanner.parseProcessTable(mockProcessTable)
        XCTAssertEqual(records.count, 8)
        
        let herdrRecord = records.first { $0.pid == 500 }
        XCTAssertNotNil(herdrRecord)
        XCTAssertEqual(herdrRecord?.ppid, 1)
        XCTAssertNil(herdrRecord?.tty)
        XCTAssertEqual(herdrRecord?.command, "herdr --remote host-node-1")

        let ptyRecord = records.first { $0.pid == 700 }
        XCTAssertNotNil(ptyRecord)
        XCTAssertEqual(ptyRecord?.ppid, 600)
        XCTAssertEqual(ptyRecord?.tty, "ttys003")
        XCTAssertEqual(ptyRecord?.command, "/bin/zsh -l")

        let claudeRecord = records.first { $0.pid == 800 }
        XCTAssertNotNil(claudeRecord)
        XCTAssertEqual(claudeRecord?.ppid, 700)
        XCTAssertEqual(claudeRecord?.tty, "ttys003")
        XCTAssertEqual(claudeRecord?.command, "claude --dangerously-skip-permissions")
    }

    func testHerdrTmuxPTYClaudeSubagentLineage() {
        let records = HostAgentTreeScanner.parseProcessTable(mockProcessTable)
        let lineages = HostAgentTreeScanner.extractLineages(from: records)

        XCTAssertEqual(lineages.count, 1)
        guard let lineage = lineages.first else {
            XCTFail("Lineage should not be empty")
            return
        }

        // herdr -> tmux -> PTY -> claude -> 서브에이전트 계통 검증
        XCTAssertEqual(lineage.claudePID, 800)
        XCTAssertEqual(lineage.ptyPID, 700)
        XCTAssertEqual(lineage.tmuxPID, 600)
        XCTAssertEqual(lineage.herdrPID, 500)
        XCTAssertEqual(lineage.subagentPIDs, [900, 901, 902])
    }

    func testBuildTreeHierarchy() {
        let records = HostAgentTreeScanner.parseProcessTable(mockProcessTable)
        let tree = HostAgentTreeScanner.buildTree(from: records)

        // 최상위 노드 중 herdr 탐색
        guard let herdrNode = tree.first(where: { $0.pid == 500 }) else {
            XCTFail("Herdr node not found at root")
            return
        }
        XCTAssertEqual(herdrNode.role, .herdr)
        XCTAssertEqual(herdrNode.children.count, 1)

        // tmux 노드
        let tmuxNode = herdrNode.children[0]
        XCTAssertEqual(tmuxNode.pid, 600)
        XCTAssertEqual(tmuxNode.role, .tmux)
        XCTAssertEqual(tmuxNode.children.count, 1)

        // PTY (zsh) 노드
        let ptyNode = tmuxNode.children[0]
        XCTAssertEqual(ptyNode.pid, 700)
        XCTAssertEqual(ptyNode.role, .pty)
        XCTAssertEqual(ptyNode.children.count, 1)

        // Claude 에이전트 노드
        let claudeNode = ptyNode.children[0]
        XCTAssertEqual(claudeNode.pid, 800)
        XCTAssertEqual(claudeNode.role, .claude)
        XCTAssertEqual(claudeNode.children.count, 2) // 900 and 901

        // Claude의 자식 (서브에이전트들)
        let childRoles = claudeNode.children.map(\.role)
        XCTAssertTrue(childRoles.allSatisfy { $0 == .subagent })

        // 900 노드의 자식 902 (서브에이전트 계층)
        if let node900 = claudeNode.children.first(where: { $0.pid == 900 }) {
            XCTAssertEqual(node900.children.count, 1)
            XCTAssertEqual(node900.children[0].pid, 902)
            XCTAssertEqual(node900.children[0].role, .subagent)
        } else {
            XCTFail("Subagent node 900 not found")
        }
    }

    func testScannerWithMockProvider() {
        let table = self.mockProcessTable
        let scanner = HostAgentTreeScanner(tableProvider: { table })
        let result = scanner.scan()
        let lineages = result.lineages

        XCTAssertEqual(lineages.count, 1)
        XCTAssertEqual(lineages[0].claudePID, 800)
        XCTAssertEqual(lineages[0].herdrPID, 500)
        XCTAssertEqual(lineages[0].tmuxPID, 600)
        XCTAssertEqual(lineages[0].ptyPID, 700)
        XCTAssertEqual(lineages[0].subagentPIDs.count, 3)

        // 에이전트 목록 검증
        XCTAssertEqual(result.agents.count, 1)
        XCTAssertEqual(result.agents[0].pid, 800)
        XCTAssertEqual(result.agents[0].tool, "claude")
        XCTAssertEqual(result.agents[0].subjobCount, 3)
    }

    func testRealHostProcessTableParsingSmoke() {
        let raw = HostAgentTreeScanner.fetchSystemProcessTable()
        if !raw.isEmpty {
            let records = HostAgentTreeScanner.parseProcessTable(raw)
            XCTAssertFalse(records.isEmpty, "System process table should parse into non-empty records")
            XCTAssertTrue(records.contains { $0.pid > 0 })
        }
    }

    func testRealHostAgentScanDetectsRunningAgents() {
        let result = HostAgentTreeScanner.shared.scan()
        // 호스트에서 실제 에이전트(claude, agy 등)가 실행 중일 때
        if !result.agents.isEmpty {
            for agent in result.agents {
                XCTAssertGreaterThan(agent.pid, 0, "에이전트 PID는 반드시 0보다 커야 합니다.")
                XCTAssertFalse(agent.tool.isEmpty, "에이전트 툴 이름이 비어있으면 안 됩니다.")
                XCTAssertNotNil(agent.container, "컨테이너 귀속 정보가 있어야 합니다.")
            }
        }
    }

    func testInvertedStateStoreRealAgentPIDsAreNeverZero() {
        let store = InvertedStateStore.shared
        store.reloadOnce()
        let agents = store.currentAgents()
        for agent in agents {
            XCTAssertNotEqual(agent.pid, 0, "InvertedStateStore의 AgentSessionEntry PID는 절대 0이 아니어야 합니다.")
        }
    }

    func testAgentBarDataSourceDoesNotContainFakeFallbackWhenLiveAgentsExist() {
        let store = InvertedStateStore.shared
        store.reloadOnce()
        let ds = AgentBarDataSource(store: store)
        let items = ds.currentItems()
        XCTAssertFalse(
            items.contains { $0.id == "agent-active-session" },
            "실제 에이전트 환경에서 가짜 agent-active-session이 주입되어서는 안 됩니다."
        )
        XCTAssertFalse(
            items.contains { $0.id == "awo-pipeline-shared" },
            "실제 에이전트 환경에서 가짜 awo-pipeline-shared가 주입되어서는 안 됩니다."
        )
    }

    func testExtractSubagentTitle() {
        // 1. 프롬프트 형태 (문 게이트 구현)
        let t1 = HostAgentTreeScanner.extractSubagentTitle(command: "claude -p '문 게이트 구현'")
        XCTAssertEqual(t1, "문 게이트 구현")

        let t2 = HostAgentTreeScanner.extractSubagentTitle(command: "agy --prompt \"문 게이트 구현\"")
        XCTAssertEqual(t2, "문 게이트 구현")

        // 2. worktree 디렉터리 경로 형태 (glm-w3-stateroot, glm-w4-identity-regen)
        let t3 = HostAgentTreeScanner.extractSubagentTitle(command: "node glm.js --worktree /repo/.worktrees/glm-w3-stateroot")
        XCTAssertEqual(t3, "glm-w3-stateroot")

        let t4 = HostAgentTreeScanner.extractSubagentTitle(command: "glm /workspace/.worktrees/glm-w4-identity-regen")
        XCTAssertEqual(t4, "glm-w4-identity-regen")

        // 3. 스크립트 실행 (shepherd.sh, tool-subagent.js)
        let t5 = HostAgentTreeScanner.extractSubagentTitle(command: "/bin/bash /opt/tools/shepherd.sh --watch")
        XCTAssertEqual(t5, "shepherd.sh")

        let t6 = HostAgentTreeScanner.extractSubagentTitle(command: "node /Users/jeonghan/.claude/tool-subagent.js")
        XCTAssertEqual(t6, "tool-subagent.js")

        // 4. 셸 명령 실행
        let t7 = HostAgentTreeScanner.extractSubagentTitle(command: "/bin/sh -c git status")
        XCTAssertEqual(t7, "git status")

        // 5. CLI worker 실행
        let t8 = HostAgentTreeScanner.extractSubagentTitle(command: "codex worker --task 42")
        XCTAssertTrue(t8.contains("codex worker") && t8.contains("42"))
    }

    func testRealSubagentHierarchyInScanResult() {
        let table = self.mockProcessTable
        let scanner = HostAgentTreeScanner(tableProvider: { table })
        let result = scanner.scan()

        guard let claude = result.agents.first(where: { $0.pid == 800 }) else {
            XCTFail("Claude agent 800 not found")
            return
        }

        // 실제 직속 자식 서브에이전트들이 subagents에 담겨 있어야 함 (900, 901)
        XCTAssertEqual(claude.subagents.count, 2)
        let subPids = claude.subagents.map(\.pid)
        XCTAssertTrue(subPids.contains(900))
        XCTAssertTrue(subPids.contains(901))

        // 900 서브에이전트의 실제 타이틀 및 자식 902 검증
        guard let sub900 = claude.subagents.first(where: { $0.pid == 900 }) else {
            XCTFail("Subagent 900 not found")
            return
        }
        XCTAssertEqual(sub900.title, "tool-subagent.js")
        XCTAssertEqual(sub900.subagents.count, 1)
        XCTAssertEqual(sub900.subagents[0].pid, 902)
        XCTAssertTrue(sub900.subagents[0].title?.contains("codex worker") == true)

        // 901 서브에이전트
        guard let sub901 = claude.subagents.first(where: { $0.pid == 901 }) else {
            XCTFail("Subagent 901 not found")
            return
        }
        XCTAssertEqual(sub901.title, "git status")
    }

    func testScanTreeGeneratesRealChildrenWithoutFakeSubagentDummies() {
        let table = self.mockProcessTable
        let scanner = HostAgentTreeScanner(tableProvider: { table })
        let scanResult = scanner.scan()

        let baseBarItem = UnifiedBarItem(
            id: "agent-800",
            title: "claude #800",
            subtitle: "workspace",
            icon: .symbol("sparkles"),
            statusDot: .running,
            subjobCount: 3,
            runningSubjobCount: 3,
            workdir: "/Users/jeonghan/workspace"
        )

        let scannedTrees = scanner.scanTree(baseAgents: [baseBarItem], scanResult: scanResult)
        XCTAssertEqual(scannedTrees.count, 1)

        let rootItem = scannedTrees[0]
        // 자식이 2개 (900, 901)
        XCTAssertEqual(rootItem.children.count, 2)

        // "Subagent #1", "Subagent #2" 같은 가짜 더미 문자열이 전혀 없어야 함!
        for child in rootItem.children {
            XCTAssertFalse(child.title.hasPrefix("Subagent #"), "더미 Subagent #i 가 존재해서는 안 됩니다: \(child.title)")
            XCTAssertFalse(child.id.contains("-sub-1"), "가짜 카운터 기반 id가 아니어야 합니다: \(child.id)")
        }

        // 900번 아이템 확인
        guard let item900 = rootItem.children.first(where: { $0.id == "agent-800-sub-900" }) else {
            XCTFail("Child item for PID 900 not found")
            return
        }
        XCTAssertEqual(item900.title, "tool-subagent.js")
        XCTAssertEqual(item900.subtitle, "subagent #900")
        XCTAssertEqual(item900.children.count, 1)
        XCTAssertEqual(item900.children[0].id, "agent-800-sub-900-sub-902")

        // 901번 아이템 확인
        guard let item901 = rootItem.children.first(where: { $0.id == "agent-800-sub-901" }) else {
            XCTFail("Child item for PID 901 not found")
            return
        }
        XCTAssertEqual(item901.title, "git status")
        XCTAssertEqual(item901.subtitle, "pty #901")
    }

    func testScannerCachingTTL() {
        let scanner = HostAgentTreeScanner(cacheTTL: 2.0)
        // 캐시 무효화 후
        scanner.invalidateCache()

        // 커스텀 프로바이더가 없는 경우에 TTL 캐시가 작동함
        // 1. 첫 스캔
        let r1 = scanner.scan()
        // 2. 직후 스캔 (캐시 반환)
        let r2 = scanner.scan()
        XCTAssertEqual(r1.timestamp, r2.timestamp)

        // 3. 강제 리프레시 시에는 갱신
        let r3 = scanner.scan(forceRefresh: true)
        XCTAssertTrue(r3.timestamp >= r1.timestamp)
    }

    func testSessionIDAccurateMatchingNotShadowedByEarlierPanes() {
        // herdr json에 여러 개의 claude pane이 있고, 동일한 CWD를 공유하지만 세션 ID가 다른 경우
        let mockHerdrJSON = """
        {
          "result": {
            "panes": [
              {
                "agent": "claude",
                "agent_status": "running",
                "cwd": "/workspace/main",
                "terminal_title": "첫 번째 세션 (분석)",
                "terminal_title_stripped": "첫 번째 세션 (분석)",
                "agent_session": { "value": "session-1111" }
              },
              {
                "agent": "claude",
                "agent_status": "running",
                "cwd": "/workspace/main",
                "terminal_title": "두 번째 세션 (Room 방식 개선 비교)",
                "terminal_title_stripped": "두 번째 세션 (Room 방식 개선 비교)",
                "agent_session": { "value": "session-2222" }
              }
            ]
          }
        }
        """

        let mockProcessTable = """
          PID  PPID TTY      COMMAND
          100     1 ??       herdr server
          200   100 ttys001  claude --resume session-2222 --workdir /workspace/main
        """

        let records = HostAgentTreeScanner.parseProcessTable(mockProcessTable)
        let lineages = HostAgentTreeScanner.extractLineages(from: records)
        let cwdMap: [Int32: String] = [200: "/workspace/main"]

        let result = HostAgentTreeScanner.buildScanResult(
            records: records,
            lineages: lineages,
            cwdMap: cwdMap,
            herdrJson: mockHerdrJSON
        )

        XCTAssertEqual(result.agents.count, 1)
        guard let agent = result.agents.first else {
            XCTFail("Agent not found")
            return
        }

        // 첫 번째 pane("첫 번째 세션 (분석)")에 쉐도잉되지 않고, 정확히 session-2222에 매칭된 타이틀이 나와야 함
        XCTAssertEqual(agent.sessionID, "session-2222")
        XCTAssertEqual(agent.title, "두 번째 세션 (Room 방식 개선 비교)")
    }

    func testProcessModelCLIArgumentDetection() {
        let model1 = HostAgentTreeScanner.detectProcessModel(pid: 999999, command: "claude --model claude-fable-5")
        XCTAssertEqual(model1, "claude-fable-5")

        let model2 = HostAgentTreeScanner.detectProcessModel(pid: 999999, command: "claude --model GLM-5.3 --dangerously-skip-permissions")
        XCTAssertEqual(model2, "GLM-5.3")

        let model3 = HostAgentTreeScanner.detectProcessModel(pid: 999999, command: "claude")
        // pid 999999는 존재하지 않으므로 nil
        XCTAssertNil(model3)
    }

    func testDirectProcessToPaneAttributionByForegroundPgid() {
        // --resume 플래그가 전혀 없는 claude 프로세스가 있을 때,
        // herdr pane의 foreground_process_group_id가 일치하면 해당 pane에 100% 직속 결합되는지 검증
        let mockHerdrJSON = """
        {
          "result": {
            "panes": [
              {
                "pane_id": "w6:pT",
                "agent": "claude",
                "agent_status": "running",
                "cwd": "/workspace/main",
                "terminal_title": "첫 번째 분석 pane",
                "terminal_title_stripped": "첫 번째 분석 pane",
                "foreground_process_group_id": 11111
              },
              {
                "pane_id": "w6:p0",
                "agent": "claude",
                "agent_status": "working",
                "cwd": "/workspace/main",
                "terminal_title": "◑ Gujo.ai 사업계획서",
                "terminal_title_stripped": "Gujo.ai 사업계획서",
                "agent_session": { "value": "9c007302-39a9-4019-b9f1-978435469c55" },
                "foreground_process_group_id": 41921
              }
            ]
          }
        }
        """

        let mockProcessTable = """
          PID  PPID TTY      COMMAND
          100     1 ??       herdr server
        41921   100 ttys018  claude
        """

        let records = HostAgentTreeScanner.parseProcessTable(mockProcessTable)
        let lineages = HostAgentTreeScanner.extractLineages(from: records)
        let cwdMap: [Int32: String] = [41921: "/workspace/main"]

        let result = HostAgentTreeScanner.buildScanResult(
            records: records,
            lineages: lineages,
            cwdMap: cwdMap,
            herdrJson: mockHerdrJSON
        )

        XCTAssertEqual(result.agents.count, 1)
        guard let agent = result.agents.first else {
            XCTFail("Agent 41921 not found")
            return
        }

        // 첫 번째 pane("첫 번째 분석 pane")에 걸리지 않고, 자신의 foreground_process_group_id와 일치하는 w6:p0에 직속 결합
        XCTAssertEqual(agent.pid, 41921)
        XCTAssertEqual(agent.title, "Gujo.ai 사업계획서")
        XCTAssertEqual(agent.sessionID, "9c007302-39a9-4019-b9f1-978435469c55")
    }

    func testMultipleAgentsDoNotDuplicateSamePaneTitle() {
        // 동일한 CWD를 가진 2개의 agy 프로세스
        let mockHerdrJSON = """
        {
          "result": {
            "panes": [
              {
                "pane_id": "w6:pR",
                "agent": "agy",
                "agent_status": "idle",
                "cwd": "/workspace/main",
                "terminal_title": "grok",
                "terminal_title_stripped": "grok"
              },
              {
                "pane_id": "w6:pY",
                "agent": "agy",
                "agent_status": "working",
                "cwd": "/workspace/main",
                "terminal_title": "task-runner",
                "terminal_title_stripped": "task-runner"
              }
            ]
          }
        }
        """

        let mockProcessTable = """
          PID  PPID TTY      COMMAND
          100     1 ??       herdr server
          201   100 ttys004  agy
          202   100 ttys030  agy
        """

        let records = HostAgentTreeScanner.parseProcessTable(mockProcessTable)
        let lineages = HostAgentTreeScanner.extractLineages(from: records)
        let cwdMap: [Int32: String] = [201: "/workspace/main", 202: "/workspace/main"]

        let result = HostAgentTreeScanner.buildScanResult(
            records: records,
            lineages: lineages,
            cwdMap: cwdMap,
            herdrJson: mockHerdrJSON
        )

        XCTAssertEqual(result.agents.count, 2)
        let titles = result.agents.compactMap(\.title)
        XCTAssertEqual(titles.count, 2)
        // 두 에이전트가 모두 "grok"으로 중복 할당되지 않고 각각 w6:pR과 w6:pY를 배타적으로 차지해야 함
        XCTAssertTrue(titles.contains("grok"))
        XCTAssertTrue(titles.contains("task-runner"))
    }

    /// `herdr pane process-info` JSON 계약. 라이브 herdr·stdout print 스모크는
    /// 병렬 테스트의 stdout 캡처를 오염한다.
    func testHerdrProcessInfoResponseMapsForegroundGroup() throws {
        let json = """
        {
          "result": {
            "process_info": {
              "foreground_process_group_id": 56024,
              "shell_pid": 1246,
              "foreground_processes": [{"pid": 56024}]
            }
          }
        }
        """
        let decoded = try JSONDecoder().decode(
            HerdrProcessInfoResponse.self, from: Data(json.utf8))
        let pinfo = try XCTUnwrap(decoded.result?.process_info)
        XCTAssertEqual(pinfo.foreground_process_group_id, 56024)
        XCTAssertEqual(pinfo.shell_pid, 1246)
        XCTAssertEqual(pinfo.foreground_processes?.compactMap(\.pid), [56024])
    }
}
