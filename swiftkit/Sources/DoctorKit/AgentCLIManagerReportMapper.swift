import Foundation

enum AgentCLIManagerReportMapper {
    static func map(stdout: String, source: String) -> [DoctorFinding] {
        guard let data = stdout.data(using: .utf8),
              let obj = DoctorJSON.raw(from: data)
        else { return [] }

        // Accept either array of findings or {ok,result:{...}}
        if let arr = obj as? [[String: Any]] {
            return arr.compactMap { row in
                let status = (row["status"] as? String) ?? (row["kind"] as? String) ?? "issue"
                let name = (row["name"] as? String) ?? (row["cli"] as? String) ?? "?"
                let problem = (row["isProblem"] as? Bool)
                    ?? (status != "ok" && status != "healthy")
                guard problem else { return nil }
                return DoctorFinding(
                    category: .management,
                    severity: .warn,
                    body: .init(
                        subject: name,
                        title: "agent-cli-manager: \(status) — \(name)",
                        detail: (row["message"] as? String) ?? String(describing: row),
                        remedy: "agent-cli-manager check --all; path-cli-health repair-copies --apply"
                    ),
                    source: source,
                    payload: ["owner": "agent-cli-manager", "cli": name]
                )
            }
        }

        if let dict = obj as? [String: Any] {
            let root = (dict["result"] as? [String: Any]) ?? dict
            var out: [DoctorFinding] = []
            if let problems = root["problems"] as? [[String: Any]] {
                out.append(contentsOf: problems.map { row in
                    let name = (row["name"] as? String) ?? "?"
                    return DoctorFinding(
                        category: .management,
                        severity: .warn,
                        body: .init(
                            subject: name,
                            title: "agent-cli-manager problem — \(name)",
                            detail: (row["message"] as? String) ?? String(describing: row),
                            remedy: "agent-cli-manager shadow --fix 또는 path-cli-health repair-copies --apply"
                        ),
                        source: source,
                        payload: ["owner": "agent-cli-manager", "cli": name]
                    )
                })
            }
            // check --json shape: { naming_violations, shadow }
            if let shadows = root["shadow"] as? [[String: Any]] {
                for row in shadows {
                    let status = (row["status"] as? String) ?? "ok"
                    guard status != "ok", status != "notOnPath" else { continue }
                    let cli = (row["cli"] as? String) ?? "?"
                    out.append(DoctorFinding(
                        category: .management,
                        severity: .warn,
                        body: .init(
                            subject: cli,
                            title: "agent-cli-manager shadow: \(status) — \(cli)",
                            detail: (row["message"] as? String) ?? String(describing: row),
                            remedy: "agent-cli-manager shadow --fix"
                        ),
                        source: source,
                        payload: ["owner": "agent-cli-manager", "cli": cli, "kind": "shadow"]
                    ))
                }
            }
            if let violations = root["naming_violations"] as? [[String: Any]], !violations.isEmpty {
                // naming=ok rows may still appear; only non-ok naming
                for row in violations {
                    let naming = (row["naming"] as? String) ?? "ok"
                    guard naming != "ok" else { continue }
                    let cli = (row["canonicalCLI"] as? String) ?? (row["command"] as? String) ?? "?"
                    out.append(DoctorFinding(
                        category: .management,
                        severity: .warn,
                        body: .init(
                            subject: cli,
                            title: "agent-cli-manager naming: \(naming) — \(cli)",
                            detail: (row["app"] as? String) ?? String(describing: row),
                            remedy: "package-identity.json dual_entry/cli 이름 정리 후 ship"
                        ),
                        source: source,
                        payload: ["owner": "agent-cli-manager", "cli": cli, "kind": "naming"]
                    ))
                }
            }
            return out
        }
        return []
    }
}
