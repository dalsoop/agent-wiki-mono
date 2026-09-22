import Foundation

enum RegistryDoctorMapper {
    static func map(stdout: String, source: String) -> [DoctorFinding] {
        guard let data = stdout.data(using: .utf8),
              let obj = DoctorJSON.object(from: data)
        else { return [] }
        let root = (obj["result"] as? [String: Any]) ?? obj
        let total = root["registryTotal"] as? Int
            ?? root["registry_total"] as? Int
            ?? -1
        if total == 0 {
            return [
                DoctorFinding(
                    category: .management,
                    severity: .fail,
                    body: .init(
                        subject: "agent-app-registry",
                        title: "registry 비어 있음",
                        detail: "registryTotal=0 — ship/upsert 가 안 돌았거나 경로 오류",
                        remedy: "agent-app-registry doctor; app-build-manager ship …"
                    ),
                    source: source,
                    payload: ["owner": "agent-app-registry", "kind": "empty"]
                ),
            ]
        }
        if total > 0 {
            return [
                DoctorFinding(
                    category: .management,
                    severity: .ok,
                    body: .init(
                        subject: "agent-app-registry",
                        title: "registry \(total) apps",
                        detail: (root["note"] as? String)
                        ?? "path=\(root["registryPath"] as? String ?? "")"
                    ),
                    source: source,
                    payload: [
                        "owner": "agent-app-registry",
                        "kind": "summary",
                        "total": "\(total)",
                    ]
                ),
            ]
        }
        return []
    }
}
