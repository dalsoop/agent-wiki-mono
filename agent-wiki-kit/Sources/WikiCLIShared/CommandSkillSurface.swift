import AgentSurfaceKit
import Foundation
import KnowledgeBaseWikiCore

private let skillSurfaceUsage = """
사용법: agent-wiki skill-install|skill-uninstall|skill-status [--json]
       agent-wiki skill install|uninstall|status [--json]
"""

private func resolveSkillAction(cmd: String, positionalArgs: [String]) -> String {
    switch cmd {
    case "skill-install": return "install"
    case "skill-uninstall": return "uninstall"
    case "skill-status": return "status"
    case "skill", "skills":
        return positionalArgs.first ?? "status"
    default:
        return "status"
    }
}

/// skill-install | skill-uninstall | skill-status — coding-agent surface (원장 불필요).
public func runSkillSurface(arguments: [String]) {
    let cmd = arguments.first ?? ""
    let rest = Array(arguments.dropFirst())
    let allowedOptions: Set<String> = ["--json", "--help", "-h", "-j"]
    let optionArgs = rest.filter { $0.hasPrefix("-") && $0 != "-" }
    let unknown = Set(optionArgs).subtracting(allowedOptions)
    if !unknown.isEmpty {
        let names = unknown.sorted().joined(separator: ", ")
        FileHandle.standardError.write(Data("error: unknown option(s): \(names)\nRun with --help for usage.\n".utf8))
        exit(64)
    }
    if rest.contains("--help") || rest.contains("-h") || CLIArgv.isHelpToken(cmd) {
        print(skillSurfaceUsage) // allow:debug
        exit(0)
    }
    let json = rest.contains("--json") || rest.contains("-j")
    let positionalArgs = rest.filter { !$0.hasPrefix("-") }
    let action = resolveSkillAction(cmd: cmd, positionalArgs: positionalArgs)
    let isDestructive = ["install", "attach", "uninstall", "detach", "remove"].contains(action)
    if isDestructive, rest.contains(where: { $0 == "--help" || $0 == "-h" }) {
        print(skillSurfaceUsage) // allow:debug
        exit(0)
    }
    do {
        switch action {
        case "install", "attach":
            let r = try AgentSurface.attach()
            emitSkillResult(r, json: json, label: "skill-install")
            exit(r.errors.isEmpty ? 0 : 1)
        case "uninstall", "detach", "remove":
            let r = try AgentSurface.detach()
            emitSkillResult(r, json: json, label: "skill-uninstall")
            exit(r.errors.isEmpty ? 0 : 1)
        case "status", "list":
            emitSkillStatus(AgentSurface.status(), json: json)
            exit(0)
        default:
            fail(skillSurfaceUsage)
        }
    } catch {
        fail("skill surface 실패: \(error)")
    }
}

private func emitSkillResult(_ r: AgentSurfaceRules.AttachResult, json: Bool, label: String) {
    if json {
        let obj: [String: Any] = [
            "ok": r.errors.isEmpty,
            "command": label,
            "attached": r.attached.map { rec in
                [
                    "skill": rec.skill,
                    "home": rec.homeId,
                    "path": rec.path,
                    "mode": rec.mode,
                    "source": rec.source ?? NSNull(),
                ] as [String: Any]
            },
            "skipped": r.skipped,
            "errors": r.errors,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            if let text = String(data: data, encoding: .utf8) { print(text) } // allow:debug
        } catch {
            fputs("json serialize failed: \(error)\n", stderr)
        }
        return
    }
    if r.errors.isEmpty {
        print("\(label) OK (\(r.attached.count) paths)") // allow:debug
        for a in r.attached {
            print("  \(a.homeId): \(a.path) (\(a.mode))") // allow:debug
        }
        for s in r.skipped { print("  skip: \(s)") } // allow:debug
    } else {
        print("\(label) FAIL") // allow:debug
        for e in r.errors { print("  - \(e)") } // allow:debug
        for a in r.attached { print("  ok: \(a.homeId) \(a.path)") } // allow:debug
    }
}

private func emitSkillStatus(_ st: AgentSurfaceRules.Status, json: Bool) {
    if json {
        let obj: [String: Any] = [
            "ok": st.missing.isEmpty,
            "presentHomes": st.presentHomes,
            "installed": st.installed.map { ["skill": $0.skill, "home": $0.homeId, "path": $0.path, "mode": $0.mode] },
            "missing": st.missing,
            "manifestOwner": st.manifest?.ownerCLI ?? NSNull(),
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            if let text = String(data: data, encoding: .utf8) { print(text) } // allow:debug
        } catch {
            fputs("json serialize failed: \(error)\n", stderr)
        }
        return
    }
    print("skill-status") // allow:debug
    print("  homes: \(st.presentHomes.joined(separator: ", "))") // allow:debug
    if st.installed.isEmpty {
        print("  installed: (none)") // allow:debug
    } else {
        for a in st.installed {
            print("  \(a.skill) @ \(a.homeId): \(a.path) (\(a.mode))") // allow:debug
        }
    }
    if !st.missing.isEmpty {
        print("  missing: \(st.missing.joined(separator: ", "))") // allow:debug
    }
}
