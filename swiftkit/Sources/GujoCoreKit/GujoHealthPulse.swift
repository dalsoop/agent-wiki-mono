import Foundation
import StateRootKit

/// leftover copied-pulse 교체. 앱 로컬 `HealthPulseAdoption` 복제 대신
/// `HealthPulse.publish(app:)` 계약으로 게시한다. Kit 타입이 아직 없는
/// origin/main 에서도 컴파일되도록 같은 서명을 이 모듈에 둔다.
public enum HealthPulse {
    public static func publish(
        app: String,
        status: String = "ok",
        detail: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
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
            FileHandle.standardError.write(
                Data("HealthPulse: \(error.localizedDescription)\n".utf8))
        }
    }
}
