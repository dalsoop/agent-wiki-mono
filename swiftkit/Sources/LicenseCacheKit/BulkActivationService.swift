import Foundation

/// 기기 계정 토큰으로 소유 제품 전체를 일괄 활성화한다.
///
/// 1. `GET /api/device/entitlements` → 이 계정이 소유한 제품 목록
/// 2. `POST /api/device/bulk-activate` → 각 제품의 라이선스 키 수령
/// 3. `LocalLicenseWallet`에 키 저장
///
/// 각 앱의 `LicenseManager`가 다음 실행 시 wallet에서 자동 활성화한다.
@available(*, deprecated, message: "EntitlementKit 을 쓴다")
public struct BulkActivationService: Sendable {
    private let apiBaseURL: URL
    private let httpClient: any GujoStoreHTTPClient

    public init(
        apiBaseURL: URL,
        httpClient: any GujoStoreHTTPClient = URLSession.shared
    ) {
        self.apiBaseURL = apiBaseURL
        self.httpClient = httpClient
    }

    /// 이 기기 계정이 소유한 제품 목록을 조회한다.
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
    public func fetchEntitlements(accountToken: String) async throws -> [DeviceEntitlement] {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/device/entitlements"))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accountToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseProviderError.transient("서버에 연결할 수 없습니다.")
        }
        guard http.statusCode == 200 else {
            throw error(for: http, data: data)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EntitlementsResponse.self, from: data).entitlements
    }

    /// 소유 제품 전체를 일괄 활성화하고 LocalLicenseWallet에 키를 저장한다.
    ///
    /// - Returns: 활성화된 제품 수
    @discardableResult
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
    public func bulkActivate(accountToken: String) async throws -> [DeviceEntitlement] {
        var request = URLRequest(url: apiBaseURL.appendingPathComponent("api/device/bulk-activate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accountToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseProviderError.transient("서버에 연결할 수 없습니다.")
        }
        guard http.statusCode == 200 else {
            throw error(for: http, data: data)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entitlements = try decoder.decode(BulkActivateResponse.self, from: data).entitlements

        // LocalLicenseWallet에 각 키 저장
        for entitlement in entitlements {
            try? LocalLicenseWallet.upsert(LicenseWalletEntry(
                productService: entitlement.bundleIdentifier,
                displayName: entitlement.productName,
                licenseKey: entitlement.licenseKey,
                note: "SSO bulk-activate · plan: \(entitlement.plan)"
            ))
        }

        return entitlements
    }

    // MARK: - Private

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await httpClient.data(for: request)
        } catch let error as LicenseProviderError {
            throw error
        } catch {
            throw LicenseProviderError.transient("Gujo 서버에 연결할 수 없습니다.")
        }
    }

    private func error(for response: HTTPURLResponse, data: Data) -> LicenseProviderError {
        let serverMessage = (try? JSONDecoder().decode(ServerErrorResponse.self, from: data).message)
        let message = serverMessage ?? "요청이 실패했습니다. (HTTP \(response.statusCode))"
        if response.statusCode == 401 || response.statusCode == 403 {
            return .rejected("기기 계정 인증이 만료되었거나 유효하지 않습니다. 다시 로그인하세요.")
        }
        if response.statusCode >= 500 {
            return .transient(message)
        }
        return .rejected(message)
    }
}

// MARK: - Response Models

private struct EntitlementsResponse: Decodable {
    let entitlements: [DeviceEntitlement]
}

private struct BulkActivateResponse: Decodable {
    let entitlements: [DeviceEntitlement]
}

private struct ServerErrorResponse: Decodable {
    let message: String?
}
