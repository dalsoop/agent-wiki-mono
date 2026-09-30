import Foundation
import KnowledgeBaseWikiCore

/// dual-entry 자가진단 — PATH 가 GUI 를 가리키면 비정상 종료.
/// 에이전트/훅/doctor 가 재발 전에 잡도록 `version` 과 같은 원장-무관 경로.
public func runDualEntry(arguments: [String]) {
    let diag = DualEntry.diagnose()
    let json = arguments.contains("--json")
    if json {
        var obj: [String: Any] = [
            "ok": diag.ok,
            "issues": diag.issues,
            "version": LedgerVersion.current,
        ]
        if let path = diag.path { obj["path"] = path }
        if let stamp = diag.stamp { obj["stamp"] = stamp }
        do {
            let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else { return }
            print(text) // allow:debug
        } catch {
            fputs("json serialize failed: \(error)\n", stderr)
        }
    } else {
        if diag.ok {
            print("dual-entry OK") // allow:debug
            if let path = diag.path { print("  cli: \(path)") } // allow:debug
            if let stamp = diag.stamp { print("  stamp: \(stamp)") } // allow:debug
            print("  version: \(LedgerVersion.current)") // allow:debug
        } else {
            print("dual-entry FAIL") // allow:debug
            for issue in diag.issues {
                print("  - \(issue)") // allow:debug
            }
            print("fix:") // allow:debug
            print("  app-build-manager ship <앱>   # PATH 연결은 배포 도구가 유일한 쓰기 주체") // allow:debug
            print("Never: ln -s …/MacOS/KnowledgeBaseWiki /opt/homebrew/bin/agent-wiki") // allow:debug
        }
    }
    exit(diag.ok ? 0 : 2)
}
