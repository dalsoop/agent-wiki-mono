import Foundation

enum AgentHostDualEntryMapper {
    static func map(stdout: String, source: String) -> [DoctorFinding] {
        guard let data = stdout.data(using: .utf8),
              let obj = DoctorJSON.object(from: data)
        else { return [] }
        let root = (obj["result"] as? [String: Any]) ?? obj

        // Prefer structured findings if present
        if let findings = root["findings"] as? [[String: Any]], !findings.isEmpty {
            return findings.compactMap { f in
                let sevRaw = (f["severity"] as? String) ?? "warn"
                let severity = DoctorSeverity(rawValue: sevRaw) ?? .warn
                guard severity >= .warn else { return nil }
                return DoctorFinding(
                    category: .management,
                    severity: severity,
                    body: .init(
                        subject: (f["subject"] as? String) ?? (f["name"] as? String) ?? "dual-entry",
                        title: (f["title"] as? String) ?? "agent-host-doctor dual-entry",
                        detail: (f["detail"] as? String) ?? (f["message"] as? String) ?? "",
                        remedy: (f["remedy"] as? String) ?? "agent-host-doctor ensure"
                    ),
                    source: source,
                    payload: ["owner": "agent-host-doctor"]
                )
            }
        }

        // dual_entry_hits — only non-ok
        let hits = (root["dual_entry_hits"] as? [[String: Any]]) ?? []
        var out: [DoctorFinding] = []
        for h in hits {
            let kind = (h["kind"] as? String) ?? "ok"
            if kind == "ok" { continue }
            let name = (h["name"] as? String) ?? "?"
            out.append(DoctorFinding(
                category: .management,
                severity: .fail,
                body: .init(
                    subject: name,
                    title: "agent-host-doctor dual-entry: \(kind) — \(name)",
                    detail: (h["message"] as? String) ?? kind,
                    remedy: "agent-host-doctor ensure  또는  path-cli-health repair-copies --apply"
                ),
                source: source,
                payload: [
                    "owner": "agent-host-doctor",
                    "cli": name,
                    "kind": kind,
                ]
            ))
        }
        return out
    }
}
