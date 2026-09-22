import EndpointRouterKit
import Foundation
import HTTPClientKit

/// 서버 오류 봉투(계약 §1: `{ "error": "authorization_pending" }`).
/// 403 에는 부족한 ability 이름이 실릴 수 있어 여러 후보 키를 받는다.
public struct GujoErrorBody: Decodable, Equatable, Sendable {
    public var error: String?
    public var message: String?
    public var ability: String?
    public var requiredAbility: String?
    public var missingAbility: String?

    enum CodingKeys: String, CodingKey {
        case error, message, ability
        case requiredAbility = "required_ability"
        case missingAbility = "missing_ability"
    }

    public init(
        error: String? = nil, message: String? = nil, ability: String? = nil,
        requiredAbility: String? = nil, missingAbility: String? = nil
    ) {
        self.error = error
        self.message = message
        self.ability = ability
        self.requiredAbility = requiredAbility
        self.missingAbility = missingAbility
    }

    /// 서버가 밝힌 부족 ability 이름(후보 키 중 첫 비어있지 않은 값).
    public var abilityName: String? {
        [requiredAbility, missingAbility, ability].compactMap { $0 }.first { !$0.isEmpty }
    }

    public static func parse(_ data: Data) -> GujoErrorBody? {
        guard !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(GujoErrorBody.self, from: data)
        } catch {
            return nil
        }
    }
}

/// gujo.ai API 호스트 해석 — EndpointRouterKit `gujo-core` 키만 본다(하드코딩 금지).
public enum GujoCoreHost {
    public static let endpointKey = "gujo-core"

    public static func resolve(override: URL? = nil) throws -> URL {
        if let override { return override }
        guard let url = EndpointRouter.url(endpointKey) else {
            throw GujoAuthError.endpointMissing(key: endpointKey)
        }
        return url
    }
}

/// 두 킷이 같이 쓰는 JSON 전송 헬퍼. `HTTPClient` 주입으로 오프라인 테스트가 가능하다.
public struct GujoJSONTransport: Sendable {
    public let http: any HTTPClient
    public let baseURL: URL

    public init(http: any HTTPClient, baseURL: URL) {
        self.http = http
        self.baseURL = baseURL
    }

    public struct Response: Sendable {
        public let status: Int
        public let data: Data

        public init(status: Int, data: Data) {
            self.status = status
            self.data = data
        }

        public var errorBody: GujoErrorBody? { GujoErrorBody.parse(data) }

        public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
            do {
                return try SessionCoding.decoder.decode(type, from: data)
            } catch {
                throw GujoAuthError.malformedResponse("\(type): \(error)")
            }
        }
    }

    /// 경로에 쿼리를 붙여 절대 URL 을 만든다. `path` 는 `/api/...` 처럼 슬래시로 시작한다.
    /// `appendingPathComponent` 는 슬래시를 인코딩할 수 있어 URLComponents 로 붙인다.
    public func url(path: String, query: [String: String] = [:]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw GujoAuthError.malformedResponse("URL 조립 실패: \(path)")
        }
        let requestPath = path.hasPrefix("/") ? path : "/" + path
        let basePath = components.path
        if basePath.isEmpty || basePath == "/" {
            components.path = requestPath
        } else {
            let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
            components.path = trimmedBase + requestPath
        }
        if !query.isEmpty {
            components.queryItems = query.keys.sorted().map { URLQueryItem(name: $0, value: query[$0]) }
        }
        guard let url = components.url else {
            throw GujoAuthError.malformedResponse("URL 조립 실패: \(path)")
        }
        return url
    }

    public func send(
        method: String,
        path: String,
        query: [String: String] = [:],
        bearer: String? = nil,
        body: Data? = nil
    ) async throws -> Response {
        var headers = ["Accept": "application/json"]
        if body != nil { headers["Content-Type"] = "application/json" }
        if let bearer { headers["Authorization"] = bearer }
        let url = try url(path: path, query: query)
        do {
            let result = try await http.send(method: method, url: url, headers: headers, body: body)
            return Response(status: result.status, data: result.data)
        } catch let error as GujoAuthError {
            throw error
        } catch {
            throw GujoAuthError.transport(String(describing: error))
        }
    }

    public func send<Body: Encodable>(
        method: String,
        path: String,
        query: [String: String] = [:],
        bearer: String? = nil,
        json body: Body
    ) async throws -> Response {
        let data: Data
        do {
            data = try SessionCoding.encoder.encode(body)
        } catch {
            throw GujoAuthError.malformedResponse("요청 인코딩 실패: \(error)")
        }
        return try await send(method: method, path: path, query: query, bearer: bearer, body: data)
    }
}
