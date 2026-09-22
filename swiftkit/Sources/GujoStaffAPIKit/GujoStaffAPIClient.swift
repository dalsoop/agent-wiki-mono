import Foundation
import GujoAuthKit
import HTTPClientKit

/// 스태프 API 호출 오류. 403 은 부족한 ability 이름을 반드시 싣는다 —
/// 서버가 밝힌 이름(`serverAbility`)과 클라이언트가 그 경로에 요구하는 이름(`required`) 둘 다.
public enum GujoStaffAPIError: Error, Equatable, Sendable, LocalizedError {
    case forbidden(required: StaffAbility?, serverAbility: String?, path: String)
    case unauthorized(path: String)
    case notFound(path: String)
    case validation(status: Int, message: String?, path: String)
    case server(status: Int, message: String?, path: String)
    case decoding(String, path: String)

    /// 부족한 ability 이름 — 서버가 말한 것이 우선, 없으면 클라이언트 매핑.
    public var missingAbilityName: String? {
        if case .forbidden(let required, let serverAbility, _) = self {
            return serverAbility ?? required?.rawValue
        }
        return nil
    }

    public var errorDescription: String? {
        switch self {
        case .forbidden(_, _, let path):
            let name = missingAbilityName ?? "(서버가 이름을 밝히지 않음)"
            return "스태프 권한 부족: '\(name)' 이(가) 필요합니다 (\(path))."
        case .unauthorized(let path):
            return "스태프 토큰이 거부됐습니다. 다시 로그인하세요 (\(path))."
        case .notFound(let path):
            return "대상을 찾을 수 없습니다 (\(path))."
        case .validation(let status, let message, let path):
            return "요청이 거부됐습니다(HTTP \(status)): \(message ?? "검증 실패") (\(path))."
        case .server(let status, let message, let path):
            return "Gujo 서버 오류(HTTP \(status)): \(message ?? "-") (\(path))."
        case .decoding(let detail, let path):
            return "응답 해석 실패 (\(path)): \(detail)"
        }
    }
}

/// 계약 §5 스태프 API 타입 클라이언트. `GujoStaffAPI.shared` 가 기본 인스턴스다.
///
/// 모든 호출은 `auth.current()` 의 토큰을 쓰고, 경로마다 요구 ability 를 먼저 로컬로 검사한다
/// (`GujoAuthError.missingAbility`). 서버가 403 을 주면 `GujoStaffAPIError.forbidden` 에 이름을 싣는다.
public struct GujoStaffAPIClient: Sendable {
    public let auth: GujoStaffAuth
    let http: any HTTPClient
    let baseURLOverride: URL?

    public init(
        auth: GujoStaffAuth = GujoAuth.staff,
        http: any HTTPClient = URLSessionHTTPClient(),
        baseURL: URL? = nil
    ) {
        self.auth = auth
        self.http = http
        self.baseURLOverride = baseURL
    }

    public var commerce: CommerceAPI { CommerceAPI(client: self) }
    public var support: SupportAPI { SupportAPI(client: self) }
    public var ops: OpsAPI { OpsAPI(client: self) }
    public var intake: IntakeAPI { IntakeAPI(client: self) }
    public var skills: SkillsAPI { SkillsAPI(client: self) }

    // MARK: - 호출 코어

    /// 본문 없는 호출.
    func call<Value: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        requires ability: StaffAbility?,
        as type: Value.Type = Value.self
    ) async throws -> Value {
        let session = try await authorize(ability)
        let transport = try transport()
        let response = try await transport.send(
            method: method, path: path, query: query, bearer: session.authorizationHeader)
        return try decode(response, path: path, required: ability)
    }

    /// JSON 본문 호출.
    func call<Body: Encodable, Value: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: Body,
        requires ability: StaffAbility?,
        as type: Value.Type = Value.self
    ) async throws -> Value {
        let session = try await authorize(ability)
        let transport = try transport()
        let response = try await transport.send(
            method: method, path: path, query: query, bearer: session.authorizationHeader, json: body)
        return try decode(response, path: path, required: ability)
    }

    private func authorize(_ ability: StaffAbility?) async throws -> StaffSession {
        if let ability { return try await auth.require(ability) }
        return try await auth.current()
    }

    private func transport() throws -> GujoJSONTransport {
        GujoJSONTransport(http: http, baseURL: try GujoCoreHost.resolve(override: baseURLOverride))
    }

    private func decode<Value: Decodable>(
        _ response: GujoJSONTransport.Response, path: String, required: StaffAbility?
    ) throws -> Value {
        switch response.status {
        case 200..<300:
            if Value.self == Empty.self, let empty = Empty() as? Value { return empty }
            do {
                return try response.decode(Value.self)
            } catch {
                throw GujoStaffAPIError.decoding(String(describing: error), path: path)
            }
        case 401:
            throw GujoStaffAPIError.unauthorized(path: path)
        case 403:
            throw GujoStaffAPIError.forbidden(
                required: required, serverAbility: response.errorBody?.abilityName, path: path)
        case 404:
            throw GujoStaffAPIError.notFound(path: path)
        case 400, 409, 422:
            let body = response.errorBody
            throw GujoStaffAPIError.validation(
                status: response.status, message: body?.message ?? body?.error, path: path)
        default:
            let body = response.errorBody
            throw GujoStaffAPIError.server(
                status: response.status, message: body?.message ?? body?.error, path: path)
        }
    }
}

/// 204/빈 본문 응답.
public struct Empty: Decodable, Equatable, Sendable {
    public init() {}
}

/// 기본 인스턴스 — Keychain 세션 + EndpointRouterKit `gujo-core`.
public enum GujoStaffAPI {
    public static let shared = GujoStaffAPIClient()
}

/// 경로 정본. 서버 라우트가 바뀌면 여기 한 곳만 고친다(계약 §3 그룹 접두사 기준).
public enum GujoStaffRoutes {
    public static let commerce = "/api/commerce/staff"
    public static let support = "/api/support/staff"
    public static let ops = "/ops/v1"
    public static let storeIntake = "/store/releases/intake"
    public static let lectureIntake = "/lecture/releases/intake"
    public static let skills = "/api/skills"
}
