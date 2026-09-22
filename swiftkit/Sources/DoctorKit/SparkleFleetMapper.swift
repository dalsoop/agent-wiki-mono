import Foundation

enum SparkleFleetMapper {
    static func map(stdout: String, source: String) -> [DoctorFinding] {
        guard let data = stdout.data(using: .utf8),
              let obj = DoctorJSON.object(from: data)
        else { return [] }
        let root = (obj["result"] as? [String: Any]) ?? obj
        let counts = (root["counts"] as? [String: Any]) ?? [:]
        let nofw = counts["feed_without_framework"] as? Int ?? 0
        let noChannel = counts["no_channel"] as? Int ?? 0
        var out: [DoctorFinding] = []
        if nofw > 0 {
            out.append(DoctorFinding(
                category: .published,
                severity: .warn,
                body: .init(
                    subject: "sparkle-update-studio",
                    title: "Sparkle 프레임워크 없음 \(nofw)",
                    detail: "피드는 있는데 Sparkle.framework 가 없다. 채택은 adopt, 설치본은 ADM ship.",
                    remedy: "sparkle-update-studio fleet --class feed_without_framework --json · app-build-manager ship"
                ),
                source: source,
                payload: [
                    "owner": "sparkle-update-studio",
                    "kind": "feed_without_framework",
                    "count": "\(nofw)",
                ]
            ))
        }
        if noChannel > 0 {
            out.append(DoctorFinding(
                category: .published,
                severity: .info,
                body: .init(
                    subject: "sparkle-update-studio",
                    title: "Sparkle 채널 없음 \(noChannel)",
                    detail: "internal 또는 미분류일 수 있다"
                ),
                source: source,
                payload: ["owner": "sparkle-update-studio", "kind": "no_channel", "count": "\(noChannel)"]
            ))
        }
        if out.isEmpty {
            out.append(DoctorFinding(
                category: .published,
                severity: .ok,
                body: .init(
                    subject: "sparkle-update-studio",
                    title: "Sparkle fleet 채널 건강",
                    detail: "feed_without_framework=0"
                ),
                source: source,
                payload: ["owner": "sparkle-update-studio", "kind": "fleet_ok"]
            ))
        }
        return out
    }
}
