import Foundation
import StateRootKit
import LocalizationKit

/// Ops 접속 설정. 호스트는 EndpointRouterKit 키만. 토큰은 `StaffTokenProviding`.
public enum OpsPreferences {
    public static let prodHostKey = StoreOpsStaffEndpoints.prodHostKey
    public static let localHostKey = StoreOpsStaffEndpoints.localHostKey
    // 주소 해석은 `StoreOpsStaffEndpoints.resolvedHost` 한 곳으로 모은다.
    // `EndpointRouter.string` 을 직접 부르면 미선언 키(`software-prod`)가 "" 로 돌아와
    // 아래 `baseURL` 이 `file:///` 로 퇴화한다.
    public static let prodURLString = StoreOpsStaffEndpoints.resolvedHost(prodHostKey)
    public static let localURLString = StoreOpsStaffEndpoints.resolvedHost(localHostKey)

    private static let endpointChoiceKey = "gujo.store.ops.endpointKey"
    public static let tokenProvider: any StaffTokenProviding = KeychainStaffTokenProvider()

    public static var endpointKey: String {
        let stored = UserDefaults.standard.string(forKey: endpointChoiceKey) ?? ""
        if stored == localHostKey { return localHostKey }
        return prodHostKey
    }

    public static var baseURLString: String {
        StoreOpsStaffEndpoints.resolvedHost(endpointKey)
    }

    public static var baseURL: URL {
        URL(string: baseURLString) ?? URL(string: prodURLString) ?? URL(fileURLWithPath: "/")
    }

    /// Keychain staff 토큰. env·UserDefaults·평문 파일은 읽지 않는다.
    public static var bearerToken: String? {
        (try? tokenProvider.staffToken()).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static var storedBaseURLString: String { baseURLString }

    public static var tokenIsSet: Bool { bearerToken != nil }

    public static func save(baseURL: String, token: String = "") {
        _ = token
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let local = URL(string: localURLString)
        let picked: String
        if let localHost = local?.host, trimmed.lowercased().contains(localHost.lowercased()) {
            picked = localHostKey
        } else if trimmed == localURLString {
            picked = localHostKey
        } else {
            picked = prodHostKey
        }
        UserDefaults.standard.set(picked, forKey: endpointChoiceKey)
    }

    public static func makeClient() -> StoreOpsClient {
        StoreOpsClient(opsBaseURL: baseURL, tokenProvider: tokenProvider)
    }

    /// prod URL 인데 토큰이 없으면 쓰기 전에 경고용.
    public static var needsProdToken: Bool {
        endpointKey == prodHostKey && bearerToken == nil
    }

    /// 존재 확인용 경로. 인증은 이 파일을 읽지 않는다.
    public static var tokenFilePath: String {
        LegacyPlaintextTokenProbe.storeOpsPath()
    }

    public static func legacyTokenFiles(fileManager: FileManager) -> [String] {
        [
            LegacyPlaintextTokenProbe.storeOpsPath(),
            LegacyPlaintextTokenProbe.skillStorePath(),
        ].filter { LegacyPlaintextTokenProbe.exists(at: $0, fileManager: fileManager) }
    }

    /// 평문 파일은 인증에 쓰지 않는다. 호출부는 GUI 프롬프트 트리거용으로 남긴다.
    public static func loadTokenFileIfNeeded() {}

    public static func forceLoadTokenFile() {}

    /// 사용자용 에러 문구.
    public static func humanize(_ error: Error) -> String {
        let s = error.localizedDescription
        let connKeywords = ["hostname", "could not be found", "could not connect", "connection refused"]
        if connKeywords.contains(where: { s.localizedCaseInsensitiveContains($0) }) {
            return CLILocalization.format("OpsPreferences.return", prodURLString)
        }
        let isAuthError = ["HTTP 401", "invalid ops credential"].contains(where: { s.localizedCaseInsensitiveContains($0) })
        if isAuthError {
            return CLILocalization.string("OpsPreferences.return-2")
        }
        return s.contains("HTTP 404") ? CLILocalization.string("OpsPreferences.return-3") : s
    }
}
