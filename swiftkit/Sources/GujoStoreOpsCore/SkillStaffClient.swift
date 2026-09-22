import Foundation

public struct SkillMutationRequest: Sendable, Equatable {
    public var name: String
    public var version: String?
    public var body: String?

    public init(name: String, version: String? = nil, body: String? = nil) {
        self.name = name
        self.version = version
        self.body = body
    }
}

public struct SkillMutationResult: Sendable, Equatable, Codable {
    public var ok: Bool
    public var action: String
    public var name: String
    public var version: String?
    public var message: String?

    public init(ok: Bool, action: String, name: String, version: String? = nil, message: String? = nil) {
        self.ok = ok
        self.action = action
        self.name = name
        self.version = version
        self.message = message
    }
}

/// `/api/skills/publish` · `/api/skills/deprecate`.
public struct SkillStaffClient: Sendable {
    public var baseURL: URL
    public var tokenProvider: any StaffTokenProviding
    public var http: any StaffHTTPTransport

    public init(
        baseURL: URL,
        tokenProvider: any StaffTokenProviding,
        http: any StaffHTTPTransport
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.http = http
    }

    public func publish(_ request: SkillMutationRequest) async throws -> SkillMutationResult {
        try await post(path: StoreOpsStaffEndpoints.skillPublishPath, action: "publish", request: request)
    }

    public func deprecate(_ request: SkillMutationRequest) async throws -> SkillMutationResult {
        try await post(path: StoreOpsStaffEndpoints.skillDeprecatePath, action: "deprecate", request: request)
    }

    private func post(
        path: String,
        action: String,
        request: SkillMutationRequest
    ) async throws -> SkillMutationResult {
        let token = try tokenProvider.staffToken()
        guard let token, !token.isEmpty else { throw StoreOpsStaffError.missingToken }
        let url = baseURL.appendingPathComponent(path)
        var payload: [String: String] = ["name": request.name]
        if let version = request.version, !version.isEmpty { payload["version"] = version }
        if let body = request.body, !body.isEmpty { payload["body"] = body }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let response = try await http.send(
            StaffHTTPRequest(
                method: "POST",
                url: url,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                ],
                body: data
            )
        )
        guard (200..<300).contains(response.status) else { throw StoreOpsStaffError.http(response.status) }
        return try decodeMutation(action: action, fallbackName: request.name, data: response.data)
    }

    private func decodeMutation(action: String, fallbackName: String, data: Data) throws -> SkillMutationResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreOpsStaffError.decode("skill \(action)")
        }
        let result = root["result"] as? [String: Any]
        let name = result?["name"] as? String
            ?? root["name"] as? String
            ?? fallbackName
        let version = result?["version"] as? String ?? root["version"] as? String
        let message = result?["message"] as? String ?? root["message"] as? String
        let ok = (root["ok"] as? Bool) ?? true
        return SkillMutationResult(ok: ok, action: action, name: name, version: version, message: message)
    }
}
