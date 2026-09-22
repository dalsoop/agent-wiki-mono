import Foundation
import Observation

/// 번들 구독 상태를 조회하고 제품별 구독 커버 여부를 판단한다.
///
/// 앱의 `LicenseManager`가 개별 라이선스 확인에 실패했을 때 이 매니저에게
/// "내 제품이 활성 번들에 포함되는지"를 물어볼 수 있다.
@MainActor
@Observable
public final class BundleSubscriptionManager {
    public private(set) var bundles: [SubscriptionBundle] = []
    public private(set) var isLoading = false
    public private(set) var lastError: String?

    private let client: any GujoStoreHTTPClient
    private let apiBaseURL: URL
    private let authToken: @Sendable () -> String?

    /// - Parameters:
    ///   - apiBaseURL: Gujo Store API 루트. `EndpointRouter.url("apps")` 로 해석.
    ///   - authToken: 호출 시점에 Keychain에서 읽은 인증 토큰을 반환하는 클로저.
    ///   - client: 테스트에서 네트워크를 대체하기 위한 HTTP 경계.
    public init(
        apiBaseURL: URL,
        authToken: @escaping @Sendable () -> String?,
        client: any GujoStoreHTTPClient = URLSession.shared
    ) {
        self.apiBaseURL = apiBaseURL
        self.authToken = authToken
        self.client = client
    }

    /// 서버에서 사용 가능한 번들 목록을 가져온다.
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
    public func fetchBundles() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        do {
            let request = try makeRequest(path: "api/bundles", method: "GET")
            let response: BundlesResponse = try await send(request)
            bundles = response.bundles
        } catch {
            lastError = (error as? LicenseProviderError)?.errorDescription
                ?? "번들 목록을 불러올 수 없습니다."
        }
    }

    /// 내 구독 정보를 가져와 번들 활성 상태를 갱신한다.
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
    public func refreshMySubscriptions() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        do {
            let request = try makeRequest(path: "api/subscriptions", method: "GET")
            let response: SubscriptionsResponse = try await send(request)
            // 서버가 활성 구독에 해당하는 번들만 돌려준다.
            bundles = response.bundles
        } catch {
            lastError = (error as? LicenseProviderError)?.errorDescription
                ?? "구독 정보를 불러올 수 없습니다."
        }
    }

    /// 지정한 제품이 활성 구독 번들에 포함되는지 확인한다.
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
    public func isProductCovered(productID: Int) -> Bool {
        bundles.contains { bundle in
            bundle.isActive && bundle.productIDs.contains(productID)
        }
    }

    /// 지정한 제품을 커버하는 활성 번들을 돌려준다. 없으면 nil.
    @available(*, deprecated, message: "EntitlementKit 을 쓴다")
    public func coveringBundle(for productID: Int) -> SubscriptionBundle? {
        bundles.first { bundle in
            bundle.isActive && bundle.productIDs.contains(productID)
        }
    }

    // MARK: - Networking

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        let url = apiBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = authToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await client.data(for: request)
        } catch {
            throw LicenseProviderError.transient("구독 서버에 연결할 수 없습니다.")
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LicenseProviderError.transient("구독 서버 응답을 읽을 수 없습니다.")
        }
        guard httpResponse.statusCode == 200 else {
            if httpResponse.statusCode >= 500 {
                throw LicenseProviderError.transient("구독 서버 오류입니다. (HTTP \(httpResponse.statusCode))")
            }
            throw LicenseProviderError.rejected("구독 정보 요청이 거부되었습니다. (HTTP \(httpResponse.statusCode))")
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw LicenseProviderError.malformedResponse("구독 서버 응답을 해석할 수 없습니다.")
        }
    }
}

// MARK: - API Response Models

private struct BundlesResponse: Decodable {
    let bundles: [SubscriptionBundle]
}

private struct SubscriptionsResponse: Decodable {
    let bundles: [SubscriptionBundle]
}
