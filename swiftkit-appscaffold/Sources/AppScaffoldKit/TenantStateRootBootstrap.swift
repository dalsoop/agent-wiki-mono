import Foundation
import StateRootKit
import TenantGuardKit

/// 프로세스 시작 시 테넌트 컨텍스트를 `SWIFT_APP_STATE_ROOT` 로 보낸다.
///
/// `TenantGuard.resolvedTenantID()` 로 컨텍스트만 읽고, 없으면 옛 동작을 유지한다.
/// `requireContext()` / exit 78 은 걸지 않는다 — 경로 리맵만 한다.
/// 이미 `SWIFT_APP_STATE_ROOT` 가 있으면 덮어쓰지 않는다.
public enum TenantStateRootBootstrap {
    public static let envKey = StateRootKit.declaredEnv

    /// 설정할 테넌트 루트. 이미 env 가 있거나 컨텍스트가 없으면 `nil`(변경 없음).
    public static func resolvedStateRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String = NSHomeDirectory()
    ) -> String? {
        if let existing = environment[envKey], !existing.isEmpty {
            return nil
        }
        guard let tenantID = TenantGuard.resolvedTenantID(
            environment: environment,
            homeDirectory: homeDirectory
        ) else {
            return nil
        }
        let slug = tenantID.hasPrefix("tenant:") ? String(tenantID.dropFirst(7)) : tenantID
        guard !slug.isEmpty else { return nil }
        return (homeDirectory as NSString)
            .appendingPathComponent("\(StateRootKit.tenantsDirectoryName)/\(slug)")
    }

    /// `SWIFT_APP_STATE_ROOT` 를 테넌트 루트로 설정한다. 바꿀 게 없으면 아무 것도 하지 않는다.
    ///
    /// 기본 경로(주입 없음)는 `ProcessInfo.environment` 를 읽지 않는다 — 그 딕셔너리는
    /// 한 번 읽으면 캐시되어, 뒤이은 `setenv` 가 같은 프로세스의 StateRootKit 에 안 보인다.
    /// 단위 테스트는 `environment`·`homeDirectory`·`assign` 을 주입해 실제 홈을 읽지 않는다.
    @discardableResult
    public static func apply(
        environment: [String: String]? = nil,
        homeDirectory: String? = nil,
        assign: ((String, String) -> Void)? = nil
    ) -> String? {
        let env = environment ?? getenvSnapshot()
        if assign == nil, StateRootKit.isRunningUnderTest(env) {
            return nil
        }
        let home = homeDirectory ?? env["HOME"] ?? NSHomeDirectory()
        guard let root = resolvedStateRoot(
            environment: env,
            homeDirectory: home
        ) else {
            return nil
        }
        if let assign {
            assign(envKey, root)
        } else {
            _ = setenv(envKey, root, 1)
        }
        return root
    }

    private static func getenvSnapshot() -> [String: String] {
        var env: [String: String] = [:]
        for key in [
            envKey, "ROOM_TENANT", "AGENT_TENANT", "TENANT_ID", "HOME",
            "XCTestConfigurationFilePath", "XCTestSessionIdentifier",
            "XCTestBundlePath", "SWIFT_TESTING_ENABLED",
        ] {
            if let raw = getenv(key) {
                let value = String(cString: raw)
                if !value.isEmpty { env[key] = value }
            }
        }
        return env
    }
}
