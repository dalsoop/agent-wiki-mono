import Foundation
import KnowledgeBaseWikiCore

/// dual-entry 자가진단 — PATH 가 GUI 를 가리키면 비정상 종료.
/// 에이전트/훅/doctor 가 재발 전에 잡도록 `version` 과 같은 원장-무관 경로.
func runDualEntry(arguments: [String]) {
    let diag = DualEntry.diagnose()
    let json = arguments.contains("--json")
    if json {
        let obj: [String: Any] = [
            "ok": diag.ok,
            "path": diag.path as Any,
            "stamp": diag.stamp as Any,
            "issues": diag.issues,
            "version": LedgerVersion.current,
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]
            )
            if let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } catch {
            fputs("warning: dual-entry json: \(error.localizedDescription)\n", stderr)
        }
    } else {
        if diag.ok {
            print("dual-entry OK")
            if let path = diag.path { print("  cli: \(path)") }
            if let stamp = diag.stamp { print("  stamp: \(stamp)") }
            print("  version: \(LedgerVersion.current)")
        } else {
            print("dual-entry FAIL")
            for issue in diag.issues {
                print("  - \(issue)")
            }
            print("fix:")
            print("  \"/Applications/Agent Wiki.app/Contents/Helpers/agent-wiki\" install")
            print("  # then surface → Studio:")
            print("  agent-wiki-studio dual-entry adopt")
            print("  # or: app-build-manager ship apps/knowledge-base-wiki-swift release")
            print("Never: ln -s …/MacOS/KnowledgeBaseWiki /opt/homebrew/bin/agent-wiki")
        }
    }
    exit(diag.ok ? 0 : 2)
}
