import Foundation
import AgentSessionKit

/// 세션 로그 한 건에서 **호출 신호**(도구·스킬·서브에이전트·사고)를 센다.
///
/// 왜 AgentSessionKit 의 `digest` 로 안 되나 — digest 는 인수인계 팩용 증류라 `files` 와
/// `commands` 까지만 준다. 이 앱이 필요한 도구 히스토그램·스킬 호출·서브에이전트 스폰,
/// 그리고 그 직전 **사고**는 거기 없다(digest 는 thinking 을 명시적으로 버린다).
/// 그래서 파서를 새로 만들지 않고 같은 kit 의 공개 원시함수(`JSONLine.forEachLine`)로
/// 곁가지 한 패스를 더 돈다. 세션 포맷 지식의 정본은 여전히 AgentSessionKit 이다.
public struct SessionScan: Sendable {
    public var tools: [String: Int] = [:]
    /// 스킬·서브에이전트 활성화를 **순서대로**. 이름 집합이 아니라 이벤트 열이다.
    public var activations: [Activation] = []
    /// 파서가 못 읽은 이벤트 — 포맷 드리프트 감지용.
    public var unknown: [String: Int] = [:]

    public init() {}

    public var skills: [String] { unique(activations.filter { $0.kind == .skill }.map(\.name)) }
    public var subagents: [String] { unique(activations.filter { $0.kind == .subagent }.map(\.name)) }

    private func unique(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        return xs.filter { seen.insert($0).inserted }
    }

    /// 한 패스의 가변 상태. 런타임별 흡수 함수들이 이걸 공유한다.
    struct ScanState {
        var scan = SessionScan()
        var index = 0
        /// 가장 최근 사고 블록. 활성화가 나오면 "왜 불렀나"의 근거로 붙인다.
        var lastThought: String?
        /// 이미 센 도구 호출. codex 로그는 compaction 사본에 같은 호출을 여러 번 싣고, grok 은
        /// 한 호출이 상태·내용 갱신으로 수십 번 다시 실린다 — id 로 접지 않으면 부풀어 오른다(실측).
        var countedCalls = Set<String>()

        mutating func activate(_ kind: Activation.Kind, _ name: String?, path: String? = nil,
                               source: Activation.Source = .invoked) {
            guard let name, !name.isEmpty else { return }
            scan.activations.append(Activation(kind: kind, name: name, at: index,
                                               thought: lastThought, mdPath: path, source: source))
            lastThought = nil   // 한 사고를 여러 호출에 중복해 붙이지 않는다.
        }

        /// 처음 보는 호출 id 면 true. id 가 없으면 접을 수 없으니 매번 센다.
        mutating func countOnce(_ callID: String) -> Bool {
            countedCalls.insert(callID).inserted || callID.isEmpty
        }

        mutating func countTool(_ name: String) {
            scan.tools[name, default: 0] += 1
        }

        /// 도구 호출 본문에서 읽힌 SKILL.md 를 `loaded` 신호로 올린다.
        mutating func loadSkills(in text: String) {
            for skill in SessionScan.skillsLoaded(in: text) {
                activate(.skill, skill.name, path: skill.path, source: .loaded)
            }
        }
    }

    private static let scanTokensClaude: [Data] = [
        Data("tool_use".utf8), Data("thinking".utf8), Data("command-name".utf8)
    ]
    private static let scanTokensCodex: [Data] = [
        Data("reasoning".utf8), Data("function_call".utf8), Data("custom_tool_call".utf8),
        Data("message".utf8), Data("command-name".utf8)
    ]
    private static let scanTokensGrok: [Data] = [
        Data("tool_call".utf8), Data("tool_call_update".utf8), Data("agent_thought_chunk".utf8),
        Data("subagent_spawned".utf8), Data("hook_execution".utf8)
    ]

    public static func scan(_ ref: SessionRef, maxBytes: Int = 16 * 1024 * 1024) -> SessionScan {
        if ref.tool == .agy { return scanAntigravity(ref) }
        var state = ScanState()
        let tokens: [Data]
        switch ref.tool {
        case .claude: tokens = scanTokensClaude
        case .codex: tokens = scanTokensCodex
        case .grok: tokens = scanTokensGrok
        case .agy, .opencode, .cursor: tokens = []
        }
        JSONLine.forEachLine(path: ref.transcriptPath, maxBytes: maxBytes, matchingTokens: tokens) { line in
            state.index += 1
            switch ref.tool {
            case .claude: absorbClaude(line, &state)
            case .codex: absorbCodex(line, &state)
            case .grok: absorbGrok(line, &state)
            case .agy: break   // 위에서 갈라졌다.
            case .opencode, .cursor: break
            }
            return true
        }
        return state.scan
    }

    // MARK: - Antigravity

    /// steps 테이블에서 도구 호출 스텝의 type 값(실측).
    static let antigravityToolStepType = 132
    /// JSON 객체 시작 문자. 리터럴로 쓰면 lint 의 중괄호 계수기가 함수 경계를 잃는다.
    static let jsonObjectOpen = String(UnicodeScalar(0x7B))

    /// Antigravity 전사본은 sqlite steps 테이블이라 줄 단위 파서(JSONLine)로 읽히지 않는다.
    /// AntigravitySessionReader 의 문자열 run 추출로 도구 히스토그램·스킬 신호를 낸다.
    private static func scanAntigravity(_ ref: SessionRef) -> SessionScan {
        var s = SessionScan()
        for step in AntigravitySessionReader().steps(ref, types: [antigravityToolStepType]) {
            if let toolName = step.metadataStrings.first(where: {
                !$0.hasPrefix("call_") && !$0.hasPrefix(jsonObjectOpen)
            }) {
                s.tools[toolName, default: 0] += 1
            }
            let hasSkillMD = step.metadataStrings.contains { $0.contains("SKILL.md") }
                || step.payloadStrings.contains { $0.contains("SKILL.md") }
            if hasSkillMD {
                let text = (step.metadataStrings + step.payloadStrings).joined(separator: "\n")
                for skill in skillsLoaded(in: text) {
                    s.activations.append(Activation(kind: .skill, name: skill.name,
                                                    at: step.index, thought: nil, mdPath: skill.path,
                                                    source: .loaded))
                }
            }
        }
        return s
    }

    // MARK: - Claude

    private static func absorbClaude(_ line: [String: Any], _ st: inout ScanState) {
        guard let msg = line["message"] as? [String: Any] else { return }
        if let text = msg["content"] as? String {
            st.activate(.skill, commandName(in: text))
            return
        }
        for blk in (msg["content"] as? [[String: Any]] ?? []) {
            switch blk["type"] as? String {
            case "thinking":
                st.lastThought = JSONLine.string(blk["thinking"]).flatMap { summarize($0) }
            case "tool_use":
                absorbClaudeToolUse(blk, &st)
            case "text":
                if let t = JSONLine.string(blk["text"]) { st.activate(.skill, commandName(in: t)) }
            default:
                break
            }
        }
    }

    /// 스킬은 Skill 도구로 오기도 하고 사용자 메시지의 <command-name> 으로도 온다.
    private static func absorbClaudeToolUse(_ blk: [String: Any], _ st: inout ScanState) {
        let name = JSONLine.string(blk["name"]) ?? "?"
        st.countTool(name)
        let input = blk["input"] as? [String: Any] ?? [:]
        if name == "Skill" { st.activate(.skill, JSONLine.string(input["skill"])) }
        if name == "Agent" {
            st.activate(.subagent, JSONLine.string(input["subagent_type"]) ?? "general-purpose")
        }
    }

    // MARK: - Codex

    private static func absorbCodex(_ line: [String: Any], _ st: inout ScanState) {
        guard let payload = line["payload"] as? [String: Any] else { return }
        switch payload["type"] as? String {
        case "reasoning":
            st.lastThought = codexReasoning(payload).flatMap { summarize($0) }
        case "function_call", "custom_tool_call":
            absorbCodexToolCall(payload, &st)
        case "message":
            for part in (payload["content"] as? [[String: Any]] ?? []) {
                if let t = JSONLine.string(part["text"]) { st.activate(.skill, commandName(in: t)) }
            }
        default:
            break
        }
    }

    /// codex 에는 Skill 도구가 없다 — 스킬을 쓰려면 SKILL.md 를 셸로 읽는다.
    /// **도구 호출 레코드에서만** 뽑는다: 시스템 프롬프트에 실리는 스킬 카탈로그에도 같은 경로가
    /// 전부 들어 있어서, 텍스트까지 훑으면 설치된 모든 스킬이 "불렸다"로 뒤집힌다.
    private static func absorbCodexToolCall(_ payload: [String: Any], _ st: inout ScanState) {
        st.countTool(JSONLine.string(payload["name"]) ?? "?")
        let callID = JSONLine.string(payload["call_id"]) ?? JSONLine.string(payload["id"]) ?? ""
        guard st.countOnce(callID) else { return }
        let input = JSONLine.string(payload["input"]) ?? JSONLine.string(payload["arguments"]) ?? ""
        st.loadSkills(in: input)
    }

    // MARK: - Grok

    /// grok 로그는 ACP 봉투다: `{method:"session/update", params:{update:{…}}}`.
    /// 예전 분기는 최상위 `type` 만 봐서 실제로는 한 건도 안 맞았다(실측: grok 190세션 ·
    /// 도구 0 · 스킬 0). 봉투를 풀고 나서야 신호가 보인다.
    private static func absorbGrok(_ line: [String: Any], _ st: inout ScanState) {
        let update = ((line["params"] as? [String: Any])?["update"] as? [String: Any])
        let kind = JSONLine.string(update?["sessionUpdate"]) ?? JSONLine.string(line["type"])
        if let update, kind == "tool_call" || kind == "tool_call_update" {
            absorbGrokUpdateToolCall(update, kind: kind, &st)
            return
        }
        switch kind {
        case "agent_thought_chunk":
            st.lastThought = JSONLine.string(line["text"]).flatMap { summarize($0) }
        case "tool_call":
            absorbGrokLegacyToolCall(line, &st)
        case "subagent_spawned":
            st.activate(.subagent, JSONLine.string(line["agent"]) ?? JSONLine.string(line["name"]))
        case "hook_execution":
            st.countTool("hook")
        default:
            break
        }
    }

    private static func absorbGrokUpdateToolCall(_ update: [String: Any], kind: String?,
                                                 _ st: inout ScanState) {
        let callID = JSONLine.string(update["toolCallId"]) ?? ""
        if st.countOnce(callID), let text = jsonText(update) { st.loadSkills(in: text) }
        if kind == "tool_call", let title = JSONLine.string(update["title"]) ?? JSONLine.string(update["kind"]) {
            st.countTool(title)
        }
    }

    /// grok 도 Skill 도구가 없다 — codex 와 같은 모양으로 읽어서 쓴다.
    private static func absorbGrokLegacyToolCall(_ line: [String: Any], _ st: inout ScanState) {
        let name = JSONLine.string(line["name"])
            ?? JSONLine.string((line["input"] as? [String: Any])?["name"]) ?? "?"
        st.countTool(name)
        if let input = line["input"], let text = jsonText(input) { st.loadSkills(in: text) }
    }

    /// 도구 호출 본문을 문자열로. 직렬화 불가 값이면 nil — 그 호출은 스킬 신호 없이 지나간다.
    static func jsonText(_ object: Any) -> String? {
        do {
            return String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8)
        } catch {
            return nil  // NaN 등 JSON 이 못 담는 값 — 스캔은 계속.
        }
    }

    /// 명령 문자열에서 **읽히는 `SKILL.md` 경로**를 찾아 스킬 이름을 낸다.
    ///
    /// `Skill` 도구가 없는 런타임(codex·grok)에서 스킬을 쓴다는 건 곧 그 `SKILL.md` 를
    /// 컨텍스트로 읽는다는 뜻이다. 그래서 이게 유일한 관측 가능한 활성화 신호다.
    /// 호출자는 반드시 **도구 호출 레코드**에만 이걸 적용해야 한다 — 프롬프트 텍스트에는
    /// 스킬 카탈로그가 통째로 들어 있어서 전부 오탐이 된다.
    public static func skillsLoaded(in command: String) -> [(name: String, path: String?)] {
        guard command.contains("SKILL.md") else { return [] }
        var out: [(String, String?)] = []
        var seen = Set<String>()
        // `…/skills/<name>/SKILL.md` — 중간에 `(그룹)` 디렉터리가 끼기도 한다.
        for part in command.components(separatedBy: "SKILL.md").dropLast() {
            let segments = part.split(separator: "/").map(String.init)
            guard segments.count >= 2 else { continue }
            // JSON 안의 경로는 `\/` 로 이스케이프돼 오기도 한다 — 꼬리를 떼지 않으면
            // 스킬 이름이 `agent-browser\` 처럼 나온다(실측).
            let quotes = CharacterSet(charactersIn: "\\\"' ")
            let name = segments[segments.count - 1].trimmingCharacters(in: quotes)
            guard Self.isPlausibleSkillDirectoryName(name),
                  Self.looksLikeSkillPath(segments.dropLast()),
                  seen.insert(name).inserted else { continue }
            // **로그에 적힌 경로가 정답이다.** 이름으로 다시 찾으면 프로젝트 로컬 스킬을
            // 놓친다(실측: `WORKSPACE/.claude/skills/workspace-bare-worktrees` 를
            // 레포 cwd 기준으로는 못 찾아 "정의 못 찾음" 으로 떴다).
            let absolute = part.range(of: "/", options: .backwards).map {
                String(part[part.startIndex..<$0.upperBound])
            }
            let path = absolute
                .map { $0.replacingOccurrences(of: "\\/", with: "/") + "SKILL.md" }
                .flatMap { candidate -> String? in
                    guard let slash = candidate.range(of: "/") else { return nil }
                    let trimmed = String(candidate[slash.lowerBound...])
                    return trimmed.hasPrefix("/") ? trimmed : nil
                }
            out.append((name, path))
        }
        return out
    }

    /// 스킬 디렉터리 이름으로 그럴듯한가 — 식별자 문자만, 공백·따옴표·괄호 없음.
    ///
    /// Antigravity 전사본은 문서 본문이 통째로 문자열 run 으로 오므로, `SKILL.md` 앞 조각이
    /// 마크다운 한 줄(`AndroidAdbManager.app\`)`, 표 행)일 때가 있다. 그걸 스킬로 올리면
    /// 카탈로그 usage 에 문장이 섞인다(실측 2026-09-03). 이름 문법으로 거른다.
    static func isPlausibleSkillDirectoryName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 80, !name.hasPrefix("("), !name.hasPrefix(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// 경로 어딘가에 `skills` 디렉터리가 있어야 스킬 로드다 — `docs/foo/SKILL.md` 같은 문서 읽기와 구분.
    static func looksLikeSkillPath(_ parents: ArraySlice<String>) -> Bool {
        parents.contains { $0.lowercased().contains("skill") }
    }

    /// `<command-name>/foo</command-name>` 에서 스킬·슬래시 이름을 뽑는다.
    public static func commandName(in text: String) -> String? {
        guard let open = text.range(of: "<command-name>"),
              let close = text.range(of: "</command-name>", range: open.upperBound..<text.endIndex)
        else { return nil }
        let raw = String(text[open.upperBound..<close.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
    }

    /// Codex reasoning payload 는 summary/content 배열 중 하나에 텍스트를 담는다.
    public static func codexReasoning(_ payload: [String: Any]) -> String? {
        for key in ["summary", "content"] {
            for part in (payload[key] as? [[String: Any]] ?? []) {
                if let t = JSONLine.string(part["text"]), !t.isEmpty { return t }
            }
        }
        return JSONLine.string(payload["text"])
    }

    /// 사고를 한 줄로 줄인다. 전문 저장은 이 앱 일이 아니다 — 그건 세션 리플레이가 한다.
    /// 여기서는 "왜 불렀나"를 알아볼 정도면 충분하다.
    ///
    /// 비어 있으면 nil 을 준다. 사고 블록은 있는데 **본문이 없는 경우가 흔하다** —
    /// Claude 는 확장 사고를 서명만 남기고 지우고(실측 347블록 중 본문 있는 건 58, 17%),
    /// Codex 는 `encrypted_content` 로 암호화한다(1868블록 전부 본문 0). 빈 문자열을
    /// 그대로 담으면 "사고가 없었다"와 "못 읽는다"가 구별되지 않는다.
    public static func summarize(_ text: String, cap: Int = 160) -> String? {
        let flat = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty })
        guard let flat, !flat.isEmpty else { return nil }
        return flat.count <= cap ? flat : String(flat.prefix(cap)) + "…"
    }
}
