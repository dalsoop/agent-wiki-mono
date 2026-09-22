import Foundation
import InteropKit
import AgentWikiStudioCore
import AppPathsKit
import LocalizationKit
import SingleInstanceKit
import CommandKit

@main
enum AgentWikiStudioCLIMain {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let cmd = args.first ?? "help"

        func usage() {
            print(
                """
                agent-wiki-studio — Agent Wiki 내부용 (발행·운영)

                full agent-wiki 프록시 + dual-entry 승계.
                Built-in: capabilities | version | help | open | status
                          dual-entry status|adopt [--dry-run] [--no-install]
                          list | search | show | task | promotion | publish | unpublish | archive | delete

                agent-wiki-studio status
                agent-wiki-studio dual-entry status
                agent-wiki-studio dual-entry status --json
                agent-wiki-studio dual-entry adopt --dry-run
                agent-wiki-studio list
                agent-wiki-studio search <query>
                agent-wiki-studio show <id>
                agent-wiki-studio task knowledge-candidate <task> <title>
                agent-wiki-studio promotion publish <id> --to gujo --confirm
                agent-wiki-studio publish --title <title>
                agent-wiki-studio unpublish <id>

                보고: agent-wiki-reader
                """
            )
        }

SingleInstanceCLI.autoGuard()

        switch cmd {
        case "help", "-h", "--help":
            usage()
        case "version", "-V", "--version":
            print("agent-wiki-studio 0.1.0-internal")
        case "status":
            print(await AgentWikiStudioService().status())
        case "dual-entry":
            runDualEntrySubcommand(Array(args.dropFirst()))
        case "list", "search", "show", "task", "promotion", "publish", "unpublish", "archive", "delete", "rollback":
            let r = await AgentWikiStudioService().forward(args: args)
            if !r.stdout.isEmpty {
                fputs(r.stdout.hasSuffix("\n") ? r.stdout : r.stdout + "\n", stdout)
            }
            if !r.stderr.isEmpty { fputs(r.stderr, stderr) }
            if r.exitCode != 0 { exit(r.exitCode) }
        case "capabilities":
            let caps = InteropKit.Capabilities(
                name: "agent-wiki-studio",
                version: CLIMarketingVersion.current(),
                cli: HostPlatform.cliBinPath("agent-wiki-studio"),
                commands: [
                    .init(name: "capabilities", summary: CLILocalization.string("main.string"), json: true),
                    .init(name: "help", summary: CLILocalization.string("main.string-2"), json: false),
                    .init(name: "status", summary: "world list", json: false),
                    .init(name: "version", summary: CLILocalization.string("main.string-3"), json: false),
                    .init(name: "open", summary: "GUI", json: false),
                    .init(name: "dual-entry", summary: CLILocalization.string("main.string-4"), json: true),
                    .init(name: "list", summary: "list wiki records", json: true),
                    .init(name: "search", summary: "search wiki records", json: true),
                    .init(name: "show", summary: "show wiki record", json: false),
                    .init(name: "task", summary: "canonical repository task workflow", json: true),
                    .init(name: "promotion", summary: "promotion preview|publish <id> --to gujo", json: true),
                    .init(name: "publish", summary: "publish wiki record (stdin body)", json: false),
                    .init(name: "unpublish", summary: "unpublish or retract wiki record", json: false),
                    .init(name: "archive", summary: "archive wiki record", json: false),
                    .init(name: "delete", summary: "delete or rollback wiki record", json: false),
                    .init(name: "rollback", summary: "rollback wiki record", json: false),
                ],
                state: [
                .init(
        path: DurableAppLayout.tildePath(DurableAppLayout.sqliteURL(slug: "agent-wiki-studio")),
        what: CLILocalization.string("main.string-5")
    ),
                    .init(
                        path: "~/.swift-app-state/agent-wiki-studio.json",
                        what: CLILocalization.string("main.string-6")
                    ),
                ],
                health: .init(
                    command: "\(HostPlatform.cliBinPath("agent-wiki-studio")) capabilities",
                    freshness: "~/.swift-app-state/agent-wiki-studio.json"
                ),
                depends: []
            )
            do {
                let data = try Envelope.ok(caps)
                print(String(data: data, encoding: .utf8) ?? "{}")
            } catch {
                fputs("warning: capabilities encode: \(error.localizedDescription)\n", stderr)
            }
        case "open":
            _ = await SafeProcessRunner.runAsync(
                executable: "/usr/bin/open",
                arguments: ["-a", "Agent Wiki Studio"]
            )
        default:
            let r = await AgentWikiStudioService().forward(args: args)
            if !r.stdout.isEmpty {
                fputs(r.stdout.hasSuffix("\n") ? r.stdout : r.stdout + "\n", stdout)
            }
            if !r.stderr.isEmpty { fputs(r.stderr, stderr) }
            if r.exitCode != 0 { exit(r.exitCode) }
        }
    }

    /// dual-entry status | adopt [--dry-run] [--no-install] [--json]
    static func runDualEntrySubcommand(_ args: [String]) {
        let parsed = parseDualEntryArgs(args)
        switch parsed.sub {
        case "status":
            emitDualEntryStatus(json: parsed.json)
        case "adopt":
            emitDualEntryAdopt(dryRun: parsed.dryRun, runPathInstall: !parsed.noInstall, json: parsed.json)
        default:
            fputs("usage: agent-wiki-studio dual-entry status|adopt [--dry-run] [--no-install] [--json]\n", stderr)
            exit(64)
        }
    }

    private struct DualEntryParsed {
        var sub: String
        var json: Bool
        var dryRun: Bool
        var noInstall: Bool
    }

    private static func dualEntryUsage() -> String {
        """
        agent-wiki-studio dual-entry status [--json]
        agent-wiki-studio dual-entry adopt [--dry-run] [--no-install] [--json]
        """
    }

    private static func parseDualEntryArgs(_ args: [String]) -> DualEntryParsed {
        let allowed: Set<String> = ["--json", "--dry-run", "--no-install", "--help", "-h"]
        if let first = args.first, first == "help" || first == "--help" || first == "-h" {
            print(dualEntryUsage())
            exit(0)
        }
        var parsed = DualEntryParsed(sub: "status", json: false, dryRun: false, noInstall: false)
        var sawSub = false
        for a in args {
            if a.hasPrefix("-") {
                guard allowed.contains(a) else {
                    fputs("error: unknown option(s): \(a)\n", stderr)
                    fputs("Run with: agent-wiki-studio dual-entry --help\n", stderr)
                    exit(64)
                }
                switch a {
                case "--json": parsed.json = true
                case "--dry-run": parsed.dryRun = true
                case "--no-install": parsed.noInstall = true
                case "--help", "-h":
                    print(dualEntryUsage())
                    exit(0)
                default: break
                }
                continue
            }
            if !sawSub {
                parsed.sub = a
                sawSub = true
            }
        }
        return parsed
    }

    private static func emitDualEntryStatus(json: Bool) {
        let st = DualEntryAdoption.status()
        if json {
            let obj: [String: Any] = [
                "adopted": st.adopted,
                "readyToAdopt": st.readyToAdopt,
                "checklist": st.checklist,
                "paths": [
                    "monlithHelper": st.paths.monlithHelper as Any,
                    "studioHelper": st.paths.studioHelper as Any,
                    "pathCLI": st.paths.pathCLI as Any,
                    "studioApp": st.paths.studioApp as Any,
                    "monlithApp": st.paths.monlithApp as Any,
                ],
            ]
            do {
                let data = try Envelope.okObject(obj)
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            } catch {
                fputs("warning: dual-entry status encode: \(error.localizedDescription)\n", stderr)
            }
        } else {
            print(st.adopted ? "dual-entry ADOPTED (Studio surface)" : "dual-entry not yet Studio")
            print("  readyToAdopt: \(st.readyToAdopt)")
            for (k, v) in st.checklist.sorted(by: { $0.key < $1.key }) {
                print("  [\(v ? "x" : " ")] \(k)")
            }
            if let p = st.paths.monlithHelper { print("  monlith: \(p)") }
            if let p = st.paths.studioHelper { print("  studio:  \(p)") }
            if let p = st.paths.pathCLI { print("  PATH:    \(p)") }
        }
        exit(st.adopted ? 0 : 2)
    }

    private static func emitDualEntryAdopt(dryRun: Bool, runPathInstall: Bool, json: Bool) {
        let r = DualEntryAdoption.adopt(dryRun: dryRun, runPathInstall: runPathInstall)
        if json {
            let obj: [String: Any] = [
                "ok": r.ok,
                "message": r.message,
                "studioHelper": r.studioHelper as Any,
                "pathCLI": r.pathCLI as Any,
                "dryRun": r.dryRun,
            ]
            do {
                let data = try JSONSerialization.data(
                    withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]
                )
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            } catch {
                fputs("warning: dual-entry adopt encode: \(error.localizedDescription)\n", stderr)
            }
        } else {
            print(r.ok ? "OK \(r.message)" : "FAIL \(r.message)")
        }
        exit(r.ok ? 0 : 1)
    }
}
