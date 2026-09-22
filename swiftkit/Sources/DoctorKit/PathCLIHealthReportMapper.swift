import Foundation

enum PathCLIHealthReportMapper {
    static func map(stdout: String, source: String) -> [DoctorFinding] {
        guard let data = stdout.data(using: .utf8),
              let obj = DoctorJSON.object(from: data)
        else { return [] }

        let root = (obj["result"] as? [String: Any]) ?? obj
        let hits = (root["hits"] as? [[String: Any]]) ?? []
        var out: [DoctorFinding] = []

        for h in hits {
            let kind = (h["kind"] as? String) ?? "unknown"
            if kind == "ok" { continue }
            let name = (h["name"] as? String) ?? "?"
            let message = (h["message"] as? String) ?? kind
            let path = (h["path"] as? String) ?? ""
            let remedy = (h["remedy"] as? String)
                ?? "path-cli-health repair-copies --apply  또는  app-build-manager ship <앱> release"
            let severity: DoctorSeverity = {
                switch kind {
                case "stale_copy", "gui_symlink", "help_hang": return .fail
                // missing 은 path-cli 에서 isProblem=false — 카탈로그 ghost 노이즈 방지로 warn
                case "missing": return .warn
                default: return .warn
                }
            }()
            out.append(DoctorFinding(
                category: .management,
                severity: severity,
                body: .init(
                    subject: name,
                    title: "path-cli-health: \(kind) — \(name)",
                    detail: message + (path.isEmpty ? "" : " (\(path))"),
                    remedy: remedy
                ),
                source: source,
                payload: [
                    "cli": name,
                    "kind": kind,
                    "path": path,
                    "owner": "path-cli-health",
                ]
            ))
        }

        if out.isEmpty, let bad = root["bad"] as? Int, bad == 0 {
            out.append(DoctorFinding(
                category: .management,
                severity: .ok,
                body: .init(
                    subject: "path-cli-health",
                    title: "path-cli-health: bad=0",
                    detail: "count=\(root["count"] as? Int ?? -1)"
                ),
                source: source,
                payload: ["owner": "path-cli-health", "kind": "summary_ok"]
            ))
        } else if out.isEmpty, let bad = root["bad"] as? Int, bad > 0 {
            // hits 생략된 요약만 있는 경우
            out.append(DoctorFinding(
                category: .management,
                severity: .fail,
                body: .init(
                    subject: "path-cli-health",
                    title: "path-cli-health: bad=\(bad)",
                    detail: "count=\(root["count"] as? Int ?? -1) — path-cli-health last --json 로 상세",
                    remedy: "path-cli-health repair-copies --apply"
                ),
                source: source,
                payload: ["owner": "path-cli-health", "kind": "summary_bad"]
            ))
        }
        return out
    }
}
