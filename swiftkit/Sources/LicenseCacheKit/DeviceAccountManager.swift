import Foundation
import KeychainKit

/// 기기 단위 Gujo 계정 토큰을 관리한다.
///
/// 앱별 라이선스가 아닌, **이 Mac 전체**에 대한 Gujo 계정 인증 토큰을 Keychain에 보관한다.
/// 한 번 로그인하면 모든 앱이 `BulkActivationService`를 통해 소유 제품을 일괄 활성화할 수 있다.
///
/// Keychain service: `ai.gujo.device-account`
/// account: `device-token-v1`
@MainActor
@Observable
public final class DeviceAccountManager {
    public nonisolated(unsafe) static let keychainService = "ai.gujo.device-account"
    public nonisolated(unsafe) static let account = "device-token-v1"

    public private(set) var isWorking = false

    private let store: CachedKeychainStore
    private let httpClient: any GujoStoreHTTPClient
    private let apiBaseURL: URL
    private let now: @Sendable () -> Date

    public init(
        apiBaseURL: URL,
        httpClient: any GujoStoreHTTPClient = URLSession.shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.apiBaseURL = apiBaseURL
        self.httpClient = httpClient
        self.now = now
        self.store = CachedKeychainStore(service: Self.keychainService)
    }

    /// 저장된 기기 토큰이 존재하는지.
    public var isLoggedIn: Bool {
        guard let token = store.string(account: Self.account) else { return false }
        return !token.isEmpty
    }

    /// 저장된 기기 토큰. 없으면 nil.
    public var accountToken: String? {
        store.string(account: Self.account)
    }

    /// Sendable 컨텍스트에서 호출 가능한 토큰 조회 (Keychain 직접 읽기).
    public nonisolated var storedToken: String? {
        Self.storedAccountToken()
    }

    /// 이 Mac 공용 기기 SSO 토큰. 인스턴스 없이 읽는다 — 소비 앱은 저장하지 않는다.
    public nonisolated static func storedAccountToken() -> String? {
        let raw = CachedKeychainStore(service: keychainService)
            .string(account: account)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    /// RFC 8628 기기 인증으로 Gujo 계정에 로그인한다.
    ///
    /// `openVerificationURL`은 사용자에게 브라우저를 여는 콜백이다.
    /// LicenseKit은 AppKit에 의존하지 않으므로 호출자가 주입한다.
    @discardableResult
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
    public func login(
        clientName: String = "Gujo Device SSO",
        openVerificationURL: (URL) -> Bool
    ) async throws -> String {
        guard !isWorking else {
            throw LicenseProviderError.transient("기기 로그인이 이미 진행 중입니다.")
        }
        isWorking = true
        defer { isWorking = false }

        let authorization = try await startDeviceAuthorization(clientName: clientName)
        _ = openVerificationURL(authorization.verificationCompleteURL)

        while true {
            if Task.isCancelled {
                throw CancellationError()
            }
            if let token = try await pollDeviceAuthorization(authorization) {
                store.set(token, account: Self.account)
                return token
            }
            try await Task.sleep(nanoseconds: UInt64(authorization.pollInterval * 1_000_000_000))
        }
    }

    /// 기기 토큰을 삭제하고 로그아웃한다.
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
    public func logout() {
        store.delete(account: Self.account)
    }

    // MARK: - Private

    private func startDeviceAuthorization(clientName: String) async throws -> DeviceAccountAuthorization {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/cli/device/authorize"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(DeviceAccountAuthorizeRequest(clientName: clientName))

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LicenseProviderError.rejected("기기 인증을 시작할 수 없습니다.")
        }

        let decoded = try JSONDecoder().decode(DeviceAccountAuthorizeResponse.self, from: data)
        guard let verificationURL = URL(string: decoded.verificationURI),
              let completeURL = URL(string: decoded.verificationURIComplete)
        else {
            throw LicenseProviderError.malformedResponse("기기 인증 URL이 올바르지 않습니다.")
        }

        return DeviceAccountAuthorization(
            deviceCode: decoded.deviceCode,
            userCode: decoded.userCode,
            verificationURL: verificationURL,
            verificationCompleteURL: completeURL,
            expiresAt: now().addingTimeInterval(TimeInterval(decoded.expiresIn)),
            pollInterval: TimeInterval(max(decoded.interval, 1))
        )
    }

    private func pollDeviceAuthorization(_ authorization: DeviceAccountAuthorization) async throws -> String? {
        guard now() < authorization.expiresAt else {
            throw LicenseProviderError.rejected("기기 인증 코드가 만료되었습니다. 다시 로그인하세요.")
        }

        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/cli/device/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(DeviceAccountTokenRequest(deviceCode: authorization.deviceCode))

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseProviderError.transient("서버에 연결할 수 없습니다.")
        }

        if http.statusCode == 202 { return nil }
        guard http.statusCode == 200 else {
            throw LicenseProviderError.rejected("기기 인증에 실패했습니다. (HTTP \(http.statusCode))")
        }

        return try JSONDecoder().decode(DeviceAccountTokenResponse.self, from: data).accountToken
    }

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await httpClient.data(for: request)
        } catch let error as LicenseProviderError {
            throw error
        } catch {
            throw LicenseProviderError.transient("Gujo 서버에 연결할 수 없습니다.")
        }
    }
}

// MARK: - Internal Models

struct DeviceAccountAuthorization: Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    let verificationCompleteURL: URL
    let expiresAt: Date
    let pollInterval: TimeInterval
}

private struct DeviceAccountAuthorizeRequest: Encodable {
    let clientName: String
    enum CodingKeys: String, CodingKey { case clientName = "client_name" }
}

private struct DeviceAccountAuthorizeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let verificationURIComplete: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

private struct DeviceAccountTokenRequest: Encodable {
    let deviceCode: String
    enum CodingKeys: String, CodingKey { case deviceCode = "device_code" }
}

private struct DeviceAccountTokenResponse: Decodable {
    let accountToken: String
    enum CodingKeys: String, CodingKey { case accountToken = "account_token" }
}
