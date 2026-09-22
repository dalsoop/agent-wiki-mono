import Foundation

public struct VaultCredentials: Codable, Equatable, Sendable {
    public var vaultId: String
    public var deviceId: String
    public var token: String
    public init(vaultId: String, deviceId: String, token: String) {
        self.vaultId = vaultId; self.deviceId = deviceId; self.token = token
    }
}

public struct RelayInvite: Codable, Equatable, Sendable {
    public var inviteId: String
    public var expiresAt: Int64
    public init(inviteId: String, expiresAt: Int64) { self.inviteId = inviteId; self.expiresAt = expiresAt }
}

public struct ChangePage: Codable, Equatable, Sendable {
    public var envelopes: [EncryptedEnvelope]
    public var nextCursor: String?
    public init(envelopes: [EncryptedEnvelope], nextCursor: String?) {
        self.envelopes = envelopes; self.nextCursor = nextCursor
    }
}

public struct RelayDevice: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var isOwner: Bool
    public var isCurrent: Bool
    public var canRevoke: Bool
    public var fingerprint: String
}

public enum RelayError: Error, Equatable, Sendable {
    case unauthorized
    case cursorExpired
    case inviteUnavailable
    case retryable
    case requestRejected(Int)
}

public protocol RelayTransport: Sendable {
    func createVault(deviceId: String, deviceName: String) async throws -> VaultCredentials
    func createInvite(token: String, keyFingerprint: String) async throws -> RelayInvite
    func exchangeInvite(
        inviteId: String, deviceId: String, deviceName: String, keyFingerprint: String
    ) async throws -> VaultCredentials
    func upload(token: String, envelopes: [EncryptedEnvelope]) async throws -> [String]
    func changes(token: String, cursor: String?, limit: Int) async throws -> ChangePage
    func devices(token: String) async throws -> [RelayDevice]
    func revokeDevice(token: String, deviceId: String) async throws
}

public extension RelayTransport {
    func devices(token: String) async throws -> [RelayDevice] { [] }
    func revokeDevice(token: String, deviceId: String) async throws {}
}

public final class RelayClient: RelayTransport, @unchecked Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    public func createVault(deviceId: String, deviceName: String) async throws -> VaultCredentials {
        try await post("v1/vaults", body: CreateVaultRequest(deviceId: deviceId, deviceName: deviceName), token: nil)
    }

    public func createInvite(token: String, keyFingerprint: String) async throws -> RelayInvite {
        try await post(
            "v1/invites", body: CreateInviteRequest(protocolVersion: 1, keyFingerprint: keyFingerprint), token: token)
    }

    public func exchangeInvite(
        inviteId: String, deviceId: String, deviceName: String, keyFingerprint: String
    ) async throws -> VaultCredentials {
        do {
            return try await post(
                "v1/invites/\(inviteId)/exchange",
                body: ExchangeInviteRequest(
                    deviceId: deviceId, deviceName: deviceName, keyFingerprint: keyFingerprint), token: nil)
        } catch RelayError.cursorExpired {
            throw RelayError.inviteUnavailable
        }
    }

    public func upload(token: String, envelopes: [EncryptedEnvelope]) async throws -> [String] {
        let response: UploadResponse = try await post(
            "v1/envelopes", body: UploadRequest(envelopes: envelopes), token: token)
        return response.cursors
    }

    public func changes(token: String, cursor: String?, limit: Int = 200) async throws -> ChangePage {
        var components = URLComponents(url: baseURL.appending(path: "v1/changes"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { components.queryItems?.append(URLQueryItem(name: "cursor", value: cursor)) }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await execute(request)
    }

    public func devices(token: String) async throws -> [RelayDevice] {
        var request = URLRequest(url: baseURL.appending(path: "v1/devices"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return try await execute(request)
    }

    public func revokeDevice(token: String, deviceId: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "v1/devices/\(deviceId)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        try await executeNoContent(request)
    }

    private func post<Body: Encodable, Response: Decodable>(
        _ path: String, body: Body, token: String?
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return try await execute(request)
    }

    private func execute<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw RelayError.retryable }
        guard let http = response as? HTTPURLResponse else { throw RelayError.retryable }
        switch http.statusCode {
        case 200..<300: break
        case 401: throw RelayError.unauthorized
        case 410: throw RelayError.cursorExpired
        case 429, 500...599: throw RelayError.retryable
        default: throw RelayError.requestRejected(http.statusCode)
        }
        return try decoder.decode(Response.self, from: data)
    }

    private func executeNoContent(_ request: URLRequest) async throws {
        let response: URLResponse
        do { (_, response) = try await session.data(for: request) }
        catch { throw RelayError.retryable }
        guard let http = response as? HTTPURLResponse else { throw RelayError.retryable }
        switch http.statusCode {
        case 200..<300: return
        case 401: throw RelayError.unauthorized
        case 429, 500...599: throw RelayError.retryable
        default: throw RelayError.requestRejected(http.statusCode)
        }
    }
}

private struct CreateVaultRequest: Codable { var deviceId: String; var deviceName: String }
private struct CreateInviteRequest: Codable { var protocolVersion: Int; var keyFingerprint: String }
private struct ExchangeInviteRequest: Codable { var deviceId: String; var deviceName: String; var keyFingerprint: String }
private struct UploadRequest: Codable { var envelopes: [EncryptedEnvelope] }
private struct UploadResponse: Codable { var cursors: [String] }
