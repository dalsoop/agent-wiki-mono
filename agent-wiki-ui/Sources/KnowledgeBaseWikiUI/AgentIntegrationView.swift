import AgentSurfaceKit
import KnowledgeBaseWikiCore
import SwiftUI

/// 에이전트 연동 설정 — Claude Code 훅 / Codex 규약 / agent-wiki surface 스킬을
/// 앱에서 점검·설치·제거한다. orca agent-hooks 관례를 따른다:
/// 존재-가드된 명령, fail-open(연동이 없어도 세션을 절대 막지 않음), 쓰기 전 백업.
@MainActor @Observable
final class AgentIntegration {
    static let hintScript = NSString(string: "~/.codex/tools/gujo-wiki-session-hint.sh").expandingTildeInPath
    static let claudeSettings = NSString(string: "~/.claude/settings.json").expandingTildeInPath
    static let codexAgents = NSString(string: "~/.codex/AGENTS.md").expandingTildeInPath
    static let codexSkill = NSString(string: "~/.codex/skills/agent-wiki").expandingTildeInPath
    static let claudeSkill = NSString(string: "~/.claude/skills/agent-wiki").expandingTildeInPath
    static let wikiRecordCodex = NSString(string: "~/.codex/skills/wiki-record").expandingTildeInPath
    static let hookCommand = "bash \"$HOME/.codex/tools/gujo-wiki-session-hint.sh\" 2>/dev/null || true"
    static let opencodeAgents = NSString(string: "~/.config/opencode/AGENTS.md").expandingTildeInPath
    static let opencodeConfig = NSString(string: "~/.config/opencode/opencode.json").expandingTildeInPath

    var scriptInstalled = false
    var claudeHookInstalled = false
    var codexRuleInstalled = false
    var codexSkillInstalled = false
    var claudeSkillLinked = false
    var wikiRecordInstalled = false
    var surfaceInstalledCount = 0
    var surfaceMissing: [String] = []
    var opencodeRuleInstalled = false
    var opencodePermissionInstalled = false
    var message: String?

    func refresh() {
        let fm = FileManager.default
        scriptInstalled = fm.isExecutableFile(atPath: Self.hintScript)
        claudeHookInstalled = (try? String(contentsOfFile: Self.claudeSettings, encoding: .utf8))?
            .contains("gujo-wiki-session-hint.sh") ?? false
        codexRuleInstalled = (try? String(contentsOfFile: Self.codexAgents, encoding: .utf8))?
            .contains("조회(원장 우선)") ?? false
        codexSkillInstalled = fm.fileExists(atPath: Self.codexSkill + "/SKILL.md")
        var isDir: ObjCBool = false
        claudeSkillLinked = fm.fileExists(atPath: Self.claudeSkill, isDirectory: &isDir)
        wikiRecordInstalled = fm.fileExists(atPath: Self.wikiRecordCodex + "/SKILL.md")
        let st = AgentSurface.status()
        surfaceInstalledCount = st.installed.count
        surfaceMissing = st.missing
        opencodeRuleInstalled = (try? String(contentsOfFile: Self.opencodeAgents, encoding: .utf8))?
            .contains("조회(원장 우선)") ?? false
        let openCfg = (try? String(contentsOfFile: Self.opencodeConfig, encoding: .utf8)) ?? ""
        opencodePermissionInstalled = openCfg.contains("agent-wiki search*")
            || openCfg.contains("memo-citation-ledger search*")
    }

    func attachSurface() {
        do {
            let r = try AgentSurface.attach()
            if r.errors.isEmpty {
                message = "agent-wiki 스킬 부착 \(r.attached.count) paths"
            } else {
                message = "부분 실패: \(r.errors.joined(separator: "; "))"
            }
            refresh()
        } catch {
            message = "실패: \(error.localizedDescription)"
        }
    }

    func detachSurface() {
        do {
            let r = try AgentSurface.detach()
            message = r.errors.isEmpty
                ? "스킬 부착 해제 \(r.attached.count)"
                : "해제 오류: \(r.errors.joined(separator: "; "))"
            refresh()
        } catch {
            message = "실패: \(error.localizedDescription)"
        }
    }

    /// opencode 전역 규칙 + 읽기 전용 조회 명령 자동 허용 설치 (백업 후 수정).
    func installOpencode() {
        do {
            let fm = FileManager.default
            let configDir = (Self.opencodeAgents as NSString).deletingLastPathComponent
            guard fm.fileExists(atPath: configDir) else {
                message = "opencode 미설치 (~/.config/opencode 없음)"; return
            }
            if !opencodeRuleInstalled {
                let rules = """
                # 전역 규칙 — Agent Wiki 원장 우선

                제품은 **Agent Wiki**(CLI `agent-wiki`). 데이터 경로 world gujo-wiki · ~/gujo-wiki.
                구조위키·Knowledge Base Wiki 호칭 금지. 과거 결정·런북·시스템 지식은
                파일 grep·웹 검색 전에 `agent-wiki --world gujo-wiki context \"<질문>\"` /
                `search` / `path` / `show` 로 조회(원장 우선)한다.
                기록은 wiki-record 규약(~/.codex/skills/wiki-record) → agent-wiki publish,
                발행 id + verify 로 검증한다. secret 원문은 원장에 쓰지 않는다.
                (별칭 memo-citation-ledger / knowledge-base-wiki 도 동일 바이너리)
                """
                try Data(rules.utf8).write(to: URL(fileURLWithPath: Self.opencodeAgents))
            }
            if !opencodePermissionInstalled {
                let url = URL(fileURLWithPath: Self.opencodeConfig)
                let data = try Data(contentsOf: url)
                try data.write(to: URL(fileURLWithPath: Self.opencodeConfig + ".bak"))
                guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      var permission = root["permission"] as? [String: Any],
                      var bash = permission["bash"] as? [String: Any] else {
                    message = "opencode.json 파싱 실패"; return
                }
                for command in ["search", "context", "path", "list", "show", "history", "cited-by"] {
                    bash["agent-wiki \(command)*"] = "allow"
                    bash["memo-citation-ledger \(command)*"] = "allow" // 호환 별칭
                }
                bash["agent-wiki verify"] = "allow"
                bash["agent-wiki root"] = "allow"
                bash["agent-wiki --world*"] = "allow"
                bash["agent-wiki skill-status"] = "allow"
                bash["agent-wiki dual-entry*"] = "allow"
                bash["memo-citation-ledger verify"] = "allow"
                bash["memo-citation-ledger root"] = "allow"
                permission["bash"] = bash
                root["permission"] = permission
                let out = try JSONSerialization.data(
                    withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
                try out.write(to: url)
            }
            message = "opencode 설치됨 (백업: opencode.json.bak)"
            refresh()
        } catch {
            message = "실패: \(error.localizedDescription)"
        }
    }

    /// Claude Code SessionStart 훅 등록/해제 — settings.json 을 백업 후 수정.
    func setClaudeHook(_ enable: Bool) {
        do {
            let url = URL(fileURLWithPath: Self.claudeSettings)
            let data = try Data(contentsOf: url)
            try data.write(to: URL(fileURLWithPath: Self.claudeSettings + ".bak"))
            guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                message = "settings.json 파싱 실패"; return
            }
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            var sessionStart = hooks["SessionStart"] as? [[String: Any]] ?? []
            sessionStart.removeAll { entry in
                ((entry["hooks"] as? [[String: Any]]) ?? []).contains {
                    ($0["command"] as? String)?.contains("gujo-wiki-session-hint") == true
                }
            }
            if enable {
                sessionStart.append([
                    "matcher": "*",
                    "hooks": [["type": "command", "command": Self.hookCommand,
                               "timeout": 10, "statusMessage": "gujo wiki 지침 주입"]],
                ])
            }
            hooks["SessionStart"] = sessionStart
            root["hooks"] = hooks
            let out = try JSONSerialization.data(
                withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try out.write(to: url)
            message = enable ? "훅 등록됨 (백업: settings.json.bak)" : "훅 해제됨"
            refresh()
        } catch {
            message = "실패: \(error.localizedDescription)"
        }
    }
}

struct AgentIntegrationView: View {
    @State private var integration = AgentIntegration()

    var body: some View {
        Form {
            Section("세션 훅 — 원장 우선 조회 (graph-first)") {
                statusRow("주입 스크립트 (gujo-wiki-session-hint.sh)", ok: integration.scriptInstalled,
                          detail: integration.scriptInstalled ? "실행 가능" : "없음 — 재설치 필요")
                HStack {
                    statusLabel("Claude Code SessionStart 훅", ok: integration.claudeHookInstalled)
                    Spacer()
                    Button(integration.claudeHookInstalled ? "해제" : "등록") {
                        integration.setClaudeHook(!integration.claudeHookInstalled)
                    }
                    .disabled(!integration.scriptInstalled && !integration.claudeHookInstalled)
                }
                statusRow("Codex AGENTS.md 조회 규약", ok: integration.codexRuleInstalled,
                          detail: integration.codexRuleInstalled
                              ? "'조회(원장 우선)' 절 있음" : "~/.codex/AGENTS.md 에 규약 없음")
            }
            Section("스킬 — agent-wiki (앱 surface)") {
                statusRow("Codex (~/.codex/skills/agent-wiki)", ok: integration.codexSkillInstalled,
                          detail: integration.codexSkillInstalled ? "SKILL.md 있음" : "없음")
                statusRow("Claude (~/.claude/skills/agent-wiki)", ok: integration.claudeSkillLinked,
                          detail: integration.claudeSkillLinked ? "있음" : "없음")
                statusRow("surface 부착", ok: integration.surfaceMissing.isEmpty && integration.surfaceInstalledCount > 0,
                          detail: integration.surfaceMissing.isEmpty
                              ? "\(integration.surfaceInstalledCount) paths"
                              : "missing: \(integration.surfaceMissing.joined(separator: ", "))")
                HStack {
                    Button("부착 (skill-install)") { integration.attachSurface() }
                    Button("해제") { integration.detachSurface() }
                }
                statusRow("wiki-record (발행 전용, 별 스킬)", ok: integration.wikiRecordInstalled,
                          detail: integration.wikiRecordInstalled ? "host-skills" : "없음")
            }
            Section("opencode") {
                statusRow("전역 규칙 (~/.config/opencode/AGENTS.md)", ok: integration.opencodeRuleInstalled,
                          detail: integration.opencodeRuleInstalled ? "'조회(원장 우선)' 절 있음" : "없음")
                HStack {
                    statusLabel("조회 명령 자동 허용 (opencode.json)", ok: integration.opencodePermissionInstalled)
                    Spacer()
                    if !integration.opencodeRuleInstalled || !integration.opencodePermissionInstalled {
                        Button("설치") { integration.installOpencode() }
                    }
                }
            }
            Section("온보딩") {
                Text("첫 실행 시 CLI · 스킬 surface · dual-entry 상태를 안내합니다. 다시 볼 수 있습니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("온보딩 다시 보기…") {
                    NotificationCenter.default.post(name: .agentWikiShowWelcomeOnboarding, object: nil)
                }
            }
            Section {
                Text("규약: 훅은 fail-open — CLI 나 원장이 없으면 조용히 통과해 세션을 막지 않는다. settings.json 수정은 항상 .bak 백업 후 수행.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = integration.message {
                    Text(message).font(.caption).foregroundStyle(.blue)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { integration.refresh() }
    }

    private func statusLabel(_ title: String, ok: Bool) -> some View {
        Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundStyle(ok ? Color.primary : .secondary)
            .symbolRenderingMode(.multicolor)
    }

    private func statusRow(_ title: String, ok: Bool, detail: String) -> some View {
        HStack {
            statusLabel(title, ok: ok)
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.tertiary)
        }
    }
}
