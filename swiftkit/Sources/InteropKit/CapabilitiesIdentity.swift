import Foundation
private typealias _P = Void; import PackageIdentityKit

/// capabilities `purpose` / `stateRoot` 의 실행 파일 기준 해석.
/// PackageIdentityKit 으로 단일화.
public enum CapabilitiesIdentity {
    public static let purposePlistKey = AppIdentityKeys.purposePlistKey
    public static let stateRootEnvPlistKey = AppIdentityKeys.stateRootEnvPlistKey
    public static let identityPurposeKey = AppIdentityKeys.identityPurposeKey
    public static let identityStateRootEnvKey = AppIdentityKeys.identityStateRootEnvKey

    public static func purpose(
        executablePath: String = ProcessInfo.processInfo.arguments.first ?? CommandLine.arguments[0]
    ) -> String {
        let url = URL(fileURLWithPath: executablePath)
        return AppIdentityLocator.locate(executable: url)?.purpose ?? ""
    }

    public static func stateRoot(
        executablePath: String = ProcessInfo.processInfo.arguments.first ?? CommandLine.arguments[0]
    ) -> Capabilities.StateRoot? {
        let url = URL(fileURLWithPath: executablePath)
        guard let env = AppIdentityLocator.locate(executable: url)?.stateRootEnv else { return nil }
        return Capabilities.StateRoot(env: env)
    }

    /// 이 실행 파일이 속한 앱 번들 ID. Helpers 안 CLI 는 감싸는 `.app` 의 Info.plist 를 본다.
    ///
    /// 왜 필요한가(실측 2026-08-10 계통): 레지스트리에 번들 ID 축이 없어서, 실행 중인
    /// 앱을 함대 앱으로 판정하려면 `net.ranode.` 접두사 추측에 기대야 했다. 접두사는
    /// 규칙이 아니라 관행이라 새 도메인 앱이 조용히 목록에서 빠진다.
    public static func bundleId(
        executablePath: String = ProcessInfo.processInfo.arguments.first ?? CommandLine.arguments[0]
    ) -> String {
        let url = URL(fileURLWithPath: executablePath)
        return AppIdentityLocator.locate(executable: url)?.bundleIdentifier ?? ""
    }

    public static func stringValue(
        executablePath: String,
        plistKey: String,
        identityKey: String
    ) -> String? {
        let url = URL(fileURLWithPath: executablePath)
        guard let identity = AppIdentityLocator.locate(executable: url) else { return nil }
        return identity.value(plistKey: plistKey, identityKey: identityKey)
    }

    public static func resolveExecutable(_ path: String) -> String {
        AppIdentityLocator.resolveExecutable(URL(fileURLWithPath: path)).path
    }

    public static func contentsInfoPlist(executable: String) -> URL? {
        AppIdentityLocator.contentsInfoPlist(executable: URL(fileURLWithPath: executable))
    }

    public static func packageIdentityURL(startingAt executable: String) -> URL? {
        AppIdentityLocator.packageIdentityURL(startingAt: URL(fileURLWithPath: executable))
    }
}
