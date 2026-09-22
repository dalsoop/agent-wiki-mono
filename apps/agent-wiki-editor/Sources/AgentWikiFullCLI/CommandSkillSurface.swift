import AgentSurfaceKit
import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// skill-install | skill-uninstall | skill-status — coding-agent surface (원장 불필요).
func runSkillSurface(arguments: [String]) {
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
        print("""
        사용법: agent-wiki skill-install|skill-uninstall|skill-status [--json]
               agent-wiki skill install|uninstall|status [--json]
        """)
        exit(0)
    }
    let json = rest.contains("--json") || rest.contains("-j")
    let action: String = {
        switch cmd {
        case "skill-install": return "install"
        case "skill-uninstall": return "uninstall"
        case "skill-status": return "status"
        case "skill", "skills":
            let pos = rest.filter { !$0.hasPrefix("-") }
            return pos.first ?? "status"
        default:
            return "status"
        }
    }()
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
            fail("""
            사용법: agent-wiki skill-install|skill-uninstall|skill-status [--json]
                   agent-wiki skill install|uninstall|status [--json]
            """)
        }
    } catch {
   fail(CLILocalization.format("CommandSkillSurface.string", "\(error)"))
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
                    "source": rec.source as Any,
                ] as [String: Any]
            },
            "skipped": r.skipped,
            "errors": r.errors,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } catch {}
        return
    }
    if r.errors.isEmpty {
        print("\(label) OK (\(r.attached.count) paths)")
        for a in r.attached {
            print("  \(a.homeId): \(a.path) (\(a.mode))")
        }
        for s in r.skipped { print("  skip: \(s)") }
    } else {
        print("\(label) FAIL")
        for e in r.errors { print("  - \(e)") }
        for a in r.attached { print("  ok: \(a.homeId) \(a.path)") }
    }
}

private func emitSkillStatus(_ st: AgentSurfaceRules.Status, json: Bool) {
    if json {
        let obj: [String: Any] = [
            "ok": st.missing.isEmpty,
            "presentHomes": st.presentHomes,
            "installed": st.installed.map { ["skill": $0.skill, "home": $0.homeId, "path": $0.path, "mode": $0.mode] },
            "missing": st.missing,
            "manifestOwner": st.manifest?.ownerCLI as Any,
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } catch {}
        return
    }
    print("skill-status")
    print("  homes: \(st.presentHomes.joined(separator: ", "))")
    if st.installed.isEmpty {
        print("  installed: (none)")
    } else {
        for a in st.installed {
            print("  \(a.skill) @ \(a.homeId): \(a.path) (\(a.mode))")
        }
    }
    if !st.missing.isEmpty {
        print("  missing: \(st.missing.joined(separator: ", "))")
    }
}
