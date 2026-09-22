import Foundation
import StateRootKit

/// 함대 헬스 펄스 게시 — `~/.swift-app-state/pulse/<app>.pulse`
/// app-fleet-quality-auditor `source.pulse` 계약. GUI/CLI 기동 경로에서 `publish()` 호출을 권장.
public enum HealthPulseAdoption {
    public static let appName = "KnowledgeBaseWiki"

    public static func publish(status: String = "ok", detail: String? = nil) {
        let fm = FileManager.default
        let dir = StateRootKit.url(".swift-app-state/pulse")
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { _ = error }
        let url = dir.appendingPathComponent("\(Self.appName).pulse")
        var payload: [String: Any] = [
            "status": status,
            "ts": Int(Date().timeIntervalSince1970),
            "app": Self.appName,
        ]
        if let detail { payload["detail"] = detail }
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        } catch {
            return
        }
        guard var text = String(data: data, encoding: .utf8) else { return }
        if !text.hasSuffix("\n") { text += "\n" }
        do { try text.write(to: url, atomically: true, encoding: .utf8) } catch { _ = error }
    }
}
