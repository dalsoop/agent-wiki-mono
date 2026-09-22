import Foundation
@_exported import HTTPClientKit   // HTTPClient / URLSessionHTTPClient 공용

public enum InfisicalError: Error, Sendable, Equatable, CustomStringConvertible {
    case http(step: String, status: Int, body: String)
    case parse(step: String)
    case notLoggedIn
    public var description: String {
        switch self {
        case .http(let s, let st, let b): return "\(s): HTTP \(st) \(String(b.prefix(200)))"
        case .parse(let s): return "\(s): unexpected response shape"
        case .notLoggedIn: return "not logged in"
        }
    }
}

/// Infisical REST API 클라이언트. Universal Auth(clientId/clientSecret)로 로그인해
/// access token 을 쥐고, 프로젝트·시크릿·아이덴티티를 조작한다.
public actor InfisicalClient {
    private let http: HTTPClient
    private let base: String   // 예: https://infisical.50.internal.kr
    private var accessToken: String?

    // 기본값을 nil 로 두고 내부에서 생성한다 — default 인자가 caller 모듈에서 HTTPClientKit
    // 심볼을 요구하지 않게 해 링크 문제를 피한다.
    public init(http: HTTPClient? = nil, instanceBase: String) {
        self.http = http ?? URLSessionHTTPClient()
        self.base = instanceBase.hasSuffix("/") ? String(instanceBase.dropLast()) : instanceBase
    }

    public var isLoggedIn: Bool { accessToken != nil }

    // MARK: - 저수준 요청

    private func request(_ step: String, _ method: String, _ path: String,
                         query: [String: String] = [:], json bodyObj: [String: Any]? = nil,
                         auth: Bool = true, tokenOverride: String? = nil) async throws -> Data {
        var comps = URLComponents(string: base + "/api" + path)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var headers = ["Content-Type": "application/json"]
        if let tokenOverride {
            headers["Authorization"] = "Bearer \(tokenOverride)"
        } else if auth {
            guard let token = accessToken else { throw InfisicalError.notLoggedIn }
            headers["Authorization"] = "Bearer \(token)"
        }
        let body = try bodyObj.map { try JSONSerialization.data(withJSONObject: $0) }
        let (status, data) = try await http.send(method: method, url: comps.url!, headers: headers, body: body)
        guard (200..<300).contains(status) else {
            throw InfisicalError.http(step: step, status: status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private func obj(_ data: Data, _ step: String) throws -> [String: Any] {
        do {
            guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw InfisicalError.parse(step: step)
            }
            return o
        } catch let err as InfisicalError {
            throw err
        } catch {
            throw InfisicalError.parse(step: step)
        }
    }

    // MARK: - 인증 / 상태

    public func login(clientId: String, clientSecret: String) async throws {
        let data = try await request("login", "POST", "/v1/auth/universal-auth/login",
                                     json: ["clientId": clientId, "clientSecret": clientSecret], auth: false)
        guard let token = try obj(data, "login")["accessToken"] as? String else {
            throw InfisicalError.parse(step: "login")
        }
        accessToken = token
    }

    public func logout() { accessToken = nil }

    /// GET /api/status — 인증 불필요. 실패해도 throw 하지 않고 unreachable 로 보고.
    public func serverStatus() async -> ServerStatus {
        do {
            let data = try await request("status", "GET", "/status", auth: false)
            let msg = (try? obj(data, "status"))?["message"] as? String ?? "ok"
            return ServerStatus(reachable: true, message: msg)
        } catch {
            return ServerStatus(reachable: false, message: "\(error)")
        }
    }

    // MARK: - 프로젝트

    public func workspaces() async throws -> [Workspace] {
        let data = try await request("workspaces", "GET", "/v1/workspace")
        guard let arr = try obj(data, "workspaces")["workspaces"] as? [[String: Any]] else {
            throw InfisicalError.parse(step: "workspaces")
        }
        return arr.compactMap { w in
            guard let id = (w["id"] ?? w["_id"]) as? String, let name = w["name"] as? String else { return nil }
            let envs = (w["environments"] as? [[String: Any]] ?? []).compactMap { e -> ProjectEnvironment? in
                guard let slug = e["slug"] as? String else { return nil }
                return ProjectEnvironment(name: e["name"] as? String ?? slug, slug: slug)
            }
            return Workspace(id: id, name: name, orgId: w["orgId"] as? String ?? "", environments: envs)
        }
    }

    // MARK: - 폴더

    public func folders(workspaceId: String, environment: String, path: String = "/") async throws -> [Folder] {
        let data = try await request("folders", "GET", "/v1/folders",
                                     query: ["workspaceId": workspaceId, "environment": environment, "path": path])
        guard let arr = try obj(data, "folders")["folders"] as? [[String: Any]] else {
            throw InfisicalError.parse(step: "folders")
        }
        return arr.compactMap { f in
            guard let id = f["id"] as? String, let name = f["name"] as? String else { return nil }
            return Folder(id: id, name: name)
        }.sorted { $0.name < $1.name }
    }

    /// 폴더 한 단계를 생성한다. 이미 존재하는 경우의 idempotency 는
    /// `ensureFolderPath` 에서 목록 재확인으로 처리한다.
    public func createFolder(workspaceId: String, environment: String, path: String = "/",
                             name: String) async throws {
        _ = try await request("create-folder", "POST", "/v1/folders", json: [
            "workspaceId": workspaceId, "environment": environment,
            "path": path, "name": name,
        ])
    }

    /// `/a/b` 형태의 경로를 상위부터 준비한다. 동시 생성으로 실패한 경우에는
    /// 해당 부모를 다시 읽어 실제로 존재할 때만 계속 진행한다.
    public func ensureFolderPath(workspaceId: String, environment: String, path: String) async throws {
        let components = path.split(separator: "/").map(String.init)
        var parent = "/"
        for name in components {
            do {
                try await createFolder(
                    workspaceId: workspaceId, environment: environment,
                    path: parent, name: name
                )
            } catch {
                let existing = try await folders(
                    workspaceId: workspaceId, environment: environment, path: parent
                )
                guard existing.contains(where: { $0.name == name }) else { throw error }
            }
            parent = parent == "/" ? "/\(name)/" : "\(parent)\(name)/"
        }
    }

    // MARK: - 시크릿 CRUD (v3 raw)

    /// recursive=true 면 하위 폴더까지 전부. 각 Secret.path 에 실제 경로가 채워진다.
    public func secrets(workspaceId: String, environment: String, path: String = "/",
                        recursive: Bool = false) async throws -> [Secret] {
        var query = ["workspaceId": workspaceId, "environment": environment, "secretPath": path]
        if recursive { query["recursive"] = "true" }
        let data = try await request("secrets", "GET", "/v3/secrets/raw", query: query)
        guard let arr = try obj(data, "secrets")["secrets"] as? [[String: Any]] else {
            throw InfisicalError.parse(step: "secrets")
        }
        return arr.compactMap { s in
            guard let key = s["secretKey"] as? String else { return nil }
            return Secret(key: key, value: s["secretValue"] as? String ?? "",
                          comment: s["secretComment"] as? String ?? "",
                          path: s["secretPath"] as? String ?? path)
        }
    }

    public func createSecret(workspaceId: String, environment: String, path: String = "/",
                             key: String, value: String, comment: String = "") async throws {
        _ = try await request("create-secret", "POST", "/v3/secrets/raw/\(escape(key))", json: [
            "workspaceId": workspaceId, "environment": environment, "secretPath": path,
            "secretValue": value, "secretComment": comment, "type": "shared",
        ])
    }

    public func updateSecret(workspaceId: String, environment: String, path: String = "/",
                             key: String, value: String) async throws {
        _ = try await request("update-secret", "PATCH", "/v3/secrets/raw/\(escape(key))", json: [
            "workspaceId": workspaceId, "environment": environment, "secretPath": path,
            "secretValue": value, "type": "shared",
        ])
    }

    public func deleteSecret(workspaceId: String, environment: String, path: String = "/",
                             key: String) async throws {
        _ = try await request("delete-secret", "DELETE", "/v3/secrets/raw/\(escape(key))", json: [
            "workspaceId": workspaceId, "environment": environment, "secretPath": path, "type": "shared",
        ])
    }

    // MARK: - 아이덴티티 / 토큰

    public func identities(orgId: String) async throws -> [Identity] {
        // 주의: /v2/organizations/{id}/identities 는 self-hosted(2026-05 기준)에 없음 — identity-memberships 가 맞는 경로.
        let data = try await request("identities", "GET", "/v2/organizations/\(escape(orgId))/identity-memberships")
        guard let arr = try obj(data, "identities")["identityMemberships"] as? [[String: Any]] else {
            throw InfisicalError.parse(step: "identities")
        }
        return arr.compactMap { m in
            guard let ident = m["identity"] as? [String: Any],
                  let id = ident["id"] as? String, let name = ident["name"] as? String else { return nil }
            let role = m["role"] as? String ?? ""
            return Identity(id: id, name: name, role: role)
        }
    }

    public func clientSecrets(identityId: String) async throws -> [ClientSecretInfo] {
        let data = try await request("client-secrets", "GET",
                                     "/v1/auth/universal-auth/identities/\(escape(identityId))/client-secrets")
        guard let arr = try obj(data, "client-secrets")["clientSecretData"] as? [[String: Any]] else {
            throw InfisicalError.parse(step: "client-secrets")
        }
        return arr.compactMap { s in
            guard let id = s["id"] as? String else { return nil }
            return ClientSecretInfo(id: id, description: s["description"] as? String ?? "",
                                    createdAt: s["createdAt"] as? String ?? "")
        }
    }

    /// 새 client secret 발급 — 평문은 이 호출의 반환값에서만 볼 수 있다.
    public func createClientSecret(identityId: String, description: String) async throws -> String {
        let data = try await request("create-client-secret", "POST",
                                     "/v1/auth/universal-auth/identities/\(escape(identityId))/client-secrets",
                                     json: ["description": description, "numUsesLimit": 0, "ttl": 0])
        guard let secret = try obj(data, "create-client-secret")["clientSecret"] as? String else {
            throw InfisicalError.parse(step: "create-client-secret")
        }
        return secret
    }

    public func revokeClientSecret(identityId: String, clientSecretId: String) async throws {
        _ = try await request("revoke-client-secret", "POST",
                              "/v1/auth/universal-auth/identities/\(escape(identityId))/client-secrets/\(escape(clientSecretId))/revoke")
    }

    // MARK: - 온보딩 프로비저닝 (관리자 토큰 사용, 저장하지 않음)

    /// 관리자(사용자 세션) 토큰으로 워크스페이스 목록 조회 — 온보딩에서 org/프로젝트 탐색용.
    public func workspaces(adminToken: String) async throws -> [Workspace] {
        let data = try await request("workspaces", "GET", "/v1/workspace", tokenOverride: adminToken)
        guard let arr = try obj(data, "workspaces")["workspaces"] as? [[String: Any]] else {
            throw InfisicalError.parse(step: "workspaces")
        }
        return arr.compactMap { w in
            guard let id = (w["id"] ?? w["_id"]) as? String, let name = w["name"] as? String else { return nil }
            let envs = (w["environments"] as? [[String: Any]] ?? []).compactMap { e -> ProjectEnvironment? in
                guard let slug = e["slug"] as? String else { return nil }
                return ProjectEnvironment(name: e["name"] as? String ?? slug, slug: slug)
            }
            return Workspace(id: id, name: name, orgId: w["orgId"] as? String ?? "", environments: envs)
        }
    }

    /// identity 생성 → Universal Auth 부착 → client secret 발급 → 프로젝트 멤버십 부여.
    /// 관리자 토큰은 이 호출 동안만 사용되고 어디에도 저장되지 않는다.
    /// 반환된 자격은 호출자가 Keychain 에 저장한다.
    public func provision(adminToken: String, orgId: String, identityName: String,
                          orgRole: String = "member", projectIds: [String],
                          projectRole: String = "admin") async throws -> (clientId: String, clientSecret: String) {
        // 1) identity 생성
        let created = try await request("create-identity", "POST", "/v1/identities", json: [
            "name": identityName, "organizationId": orgId, "role": orgRole,
        ], tokenOverride: adminToken)
        guard let identityId = (try obj(created, "create-identity")["identity"] as? [String: Any])?["id"] as? String else {
            throw InfisicalError.parse(step: "create-identity")
        }

        // 2) Universal Auth 부착 (이미 있으면 GET 으로 clientId 회수)
        let uaPath = "/v1/auth/universal-auth/identities/\(escape(identityId))"
        let uaBody: [String: Any] = [
            "accessTokenTTL": 2_592_000, "accessTokenMaxTTL": 2_592_000, "accessTokenNumUsesLimit": 0,
            "clientSecretTrustedIps": [["ipAddress": "0.0.0.0/0"]],
            "accessTokenTrustedIps": [["ipAddress": "0.0.0.0/0"]],
        ]
        let clientId: String
        do {
            let uaData = try await request("universal-auth", "POST", uaPath, json: uaBody, tokenOverride: adminToken)
            guard let cid = (try obj(uaData, "universal-auth")["identityUniversalAuth"] as? [String: Any])?["clientId"] as? String else {
                throw InfisicalError.parse(step: "universal-auth")
            }
            clientId = cid
        } catch InfisicalError.http {
            let uaData = try await request("universal-auth-get", "GET", uaPath, tokenOverride: adminToken)
            guard let cid = (try obj(uaData, "universal-auth-get")["identityUniversalAuth"] as? [String: Any])?["clientId"] as? String else {
                throw InfisicalError.parse(step: "universal-auth-get")
            }
            clientId = cid
        }

        // 3) client secret 발급
        let csData = try await request("create-client-secret", "POST", uaPath + "/client-secrets", json: [
            "description": "provisioned by Infisical Manager onboarding", "numUsesLimit": 0, "ttl": 0,
        ], tokenOverride: adminToken)
        guard let secret = try obj(csData, "create-client-secret")["clientSecret"] as? String else {
            throw InfisicalError.parse(step: "create-client-secret")
        }

        // 4) 프로젝트 멤버십 (이미 있으면 400/409 관대)
        for projectId in projectIds {
            do {
                _ = try await request("project-membership", "POST",
                                      "/v2/workspace/\(escape(projectId))/identity-memberships/\(escape(identityId))",
                                      json: ["role": projectRole], tokenOverride: adminToken)
            } catch InfisicalError.http(_, let status, _) where status == 400 || status == 409 {
                // 이미 멤버 — 무시
            }
        }

        return (clientId, secret)
    }

    private func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
    }
}
