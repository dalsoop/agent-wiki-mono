import Foundation
import StateRootKit

/// 테스트 스캔 동작 설정. **앱 UI(Settings)가 쓰고 scan 이 읽는다.**
///
/// 실측 2026-08-11: `.build` 를 지우면 다음 스캔이 캐시 없이 처음부터 빌드해 6~11시간이
/// 걸렸다. 디스크가 넉넉하면 살려둬 증분 빌드를 하는 게 맞는데, 그 판단을 코드에 박지
/// 않고 **사람이 UI 에서 고르게** 둔다 — 디스크 상황은 호스트마다 다르다.
public struct TestHealthConfig: Codable, Sendable, Equatable {
    /// 스캔 뒤 `.build` 를 살려둘까. 기본 `true` — 증분 빌드가 다음 스캔을 분 단위로 줄인다.
    public var keepBuild: Bool
    /// 앱 하나당 한도(초). 안 끝나는 빌드도 결함이다.
    public var timeoutSeconds: Int

    public init(keepBuild: Bool = true, timeoutSeconds: Int = 900) {
        self.keepBuild = keepBuild
        self.timeoutSeconds = timeoutSeconds
    }

    public static var defaultURL: URL {
        StateRootKit.url(".agent-ops/test-health/config.json")
    }

    public static func load(at url: URL = defaultURL) -> TestHealthConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(TestHealthConfig.self, from: data)
        else { return TestHealthConfig() }
        return config
    }

    public func save(at url: URL = defaultURL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        do { try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true) } catch { _ = error }
        do { try data.write(to: url, options: .atomic) } catch { _ = error }
    }
}
