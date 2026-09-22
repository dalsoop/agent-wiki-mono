import Foundation

enum AgentCLIPathGapMapper {
    static func map(stdout: String, exitCode: Int32, source: String) -> [DoctorFinding] {
        guard let data = stdout.data(using: .utf8),
              let obj = DoctorJSON.raw(from: data)
        else { return [] }

        let rows: [[String: Any]]
        if let arr = obj as? [[String: Any]] {
            rows = arr
        } else if let dict = obj as? [String: Any] {
            let root = (dict["result"] as? [String: Any]) ?? dict
            rows = (root["gaps"] as? [[String: Any]])
                ?? (root["items"] as? [[String: Any]])
                ?? []
        } else {
            return []
        }

        var out: [DoctorFinding] = []
        var skippedNonHelpers = 0
        for row in rows {
            let present = row["pathCLIPresent"] as? Bool
            if present == true { continue }
            let cli = (row["canonicalCLI"] as? String) ?? (row["cli"] as? String) ?? "?"
            let app = (row["app"] as? String) ?? ""
            let appPath = (row["path"] as? String)
                ?? (app.isEmpty ? "" : "/Applications/\(app)")
            // argv / dual 없음 은 helpers PATH gap 이 아니다 (Android/FDroid 오탐)
            // row.dual_entry 우선 (테스트·확장 JSON), 없으면 package-identity
            let dual = (row["dual_entry"] as? String) ?? dualEntry(ofAppAt: appPath)
            if let dual, dual != "helpers", dual != "cli-only" {
                skippedNonHelpers += 1
                continue
            }
            if dual == nil {
                // dual 없으면 helpers 계약 아님 (legacy GUI / FDroid)
                skippedNonHelpers += 1
                continue
            }
            out.append(DoctorFinding(
                category: .management,
                severity: .warn,
                body: .init(
                    subject: cli,
                    title: "path-gap: PATH에 CLI 없음 — \(cli)",
                    detail: "installed app \(app) dual_entry=\(dual ?? "?") identity.cli=\(cli) 가 PATH 에 없다.",
                    remedy: "app-build-manager ship 해당 앱 · Helpers 심링크 재설치"
                ),
                source: source,
                payload: [
                    "owner": "agent-cli-manager",
                    "cli": cli,
                    "app": app,
                    "kind": "path_gap",
                    "dual_entry": dual ?? "",
                ]
            ))
        }
        if out.isEmpty {
            var detail = "helpers/cli-only path-gap 없음"
            if skippedNonHelpers > 0 {
                detail += " (argv/legacy \(skippedNonHelpers)건 스킵)"
            }
            out.append(DoctorFinding(
                category: .management,
                severity: .ok,
                body: .init(
                    subject: "agent-cli-manager",
                    title: "path-gap: helpers 대상 비어 있음",
                    detail: detail
                ),
                source: source,
                payload: [
                    "owner": "agent-cli-manager",
                    "kind": "path_gap_ok",
                    "skipped_non_helpers": "\(skippedNonHelpers)",
                ]
            ))
        }
        return out
    }

    /// package-identity dual_entry (nil if unreadable / missing).
    static func dualEntry(ofAppAt appPath: String) -> String? {
        guard !appPath.isEmpty else { return nil }
        let idPath = (appPath as NSString)
            .appendingPathComponent("Contents/Resources/package-identity.json")
        guard let data = FileManager.default.contents(atPath: idPath),
              let obj = DoctorJSON.object(from: data)
        else { return nil }
        return obj["dual_entry"] as? String
    }
}
