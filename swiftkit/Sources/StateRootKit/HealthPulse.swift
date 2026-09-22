import Foundation

/// 함대 헬스 펄스 — `~/.swift-app-state/pulse/<앱>.pulse`
///
/// 앱마다 `HealthPulseAdoption.swift` 를 복제하지 않는다. 기동 경로에서
/// `HealthPulse.publish(app:)` 한 줄을 부른다. 경로는 `StateRootKit` 이 정한다.
public enum HealthPulse {
    public static func publish(
        app: String,
        status: String = "ok",
        detail: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) {
        let name = app.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let dir = StateRootKit.url(
            ".swift-app-state/pulse",
            environment: environment,
            homeDirectory: homeDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var payload: [String: Any] = [
                "app": name,
                "status": status,
                "ts": Int(Date().timeIntervalSince1970),
            ]
            if let detail { payload["detail"] = detail }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: dir.appendingPathComponent(name + ".pulse"))
        } catch {
            let line = "HealthPulse: \(error.localizedDescription)\n"
            if let data = line.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }
}
