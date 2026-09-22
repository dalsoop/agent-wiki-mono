import Foundation

/// 방 안에서 에이전트 CLI 를 기동하기 위한 argv 순수 빌더 (L3)
///
/// `LaunchArgvBuilder` 와 AWO `BatchManager.makeWorkerArguments` 규칙을 단일 정본으로 통합한다.
public enum LaunchArgv {
    public static let defaultAgyPrintTimeout = "3h"

    /// occupant 문자열 (예: "agent:claude@macbook") 에서 AgentTool 을 파싱한다.
    public static func parseTool(from occupant: String) -> AgentTool? {
        let prefix = "agent:"
        guard occupant.hasPrefix(prefix) else { return nil }
        let rest = occupant.dropFirst(prefix.count)
        guard let atIndex = rest.firstIndex(of: "@") else { return nil }
        let toolName = String(rest[rest.startIndex..<atIndex])
        return AgentTool(rawValue: toolName)
    }

    /// `RoomLaunch` 스펙으로부터 프로세스 실행 argv 배열을 빌드한다.
    public static func build(launch: RoomLaunch) -> [String] {
        switch launch.tool {
        case .agy:   return agyArgv(launch)
        case .grok:  return grokArgv(launch)
        case .claude: return claudeArgv(launch)
        case .codex: return codexArgv(launch)
        case .cursor: return cursorArgv(launch)
        case .opencode:
            var argv = [launch.tool.executableName]
            if let model = launch.model, !model.isEmpty {
                argv += ["--model", model]
            }
            if !launch.promptText.isEmpty {
                argv += [launch.promptText]
            }
            return argv
        }
    }

    // agy 1.2.0 (`agy --help`, 2026-09-11 실측):
    // - `-p`/`--print` 는 프롬프트를 값으로 받는 print 모드. 기본 print-timeout 이 5분이라
    //   `--print-timeout` 을 반드시 늘린다.
    // - `--output-format text` 는 완료 전까지 한 바이트도 내지 않아 AWO 의 무출력 제한(600초)에
    //   워커가 끊긴다(실측 2026-09-11: cf7b77c1, dc2b0b0a, 961e6e68, a4a11ec0).
    //   `stream-json` 은 t=0 에 init 이벤트를 즉시 내고 활동마다 이벤트를 흘려 무출력 타이머를
    //   리셋하므로 `stream-json` 이 정본이다 (`streaming-messages-json` 은 미지원이라 text 로 후퇴함).
    // - `--input-format text` 는 print 모드 stdin 계약의 기본값이지만, 헤드리스 기동임을
    //   명시해 stream-json 오해석 여지를 없앤다(stdin 은 여전히 text 계약).
    // - 방 exec 경로(stdin=/dev/null, TTY 없음)에서 이 형태로 exit 0 을 실측했다.
    //   'bubbletea: could not open TTY' 는 바이너리 문자열상 "Print mode: triggering
    //   interactive OAuth" 경로에서만 나온다 — 로그인 없는 환경이 원인이며 argv 로는
    //   막을 수 없다. `--dangerously-skip-permissions` 는 권한 TUI 진입을 막는다.
    private static func agyArgv(_ launch: RoomLaunch) -> [String] {
        guard let model = launch.model, !launch.promptText.isEmpty else { return [] }
        return [
            "agy", "-p", launch.promptText,
            "--model", model,
            "--dangerously-skip-permissions",
            "--input-format", "text",
            "--output-format", "stream-json",
            "--print-timeout", defaultAgyPrintTimeout
        ]
    }

    // grok (`grok --help`, 2026-09-09 실측):
    // - 위치 인수 PROMPT 는 **대화형** 세션의 첫 줄이다. AWO/방 exec 는 stdin=/dev/null
    //   이라 TUI 가 /dev/tty 를 열다 `Device not configured (os error 6)` 로 즉사한다.
    // - 헤드리스 단발은 `-p`/`--single <PROMPT>` 또는 `--prompt-file`. 파일이 있으면
    //   파일을 쓰고, 인라인 promptText 만 있으면 `-p` 를 쓴다(방 AgentToolInvocation 과 같음).
    private static func grokArgv(_ launch: RoomLaunch) -> [String] {
        let promptFile = launch.promptFile ?? ""
        let hasFile = !promptFile.isEmpty
        let hasText = !launch.promptText.isEmpty
        guard hasFile || hasText else { return [] }
        var argv = ["grok"]
        if let workdir = launch.workdir, !workdir.isEmpty {
            argv += ["--cwd", workdir]
        }
        // `json` 은 완료 전까지 한 바이트도 내지 않아 AWO 의 무출력 제한(600초)에
        // 워커가 끊긴다(실측 2026-09-10: 779줄 작성 중 컷). ProcessRunner 는
        // `streaming-messages-json` 의 tool_use 열림을 활동으로 세므로 이 형식이 정본이다.
        argv += [
            "--always-approve",
            "--output-format", "streaming-messages-json",
            "--max-turns", "200"
        ]
        if let model = launch.model, !model.isEmpty {
            argv += ["--model", model]
        }
        if hasFile {
            argv += ["--prompt-file", promptFile]
        } else {
            argv += ["-p", launch.promptText]
        }
        return argv
    }

    private static func claudeArgv(_ launch: RoomLaunch) -> [String] {
        guard !launch.promptText.isEmpty else { return [] }
        var argv = [
            "claude", "-p", launch.promptText,
            "--dangerously-skip-permissions",
            "--output-format", "text"
        ]
        if let model = launch.model, !model.isEmpty {
            argv += ["--model", model]
        }
        return argv
    }

    // codex-cli 0.147.0 (`codex exec --help`, 2026-09-06 실측):
    // - 비대화형은 `codex exec [OPTIONS] [PROMPT]`. 루트 `codex -p` 는
    //   `--profile <CONFIG_PROFILE_V2>` 라 'invalid --profile value' 로 즉사한다.
    // - PROMPT 는 마지막 위치 인수. `--prompt-file` 옵션은 없으므로 promptFile 만 있으면
    //   파일 본문을 읽어 위치 인수로 넘긴다(AWO 는 stdin 을 /dev/null 로 달아 `-` 불가).
    // - 승인: `--dangerously-bypass-approvals-and-sandbox`. help 문구대로 "externally
    //   sandboxed" 환경 전용인데, AWO 워커는 격리 worktree + 방 seatbelt 안에서 돌고
    //   claude/agy 도 같은 등급(`--dangerously-skip-permissions`)을 쓴다.
    //   `--approve-for-me` 는 workspace-write 샌드박스 안에서 자동 심사라 워크트리 밖
    //   (빌드 큐·상태 루트) 쓰기가 막혀 비대화형 완주가 보장되지 않는다.
    // - `--skip-git-repo-check`: workdir 가 git 밖(임시 디렉터리)이어도 즉사하지 않게.
    private static func codexArgv(_ launch: RoomLaunch) -> [String] {
        guard let prompt = codexPrompt(launch: launch) else { return [] }
        var argv = ["codex", "exec"]
        if let model = launch.model, !model.isEmpty {
            argv += ["--model", model]
        }
        if let workdir = launch.workdir, !workdir.isEmpty {
            argv += ["--cd", workdir]
        }
        argv += [
            "--dangerously-bypass-approvals-and-sandbox",
            "--skip-git-repo-check",
            prompt
        ]
        return argv
    }

    /// codex 위치 인수 프롬프트. promptText 우선, 없으면 promptFile 본문.
    /// 파일을 읽지 못하면 nil — 호출자는 빈 argv 로 받아 기동하지 않는다.
    static func codexPrompt(launch: RoomLaunch) -> String? {
        if !launch.promptText.isEmpty { return launch.promptText }
        guard let promptFile = launch.promptFile, !promptFile.isEmpty,
              let body = try? String(contentsOfFile: promptFile, encoding: .utf8),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return body
    }

    // cursor-agent (`cursor-agent --help`, 2026-09-17 실측):
    // - `-p`/`--print` 는 프롬프트를 값으로 받는 비대화형 print 모드.
    // - `--output-format stream-json` 은 t=0 에 init 이벤트를 내고 활동마다 이벤트를 흘려 무출력 타이머를 리셋한다.
    // - `-f`/`--force` 는 비대화형 완주를 위해 명령어 자동 승인.
    private static func cursorArgv(_ launch: RoomLaunch) -> [String] {
        let prompt: String
        if !launch.promptText.isEmpty {
            prompt = launch.promptText
        } else if let promptFile = launch.promptFile, !promptFile.isEmpty {
            guard let body = try? String(contentsOfFile: promptFile, encoding: .utf8),
                  !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return []
            }
            prompt = body
        } else {
            return []
        }
        var argv = [
            "cursor-agent",
            "-p", prompt,
            "--output-format", "stream-json",
            "-f"
        ]
        if let model = launch.model, !model.isEmpty {
            argv += ["--model", model]
        }
        return argv
    }

    /// 방 `exec` 용 argv 빌더 — `LaunchArgvBuilder.buildExecArgv` 와 호환
    public static func buildExecArgv(
        tool: AgentTool,
        promptFile: String,
        promptText: String?,
        model: String?,
        workdir: String?
    ) -> [String] {
        let launch = RoomLaunch(
            tool: tool,
            model: model,
            promptText: promptText ?? "",
            promptFile: promptFile,
            workdir: workdir
        )
        return build(launch: launch)
    }

    /// 사람이 읽기 위한 표시용 명령 문자열을 생성한다.
    /// 프롬프트 본문 자리를 `@<파일>` 형태로 축약한다.
    public static func displayCommand(
        argv: [String],
        promptText: String?,
        promptFile: String?
    ) -> String {
        guard let promptText, !promptText.isEmpty else {
            return argv.joined(separator: " ")
        }
        let replacement = promptFile.map { "@\($0)" } ?? "@prompt"
        return argv.map { $0 == promptText ? replacement : $0 }.joined(separator: " ")
    }

    public static func displayCommand(launch: RoomLaunch, argv: [String]) -> String {
        displayCommand(
            argv: argv,
            promptText: launch.promptText,
            promptFile: launch.promptFile
        )
    }

    /// `agent-room-terminal open` 호출을 위한 argv 생성 (기본 오버로드)
    public static func buildOpenArgv(
        roomID: UUID,
        tool: AgentTool,
        preset: RoomWallPreset? = nil
    ) -> [String] {
        buildOpenArgv(roomID: roomID, specURL: nil, tool: tool, preset: preset, json: false)
    }

    /// `agent-room-terminal open` 호출을 위한 argv 생성 (확장 파라미터 지원)
    public static func buildOpenArgv(
        roomID: UUID? = nil,
        specURL: URL? = nil,
        tool: AgentTool? = nil,
        preset: RoomWallPreset? = nil,
        json: Bool = false
    ) -> [String] {
        var argv = ["agent-room-terminal", "open"]
        if let specURL {
            argv += ["--spec", specURL.path]
        } else if let roomID {
            argv.append(roomID.uuidString)
        }
        if let tool {
            argv += ["--tool", tool.rawValue, "--execute"]
        }
        if let preset {
            argv += ["--preset", preset.rawValue]
        }
        if json {
            argv.append("--json")
        }
        return argv
    }

    /// `agent-room-terminal open … --json` 결과에서 `result.path` 를 파싱한다.
    public static func parseOpenPath(from data: Data) -> (path: String?, note: String?) {
        let rawJSON: Any
        do {
            rawJSON = try JSONSerialization.jsonObject(with: data)
        } catch {
            return (nil, "open 출력 파싱 실패: 유효한 JSON이 아님")
        }
        guard let json = rawJSON as? [String: Any] else {
            return (nil, "open 출력 파싱 실패: 최상위 객체가 아님")
        }
        guard let ok = json["ok"] as? Bool, ok else {
            let err = json["error"] as? String ?? "알 수 없는 오류"
            return (nil, "agent-room-terminal open 실패: \(err)")
        }
        guard let result = json["result"] as? [String: Any],
              let path = result["path"] as? String,
              !path.isEmpty else {
            return (nil, "agent-room-terminal open 결과에 result.path 없음")
        }
        return (path, nil)
    }
}
