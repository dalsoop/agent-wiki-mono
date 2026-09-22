import Foundation

enum SparklePendingMapper {
    static func map(stdout: String, source: String) -> [DoctorFinding] {
        guard let data = stdout.data(using: .utf8),
              let obj = DoctorJSON.object(from: data)
        else { return [] }
        let root = (obj["result"] as? [String: Any]) ?? obj
        let counts = (root["counts"] as? [String: Any]) ?? [:]
        let ahead = counts["ahead"] as? Int ?? 0
        let behind = counts["behind"] as? Int ?? 0
        var out: [DoctorFinding] = []
        if ahead > 0 {
            out.append(DoctorFinding(
                category: .published,
                severity: .warn,
                body: .init(
                    subject: "sparkle-update-studio",
                    title: "Sparkle ahead \(ahead) — 설치본이 CDN보다 새것",
                    detail: "발행 정본: sparkle-update-studio publish <앱> --yes",
                    remedy: "sparkle-update-studio pending --json 후 publish --yes"
                ),
                source: source,
                payload: ["owner": "sparkle-update-studio", "kind": "ahead", "count": "\(ahead)"]
            ))
        }
        if behind > 0 {
            out.append(DoctorFinding(
                category: .published,
                severity: .warn,
                body: .init(
                    subject: "gujo-cloud-apps",
                    title: "Sparkle behind \(behind) — 구매자 수신 대상",
                    detail: "수신 정본: gujo-cloud-apps software update. 함대 소스 재설치 아님.",
                    remedy: "gujo-cloud-apps software update --all"
                ),
                source: source,
                payload: ["owner": "gujo-cloud-apps", "kind": "behind", "count": "\(behind)"]
            ))
        }
        if out.isEmpty {
            out.append(DoctorFinding(
                category: .published,
                severity: .ok,
                body: .init(
                    subject: "sparkle-update-studio",
                    title: "Sparkle pending ahead=0 behind=0",
                    detail: "발행·수신 잔여 없음"
                ),
                source: source,
                payload: ["owner": "sparkle-update-studio", "kind": "pending_ok"]
            ))
        }
        return out
    }
}
