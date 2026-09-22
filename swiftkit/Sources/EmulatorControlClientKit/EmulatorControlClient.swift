import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor EmulatorControlClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: any DeviceTokenStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenStore: any DeviceTokenStoring = SharedFileTokenStore()
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func pair(code: String, deviceName: String) async throws -> PairingSession {
        struct Request: Encodable {
            let code: String
            let deviceName: String
        }
        struct Response: Decodable {
            let token: String
            let expiresAt: Date
        }
        let response: Response = try await send(
            method: "POST",
            path: ["pair"],
            body: Request(code: code, deviceName: deviceName),
            authorization: false
        )
        await tokenStore.saveToken(response.token)
        return PairingSession(expiresAt: response.expiresAt)
    }

    public func createPairingCode() async throws -> PairingCode {
        try await send(method: "POST", path: ["pairing-codes"])
    }

    public func instances() async throws -> [FleetInstance] {
        try await send(method: "GET", path: ["instances"])
    }

    public func retainedInstances() async throws -> [RetainedFleetInstance] {
        try await send(method: "GET", path: ["retained"])
    }

    public func consoles() async throws -> [FleetConsole] {
        try await send(method: "GET", path: ["consoles"])
    }

    public func create(
        type: EmulatorType,
        profile: String?,
        size: String? = nil,
        idempotencyKey: UUID
    ) async throws -> FleetOperation {
        struct Request: Encodable {
            let profile: String?
            let type: EmulatorType
            let size: String?

            enum CodingKeys: String, CodingKey {
                case profile, type, size
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                try container.encodeIfPresent(profile, forKey: .profile)
                // size 생략 호환 없음 — 항상 명시(기본 standard).
                let resolved = (size?.isEmpty == false) ? size! : "standard"
                try container.encode(resolved, forKey: .size)
            }
        }
        return try await send(
            method: "POST",
            path: ["instances"],
            body: Request(profile: profile, type: type, size: size),
            idempotencyKey: idempotencyKey
        )
    }

    /// CPU/RAM 프리셋 변경. 서버가 helm upgrade 로 적용하며 Pod 가 재시작된다.
    public func resize(
        name: String,
        size: String,
        idempotencyKey: UUID
    ) async throws -> FleetOperation {
        struct Request: Encodable {
            let size: String
        }
        return try await send(
            method: "POST",
            path: ["instances", name, "resources"],
            body: Request(size: size),
            idempotencyKey: idempotencyKey
        )
    }

    public func act(
        _ action: LifecycleAction,
        on name: String,
        idempotencyKey: UUID
    ) async throws -> FleetOperation {
        try await send(
            method: "POST",
            path: ["instances", name, "actions", action.rawValue],
            idempotencyKey: idempotencyKey
        )
    }

    public func remove(name: String, idempotencyKey: UUID) async throws -> FleetOperation {
        try await send(
            method: "DELETE",
            path: ["instances", name],
            idempotencyKey: idempotencyKey
        )
    }

    public func purge(
        name: String,
        confirmation: String,
        idempotencyKey: UUID
    ) async throws -> FleetOperation {
        struct Request: Encodable {
            let confirmation: String
        }
        return try await send(
            method: "POST",
            path: ["retained", name, "purge"],
            body: Request(confirmation: confirmation),
            idempotencyKey: idempotencyKey
        )
    }

    public func operation(id: String) async throws -> FleetOperation {
        try await send(method: "GET", path: ["operations", id])
    }

    public func dispatchAgentJob(
        on instanceName: String,
        request: FleetAgentJobRequest,
        idempotencyKey: UUID
    ) async throws -> FleetAgentJobDispatch {
        try await send(
            method: "POST",
            path: ["instances", instanceName, "agent-jobs"],
            body: request,
            idempotencyKey: idempotencyKey
        )
    }

    public func agentJobs(on instanceName: String) async throws -> [FleetAgentJob] {
        try await send(method: "GET", path: ["instances", instanceName, "agent-jobs"])
    }

    public func agentJob(on instanceName: String, id: String) async throws -> FleetAgentJob {
        try await send(method: "GET", path: ["instances", instanceName, "agent-jobs", id])
    }

    public func revokeCurrentDevice() async throws {
        let _: EmptyResponse = try await send(method: "DELETE", path: ["devices", "current"])
        await tokenStore.deleteToken()
    }

    private func send<Response: Decodable>(
        method: String,
        path: [String],
        idempotencyKey: UUID? = nil,
        authorization: Bool = true
    ) async throws -> Response {
        try await send(
            method: method,
            path: path,
            bodyData: nil,
            idempotencyKey: idempotencyKey,
            authorization: authorization
        )
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: [String],
        body: Body,
        idempotencyKey: UUID? = nil,
        authorization: Bool = true
    ) async throws -> Response {
        let bodyData = try encoder.encode(body)
        return try await send(
            method: method,
            path: path,
            bodyData: bodyData,
            idempotencyKey: idempotencyKey,
            authorization: authorization
        )
    }

    private func send<Response: Decodable>(
        method: String,
        path: [String],
        bodyData: Data?,
        idempotencyKey: UUID?,
        authorization: Bool
    ) async throws -> Response {
        var url = baseURL
        for component in path {
            url.appendPathComponent(component)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if bodyData != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authorization {
            guard let token = await tokenStore.loadToken(), !token.isEmpty else {
                throw EmulatorControlError.notPaired
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EmulatorControlError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200 ..< 300:
            if Response.self == EmptyResponse.self, data.isEmpty {
                if let empty = EmptyResponse() as? Response {
                    return empty
                }
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw EmulatorControlError.invalidResponse
            }
        case 401:
            throw EmulatorControlError.unauthorized
        default:
            throw EmulatorControlError.httpStatus(httpResponse.statusCode)
        }
    }
}

private struct EmptyResponse: Codable, Sendable {}
