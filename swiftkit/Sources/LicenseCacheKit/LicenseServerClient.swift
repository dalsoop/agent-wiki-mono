import Foundation
import EndpointRouterKit

/// 서버 `/api/license/check` 호출 담당.
public struct LicenseServerClient: Sendable {
    public let deviceToken: String
    
    public init(deviceToken: String) {
        self.deviceToken = deviceToken
    }
    
    public func fetch() async throws -> LicenseResponse {
        let baseURL = EndpointRouter.string("core")
        guard let url = URL(string: "\(baseURL)/api/license/check") else {
            throw EntitlementServerError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(deviceToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        let (data, httpResponse) = try await URLSession.shared.data(for: request)
        guard let http = httpResponse as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw EntitlementServerError.serverError
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LicenseResponse.self, from: data)
    }
}

public enum EntitlementServerError: Error, Sendable {
    case invalidURL
    case serverError
}
