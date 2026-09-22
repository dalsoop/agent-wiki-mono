import Foundation

/// 서버 엔드포인트. 비트와든 클라우드는 identity/api 호스트가 분리돼 있고,
/// 자체 호스팅 Bitwarden 은 단일 URL 아래 `/identity`·`/api` 로 나뉜다.
public struct ServerEndpoint: Codable, Sendable, Equatable {
    public var identity: String   // 토큰/prelogin 베이스 (끝 슬래시 없음)
    public var api: String        // sync/ciphers 베이스
    public var label: String      // 저장·표시용 식별자

    public init(identity: String, api: String, label: String) {
        self.identity = identity
        self.api = api
        self.label = label
    }

    public static let cloudUS = ServerEndpoint(
        identity: "https://identity.bitwarden.com",
        api: "https://api.bitwarden.com",
        label: "bitwarden.com")

    public static let cloudEU = ServerEndpoint(
        identity: "https://identity.bitwarden.eu",
        api: "https://api.bitwarden.eu",
        label: "bitwarden.eu")

    /// 자체 호스팅 단일 URL → `/identity`·`/api` 하위로 매핑.
    public static func selfHosted(_ server: String) throws -> ServerEndpoint {
        var s = server.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if !s.contains("://") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else {
            throw VaultwardenAPI.APIError.badURL
        }
        return ServerEndpoint(identity: s + "/identity", api: s + "/api", label: url.host ?? s)
    }
}

/// 2FA 필요 신호 — 로그인 응답이 400 + TwoFactorProviders 일 때.
/// bitwarden.com 신규 기기 이메일 인증 — 서버가 OTP 메일을 보내고 재시도에 newDeviceOtp 를 요구한다.
public struct NewDeviceOtpRequired: Error, Sendable, Equatable {
    public init() {}
}

public struct TwoFactorRequired: Error, Sendable, Equatable {
    /// 사용 가능한 provider id 목록 (0=인증앱 TOTP, 1=이메일, 3=YubiKey …).
    public let providers: [Int]
    public var preferredProvider: Int {
        // 인증앱(0) > 이메일(1) > 그 외 첫 번째.
        if providers.contains(0) { return 0 }
        if providers.contains(1) { return 1 }
        return providers.first ?? 0
    }
}

/// Bitwarden / Bitwarden 호환 HTTP 클라이언트.
public struct VaultwardenAPI: Sendable {
    public enum APIError: Error, LocalizedError {
        case badURL
        case http(Int, String)

        public var errorDescription: String? {
            switch self {
            case .badURL: return "서버 URL이 올바르지 않습니다"
            case .http(let code, let body):
                if code == 400, body.contains("Username or password is incorrect") {
                    return "이메일 또는 마스터 패스워드가 올바르지 않습니다"
                }
                if code == 400, body.contains("Two-step token is invalid") || body.contains("Invalid TwoFactor") {
                    return "2단계 인증 코드가 올바르지 않습니다"
                }
                if code == 400, body.lowercased().contains("otp"), body.lowercased().contains("invalid") {
                    return "인증 코드가 올바르지 않습니다 — 이메일의 최신 코드를 다시 확인하세요"
                }
                if body.contains("new device") || body.contains("device verification") {
                    return "새 기기 인증이 필요합니다 — 이메일로 온 코드를 2FA 코드 칸에 입력하세요"
                }
                return "서버 오류 (\(code)): \(body.prefix(200))"
            }
        }
    }

    public let endpoint: ServerEndpoint
    private let session: URLSession

    public init(endpoint: ServerEndpoint, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    private func identityURL(_ path: String) throws -> URL {
        guard let u = URL(string: endpoint.identity + "/" + path) else { throw APIError.badURL }
        return u
    }
    private func apiURL(_ path: String) throws -> URL {
        // path 가 "/folders" 처럼 선행 슬래시를 가지면 api 호스트와 합쳐
        // `https://api.bitwarden.com//folders` 가 되어 404 가 난다(2026-08-08 실측).
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let u = URL(string: endpoint.api + "/" + trimmed) else { throw APIError.badURL }
        return u
    }

    // MARK: - Auth

    public func prelogin(email: String) async throws -> PreloginResponse {
        var req = URLRequest(url: try identityURL("accounts/prelogin"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["email": email])
        return try await send(req)
    }

    /// 로그인. 2FA 코드가 있으면 함께 보낸다.
    /// 서버가 2FA를 요구하면 `TwoFactorRequired` 를 throw 한다.
    public func login(email: String, passwordHash: String, deviceID: String,
                      twoFactor: (code: String, provider: Int, remember: Bool)? = nil,
                      newDeviceOtp: String? = nil) async throws -> TokenResponse {
        var form: [String: String] = [
            "grant_type": "password",
            "username": email,
            "password": passwordHash,
            "scope": "api offline_access",
            "client_id": "desktop",
            "deviceType": "6",              // macOS desktop
            "deviceIdentifier": deviceID,
            "deviceName": "EnvVault",
        ]
        if let tf = twoFactor {
            form["twoFactorToken"] = tf.code
            form["twoFactorProvider"] = String(tf.provider)
            form["twoFactorRemember"] = tf.remember ? "1" : "0"
        }
        if let otp = newDeviceOtp {
            form["newDeviceOtp"] = otp
        }
        do {
            return try await postForm(try identityURL("connect/token"), form: form)
        } catch let APIError.http(code, body) where code == 400 && body.contains("TwoFactorProviders") {
            throw parseTwoFactor(body)
        } catch let APIError.http(code, body) where code == 400
                    && body.lowercased().contains("device") && body.lowercased().contains("verification") {
            // "new device verification required ..." — 서버가 이메일로 OTP 를 이미 발송했다.
            throw NewDeviceOtpRequired()
        }
    }

    public func refresh(refreshToken: String) async throws -> TokenResponse {
        try await postForm(try identityURL("connect/token"), form: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "desktop",
        ])
    }

    // MARK: - Vault

    public func sync(token: String) async throws -> SyncResponse {
        try await request("GET", try apiURL("sync"), token: token)
    }

    public func createCipher(_ cipher: CipherDTO, token: String) async throws -> CipherDTO {
        try await request("POST", try apiURL("ciphers"), token: token, jsonBody: cipher)
    }

    public func updateCipher(_ cipher: CipherDTO, token: String) async throws -> CipherDTO {
        guard let id = cipher.id else { throw APIError.badURL }
        return try await request("PUT", try apiURL("ciphers/\(id)"), token: token, jsonBody: cipher)
    }

    /// 저장 전에 서버 원본 URI 를 읽어 빈 페이로드로 덮어쓰지 않기 위해 쓴다.
    public func getCipher(id: String, token: String) async throws -> CipherDTO {
        try await request("GET", try apiURL("ciphers/\(id)"), token: token)
    }

    public func restoreCipher(id: String, token: String) async throws {
        let _: EmptyResponse = try await request("PUT", try apiURL("ciphers/\(id)/restore"), token: token,
                                                 jsonBody: EmptyBody())
    }

    /// 영구 삭제(휴지통에서 제거).
    public func purgeCipher(id: String, token: String) async throws {
        let _: EmptyResponse = try await request("DELETE", try apiURL("ciphers/\(id)"), token: token,
                                                 jsonBody: Optional<EmptyBody>.none)
    }

    // MARK: - 첨부파일 (v2 업로드 플로우)

    /// 1단계: 첨부 자리 예약 — 암호화된 파일명·크기·첨부키를 올리고 업로드 URL 을 받는다.
    public func requestAttachmentUpload(
        cipherID: String, encryptedFileName: String, fileSize: Int, encryptedKey: String, token: String
    ) async throws -> AttachmentUploadTicket {
        let url = try apiURL("/ciphers/\(cipherID)/attachment/v2")
        let body: [String: Any] = [
            "fileName": encryptedFileName,
            "fileSize": fileSize,
            "key": encryptedKey,
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(request)
    }

    /// 2단계: 암호화된 본문 업로드(Direct = 서버 multipart).
    public func uploadAttachmentData(
        cipherID: String, attachmentID: String, encryptedFileName: String,
        payload: Data, uploadURL: String, fileUploadType: Int, token: String
    ) async throws {
        let boundary = "----swiftkit-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data(
            "Content-Disposition: form-data; name=\"data\"; filename=\"\(encryptedFileName)\"\r\n".utf8
        ))
        body.append(Data("Content-Type: application/octet-stream\r\n\r\n".utf8))
        body.append(payload)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let target: URL
        if fileUploadType == 1, let direct = URL(string: uploadURL) {
            target = direct  // Azure 사전서명 URL
        } else {
            target = try apiURL("/ciphers/\(cipherID)/attachment/\(attachmentID)")
        }
        var request = URLRequest(url: target)
        request.httpMethod = "POST"
        if fileUploadType != 1 {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        _ = try await sendRaw(request)
    }

    /// 첨부 다운로드 URL 조회(만료 있는 사전서명 URL).
    public func attachmentDownloadURL(
        cipherID: String, attachmentID: String, token: String
    ) async throws -> String {
        let url = try apiURL("/ciphers/\(cipherID)/attachment/\(attachmentID)")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let dto: AttachmentDTO = try await send(request)
        guard let downloadURL = dto.url else { throw APIError.badURL }
        return downloadURL
    }

    public func deleteAttachment(cipherID: String, attachmentID: String, token: String) async throws {
        let url = try apiURL("/ciphers/\(cipherID)/attachment/\(attachmentID)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await sendRaw(request)
    }

    /// 본문 응답이 없는(혹은 JSON 이 아닌) 요청용.
    @discardableResult
    private func sendRaw(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.http(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                String(data: data, encoding: .utf8) ?? ""
            )
        }
        return data
    }

    // MARK: - 폴더(분류)

    /// 폴더 생성 — name 은 userKey 로 암호화된 EncString.
    public func createFolder(encryptedName: String, token: String) async throws -> FolderDTO {
        let url = try apiURL("/folders")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": encryptedName])
        return try await send(request)
    }

    public func updateFolder(id: String, encryptedName: String, token: String) async throws -> FolderDTO {
        let url = try apiURL("/folders/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": encryptedName])
        return try await send(request)
    }

    /// 폴더 삭제 — 서버가 소속 항목의 folderId 를 비운다(항목은 남는다).
    public func deleteFolder(id: String, token: String) async throws {
        let url = try apiURL("/folders/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await sendRaw(request)
    }

    public func deleteCipher(id: String, token: String) async throws {
        let _: EmptyResponse = try await request("PUT", try apiURL("ciphers/\(id)/delete"), token: token,
                                                 jsonBody: EmptyBody())
    }

    // MARK: - 내부 헬퍼

    struct EmptyResponse: Decodable {}
    struct EmptyBody: Encodable {}

    /// 로그인 400 응답의 TwoFactorProviders 배열을 파싱.
    private func parseTwoFactor(_ body: String) -> TwoFactorRequired {
        guard let data = body.data(using: .utf8),
              let obj = VaultwardenJSON.object(from: data) else {
            return TwoFactorRequired(providers: [0])
        }
        // "TwoFactorProviders":["0","1"] 또는 "TwoFactorProviders2":{"0":{...}}
        var ids: [Int] = []
        if let arr = (obj["TwoFactorProviders"] ?? obj["twoFactorProviders"]) as? [Any] {
            ids = arr.compactMap { ($0 as? Int) ?? Int("\($0)") }
        }
        if ids.isEmpty, let dict = (obj["TwoFactorProviders2"] ?? obj["twoFactorProviders2"]) as? [String: Any] {
            ids = dict.keys.compactMap { Int($0) }
        }
        return TwoFactorRequired(providers: ids.isEmpty ? [0] : ids.sorted())
    }

    private func postForm<R: Decodable>(_ url: URL, form: [String: String]) async throws -> R {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        req.httpBody = form.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&").data(using: .utf8)
        return try await send(req)
    }

    private func request<R: Decodable>(_ method: String, _ url: URL, token: String,
                                       jsonBody: (some Encodable)? = Optional<EmptyBody>.none) async throws -> R {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let jsonBody {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(jsonBody)
        }
        return try await send(req)
    }

    /// bitwarden.com 은 클라이언트 식별 헤더가 없으면 400(version_header_missing)을 낸다.
    /// 공식 데스크톱 클라이언트와 같은 형태로 보낸다. Device-Type 7 = macOS Desktop.
    static let clientName = "desktop"
    static let clientVersion = "2025.6.0"

    private func send<R: Decodable>(_ request: URLRequest) async throws -> R {
        var req = request
        req.setValue(Self.clientName, forHTTPHeaderField: "Bitwarden-Client-Name")
        req.setValue(Self.clientVersion, forHTTPHeaderField: "Bitwarden-Client-Version")
        req.setValue("7", forHTTPHeaderField: "Device-Type")
        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw APIError.http(code, String(decoding: data, as: UTF8.self))
        }
        if R.self == EmptyResponse.self, let empty = EmptyResponse() as? R { return empty }
        return try JSONDecoder().decode(R.self, from: data.isEmpty ? Data("{}".utf8) : data)
    }
}
