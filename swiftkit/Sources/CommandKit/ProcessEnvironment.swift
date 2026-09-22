import Foundation

/// 외부 프로세스 실행을 위한 환경변수 SSOT.
///
/// `HostPlatform.standardBinPaths`를 통한 PATH 보강과 `ToolchainEnvironment.sanitized`를
/// 통한 툴체인 정화(`SWIFT_EXEC` 오염 제거)를 단일 지점에서 결합한다.
public enum ProcessEnvironment {
    /// 시스템 기본 PATH 폴백.
    public static let fallbackPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    /// 주어진 환경변수 딕셔너리에 대해:
    /// 1. `ToolchainEnvironment.sanitized`를 적용하여 오염된 변수 제거
    /// 2. `PATH`에 `HostPlatform.standardBinPaths` 및 추가 경로를 선두에 결합(중복 제거 및 순서 보장)
    public static func enriched(
        _ environment: [String: String],
        extraBinPaths: [String] = []
    ) -> [String: String] {
        var env = ToolchainEnvironment.sanitized(environment)
        let currentPath = env["PATH"] ?? fallbackPath
        let existingSegments = currentPath.split(separator: ":").map(String.init)

        var newSegments: [String] = []
        var seen = Set<String>()

        func addSegment(_ path: String) {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { return }
            seen.insert(trimmed)
            newSegments.append(trimmed)
        }

        for path in extraBinPaths { addSegment(path) }
        for path in HostPlatformPaths.standardBinPaths { addSegment(path) }
        for path in existingSegments { addSegment(path) }

        env["PATH"] = newSegments.joined(separator: ":")
        return env
    }

    /// 현재 프로세스의 환경변수를 기반으로 보강된 환경변수 사본.
    public static func enrichedCurrent(extraBinPaths: [String] = []) -> [String: String] {
        enriched(ProcessInfo.processInfo.environment, extraBinPaths: extraBinPaths)
    }

    /// 기본 정화 및 보강된 현재 프로세스 환경 변수.
    public static var current: [String: String] {
        enrichedCurrent()
    }

    /// 옵셔널 환경변수를 받아 nil이면 현재 환경을 보강하여 반환하고, 값이 지정되어 있으면 해당 딕셔너리를 보강하여 반환한다.
    public static func resolve(_ environment: [String: String]?) -> [String: String] {
        if let environment {
            return enriched(environment)
        } else {
            return current
        }
    }
}
