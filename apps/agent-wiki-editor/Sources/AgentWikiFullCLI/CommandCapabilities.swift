import Foundation
import InteropKit
import KnowledgeBaseWikiCore
import LocalizationKit

/// 앱 상호운용 계약(docs/app-interop-contract.md) — {ok,result} 봉투로 자기소개.
/// ship-app.sh 의 register_interop 이 이걸 읽어 ~/.agent-apps/registry.json 에 등록한다.
/// 원장을 열지 않고 즉답(5초 타임아웃 호출).
func runCapabilities() {
    let caps = Capabilities(
        name: "agent-wiki",
        version: LedgerVersion.current,
        cli: CommandLine.arguments[0],
        commands: capabilityCommands(),
        state: [
            .init(
                path: "~/.swift-app-state/agent-wiki.json",
                what: "app state summary (StateMirrorAdoption — observability mirror, not the source)"
            ),
            .init(
                path: "~/.swift-app-state/memo-citation-ledger.json",
                what: CLILocalization.string("CommandCapabilities.string")
            ),
        ],
        health: .init(command: "agent-wiki verify", freshness: "~/.memo-citation-ledger/config.json"),
        depends: capabilityDepends()
    )
    do {
        FileHandle.standardOutput.write(try Envelope.ok(caps))
    } catch {
        fputs("warning: capabilities encode: \(error.localizedDescription)\n", stderr)
    }
    print("")
}

private func capabilityCommands() -> [Capabilities.Command] {
    capabilityReadCommands() + capabilityWriteCommands() + capabilityOpsCommands()
}

private func capabilityReadCommands() -> [Capabilities.Command] {
    [
        .init(name: "help", summary: CLILocalization.string("CommandCapabilities.string-2"), json: false),
        .init(name: "version", summary: CLILocalization.string("CommandCapabilities.string-3"), json: false),
        .init(name: "publish", summary: CLILocalization.string("CommandCapabilities.string-4"), json: false),
        .init(name: "show", summary: CLILocalization.string("CommandCapabilities.string-5"), json: false),
        .init(name: "status", summary: CLILocalization.string("CommandCapabilities.string-6"), json: true),
        .init(name: "list", summary: CLILocalization.string("CommandCapabilities.string-7"), json: true),
        .init(name: "search", summary: CLILocalization.string("CommandCapabilities.string-8"), json: true),
        .init(name: "context", summary: CLILocalization.string("CommandCapabilities.string-9"), json: false),
        .init(name: "path", summary: CLILocalization.string("CommandCapabilities.string-10"), json: false),
        .init(name: "history", summary: CLILocalization.string("CommandCapabilities.string-11"), json: false),
        .init(name: "cited-by", summary: CLILocalization.string("CommandCapabilities.string-12"), json: false),
        .init(name: "verify", summary: CLILocalization.string("CommandCapabilities.string-13"), json: false),
        .init(name: "repository", summary: "agent-wiki repository summary [--path <repo>] --json", json: true),
        .init(name: "repository-summary", summary: CLILocalization.string("CommandCapabilities.string-14"), json: true),
        .init(name: "task", summary: "canonical repository task workflow", json: true),
        .init(name: "agent", summary: CLILocalization.string("CommandCapabilities.string-15"), json: false),
        .init(name: "agent run", summary: CLILocalization.string("CommandCapabilities.string-16"), json: false),
        .init(name: "agent role", summary: CLILocalization.string("CommandCapabilities.string-17"), json: true),
        .init(name: "agent sync", summary: CLILocalization.string("CommandCapabilities.string-18"), json: false),
        .init(name: "run", summary: CLILocalization.string("CommandCapabilities.string-19"), json: false),
        .init(name: "sync", summary: CLILocalization.string("CommandCapabilities.string-20"), json: false),
        .init(name: "evolve", summary: CLILocalization.string("CommandCapabilities.string-21"), json: false),
        .init(name: "role", summary: CLILocalization.string("CommandCapabilities.string-22"), json: true),
        .init(name: "chat", summary: CLILocalization.string("CommandCapabilities.string-23"), json: false),
    ]
}

private func capabilityWriteCommands() -> [Capabilities.Command] {
    [
        .init(name: "orchestration", summary: CLILocalization.string("CommandCapabilities.string-24"), json: true),
        .init(
            name: "orchestration adapter",
            summary: CLILocalization.string("CommandCapabilities.string-25"),
            json: true
        ),
        .init(
            name: "orchestration capsule",
            summary: "bounded runtime/dispatch/knowledge/rules/stale/gate context",
            json: true
        ),
        .init(
            name: "orchestration context",
            summary: CLILocalization.string("CommandCapabilities.string-26"),
            json: true
        ),
        .init(name: "promotion", summary: "promotion preview|publish <id> --to gujo [--confirm] --json", json: true),
        .init(name: "promote", summary: CLILocalization.string("CommandCapabilities.string-27"), json: true),
        .init(name: "recent", summary: CLILocalization.string("CommandCapabilities.string-28"), json: false),
        .init(name: "changes", summary: CLILocalization.string("CommandCapabilities.string-29"), json: false),
        .init(name: "world", summary: CLILocalization.string("CommandCapabilities.string-30"), json: false),
        .init(name: "world rm", summary: CLILocalization.string("CommandCapabilities.string-31"), json: false),
        .init(name: "fleet", summary: CLILocalization.string("CommandCapabilities.string-32"), json: true),
        .init(name: "pull", summary: CLILocalization.string("CommandCapabilities.string-33"), json: true),
        .init(name: "weight", summary: CLILocalization.string("CommandCapabilities.string-34"), json: true),
        .init(name: "capabilities", summary: CLILocalization.string("CommandCapabilities.string-35"), json: true),
        .init(name: "skill-install", summary: CLILocalization.string("CommandCapabilities.string-36"), json: true),
        .init(name: "skill-uninstall", summary: CLILocalization.string("CommandCapabilities.string-37"), json: true),
        .init(name: "skill-status", summary: CLILocalization.string("CommandCapabilities.string-38"), json: true),
        .init(name: "skill", summary: CLILocalization.string("CommandCapabilities.string-39"), json: true),
        .init(name: "skills", summary: CLILocalization.string("CommandCapabilities.string-40"), json: true),
    ]
}

private func capabilityOpsCommands() -> [Capabilities.Command] {
    [
        .init(name: "root", summary: CLILocalization.string("CommandCapabilities.string-41"), json: false),
        .init(name: "batch", summary: CLILocalization.string("CommandCapabilities.string-42"), json: false),
        .init(name: "classify", summary: CLILocalization.string("CommandCapabilities.string-43"), json: false),
        .init(name: "capture", summary: CLILocalization.string("CommandCapabilities.string-44"), json: false),
        .init(name: "rollback", summary: CLILocalization.string("CommandCapabilities.string-45"), json: false),
        .init(name: "policy", summary: CLILocalization.string("CommandCapabilities.string-46"), json: false),
        .init(name: "structure", summary: CLILocalization.string("CommandCapabilities.string-47"), json: false),
        .init(name: "migrate", summary: CLILocalization.string("CommandCapabilities.string-48"), json: false),
        .init(name: "checkpoint", summary: CLILocalization.string("CommandCapabilities.string-49"), json: false),
        .init(name: "okf-export", summary: CLILocalization.string("CommandCapabilities.string-50"), json: false),
        .init(name: "distill", summary: CLILocalization.string("CommandCapabilities.string-51"), json: false),
        .init(name: "review", summary: CLILocalization.string("CommandCapabilities.string-52"), json: false),
        .init(name: "tick", summary: CLILocalization.string("CommandCapabilities.string-53"), json: false),
        .init(name: "backup", summary: CLILocalization.string("CommandCapabilities.string-54"), json: false),
        .init(name: "index", summary: CLILocalization.string("CommandCapabilities.string-55"), json: false),
        .init(name: "discuss", summary: CLILocalization.string("CommandCapabilities.string-56"), json: false),
        .init(name: "learn", summary: CLILocalization.string("CommandCapabilities.string-57"), json: false),
        .init(name: "metrics", summary: CLILocalization.string("CommandCapabilities.string-58"), json: false),
        .init(name: "rules", summary: CLILocalization.string("CommandCapabilities.string-59"), json: false),
        .init(name: "diff", summary: CLILocalization.string("CommandCapabilities.string-60"), json: false),
        .init(name: "blob", summary: CLILocalization.string("CommandCapabilities.string-61"), json: false),
        .init(name: "event", summary: CLILocalization.string("CommandCapabilities.string-62"), json: false),
        .init(name: "graph", summary: CLILocalization.string("CommandCapabilities.string-63"), json: false),
        .init(name: "app", summary: CLILocalization.string("CommandCapabilities.string-64"), json: false),
    ]
}

private func capabilityDepends() -> [Capabilities.Dependency] {
    [
        .init(id: "system.curl", kind: Capabilities.DependencyKind.command, ref: "curl", required: true, why: "path in CommandPublish.swift"),
        .init(id: "system.ffmpeg", kind: Capabilities.DependencyKind.command, ref: "ffmpeg", required: true, why: "str in CommandPublish.swift"),
        .init(id: "cli.gujo", kind: Capabilities.DependencyKind.cli, ref: "gujo", required: false, why: "lit in main.swift"),
        .init(
            id: "system.launchctl",
            kind: Capabilities.DependencyKind.command,
            ref: "launchctl",
            required: true,
            why: "path in CommandSchedule.swift"
        ),
    ]
}
