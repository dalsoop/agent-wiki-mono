import Foundation

public struct DownloadPipelinePlatform: Sendable, Equatable, Codable {
    public var platform: String
    public var status: String
    public var version: String?
    public var downloadPath: String?

    public init(platform: String, status: String, version: String? = nil, downloadPath: String? = nil) {
        self.platform = platform
        self.status = status
        self.version = version
        self.downloadPath = downloadPath
    }
}

public struct DownloadPipelineAudit: Sendable, Equatable, Codable {
    public var ok: Bool
    public var ready: Bool
    public var contractVersion: String?
    public var platforms: [DownloadPipelinePlatform]
    public var statusCode: Int

    public init(
        ok: Bool,
        ready: Bool,
        contractVersion: String? = nil,
        platforms: [DownloadPipelinePlatform] = [],
        statusCode: Int
    ) {
        self.ok = ok
        self.ready = ready
        self.contractVersion = contractVersion
        self.platforms = platforms
        self.statusCode = statusCode
    }
}

/// `GET /api/downloads/pipeline`.
public struct DownloadPipelineStaffClient: Sendable {
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

    public func audit() async throws -> DownloadPipelineAudit {
        let token = try tokenProvider.staffToken()
        guard let token, !token.isEmpty else { throw StoreOpsStaffError.missingToken }
        let url = baseURL.appendingPathComponent(StoreOpsStaffEndpoints.downloadPipelinePath)
        let response = try await http.send(
            StaffHTTPRequest(
                method: "GET",
                url: url,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Accept": "application/json",
                ],
                body: nil
            )
        )
        guard (200..<300).contains(response.status) else { throw StoreOpsStaffError.http(response.status) }
        return try decode(statusCode: response.status, data: response.data)
    }

    private func decode(statusCode: Int, data: Data) throws -> DownloadPipelineAudit {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreOpsStaffError.decode("download pipeline")
        }
        let result = root["result"] as? [String: Any] ?? root
        let ok = (root["ok"] as? Bool) ?? true
        let ready = (result["ready"] as? Bool) ?? false
        let contract = result["contract_version"] as? String
        let rawPlatforms = result["platforms"] as? [[String: Any]] ?? []
        let platforms: [DownloadPipelinePlatform] = rawPlatforms.compactMap { obj in
            guard let platform = obj["platform"] as? String else { return nil }
            return DownloadPipelinePlatform(
                platform: platform,
                status: obj["status"] as? String ?? "unknown",
                version: obj["version"] as? String,
                downloadPath: obj["download_path"] as? String
            )
        }
        return DownloadPipelineAudit(
            ok: ok,
            ready: ready,
            contractVersion: contract,
            platforms: platforms,
            statusCode: statusCode
        )
    }
}
