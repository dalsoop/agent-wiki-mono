import Foundation
import Security
import SigV4Kit
import WikiLedgerKit

// agent-law R2 — 전용 버킷 `agent-law`, 전용 접근 키(키체인 서비스 `agent-law-r2`).
// 근거: docs/security.md "R2 와 세션", docs/architecture.md "agent-law (ledger 3)", 결정 0007.
// - 키는 키체인에서만 읽는다. 환경 변수·설정 파일로 받지 않는다. 엔드포인트·버킷 이름은 호스트 설정(`lawStorage`).
// - 이미 쓴 객체는 고치지 않는다: 쓰기는 조건부(`If-None-Match: *`, 있으면 실패). 지우기는 가림만 쓴다.
// 옛 원장 blob 동기화(`GujoBlobSync`·`GujoBlobConfig`)는 그대로 두고, 서명은 같은 정본(`SigV4Kit`)을 쓴다.

// MARK: - 저장소 계약

public enum LawObjectStoreError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 조건부 쓰기 실패 — 같은 주소에 이미 객체가 있다.
    case alreadyExists(String)
    /// 같은 주소에 다른 내용이 있다(덧붙이기 규칙 위반).
    case conflict(String)
    case notFound(String)
    /// 네트워크 끊김·도달 실패.
    case unreachable(String)
    /// 그 밖의 HTTP 거부.
    case rejected(status: Int, detail: String)
    case configuration(String)
    /// 호스트 설정에 엔드포인트가 없다(`world storage --endpoint`).
    case endpointMissing

    public var description: String {
        switch self {
        case .alreadyExists(let key): return "R2 객체가 이미 있음: \(key)"
        case .conflict(let key): return "같은 R2 주소에 다른 내용이 있음: \(key)"
        case .notFound(let key): return "R2 객체 없음: \(key)"
        case .unreachable(let detail): return "R2 도달 실패: \(detail)"
        case .rejected(let status, let detail): return detail.isEmpty ? "R2 \(status)" : "R2 \(status): \(detail)"
        case .configuration(let detail): return "R2 설정 오류: \(detail)"
        case .endpointMissing: return LawStorageSettings.missingEndpointGuidance
        }
    }

    /// 다음 실행에서 다시 시도하면 되는 실패인가.
    public var isTransient: Bool {
        switch self {
        case .unreachable: return true
        case .rejected(let status, _): return status >= 500 || status == 429
        default: return false
        }
    }
}

/// agent-law 객체 저장소. 실제는 `LawR2Client`, 시험은 메모리 가짜를 주입한다.
public protocol LawObjectStore: Sendable {
    /// 조건부 쓰기. 같은 주소에 객체가 있으면 `alreadyExists`.
    func putIfAbsent(key: String, data: Data, contentType: String) throws
    func get(key: String) throws -> Data
    func exists(key: String) throws -> Bool
    /// 가림 전용. 없는 객체는 성공으로 본다.
    func delete(key: String) throws
    /// 앞부분이 `prefix` 인 키 전부(정렬).
    func list(prefix: String) throws -> [String]
}

public enum LawImmutablePut: Equatable, Sendable {
    case written
    /// 같은 주소에 같은 바이트가 이미 있었다(재시도 멱등).
    case identical
}

extension LawObjectStore {
    /// 덧붙이기 쓰기: 조건부로 쓰고, 이미 있으면 바이트를 비교해 같으면 멱등 성공, 다르면 `conflict`.
    @discardableResult
    public func putImmutable(key: String, data: Data, contentType: String = "application/octet-stream") throws
        -> LawImmutablePut
    {
        do {
            try putIfAbsent(key: key, data: data, contentType: contentType)
            return .written
        } catch LawObjectStoreError.alreadyExists {
            let present = try get(key: key)
            guard present == data else { throw LawObjectStoreError.conflict(key) }
            return .identical
        }
    }
}

// MARK: - 설정(비밀 아님)

/// 호스트 설정의 R2 자리(`lawStorage`). 비밀이 아닌 엔드포인트·버킷·지역만 둔다.
public struct LawStorageSettings: Codable, Equatable, Sendable {
    public var endpoint: String?
    public var bucket: String?
    public var region: String?

    /// 버킷 이름은 결정 0007 이 정한 전용 버킷.
    public static let defaultBucket = LawLedgerDefaults.bucketName
    public static let defaultRegion = "auto"
    /// 엔드포인트가 없을 때의 안내. 엔드포인트는 소스에 두지 않고 호스트 설정에서만 받는다
    /// (docs/standards.md "원격 호스트 주소는 … 설정에서 얻는다", docs/security.md "R2 와 세션").
    public static let missingEndpointGuidance = "R2 엔드포인트 미설정 — `agent-wiki world storage --endpoint <url>`"

    public init(endpoint: String? = nil, bucket: String? = nil, region: String? = nil) {
        self.endpoint = endpoint
        self.bucket = bucket
        self.region = region
    }

    /// 설정한 엔드포인트. 없으면 nil — R2 를 쓰는 명령은 `missingEndpointGuidance` 로 실패하거나 그 단계를 건너뛴다.
    public var resolvedEndpoint: String? { nonEmpty(endpoint) }
    public var resolvedBucket: String { nonEmpty(bucket) ?? Self.defaultBucket }
    public var resolvedRegion: String { nonEmpty(region) ?? Self.defaultRegion }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - 자격(키체인)

/// R2 접근 키 한 벌. 출력·로그에 값이 드러나지 않게 설명은 가린다.
public struct LawR2Credentials: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let accessKeyID: String
    public let secretAccessKey: String

    public init(accessKeyID: String, secretAccessKey: String) {
        self.accessKeyID = accessKeyID
        self.secretAccessKey = secretAccessKey
    }

    public var description: String { "LawR2Credentials(***)" }
    public var debugDescription: String { description }
}

public enum LawR2CredentialError: Error, Equatable, Sendable, CustomStringConvertible {
    case missing(service: String, account: String)
    case unreadable(service: String, account: String, status: Int32)

    public var description: String {
        switch self {
        case .missing(let service, let account):
            return "R2 키 없음: 키체인 서비스 '\(service)' 계정 '\(account)' — 금고에서 꺼내 키체인에 넣어 주세요"
                + " (docs/operations.md agent-law 절). 환경 변수·설정 파일로는 받지 않습니다"
        case .unreadable(let service, let account, let status):
            return "R2 키를 읽을 수 없음: 키체인 서비스 '\(service)' 계정 '\(account)' (상태 \(status))"
        }
    }
}

public protocol LawR2CredentialProviding: Sendable {
    func credentials() throws -> LawR2Credentials
}

/// 키체인 공급자. 서비스 `agent-law-r2`, 계정 `access-key-id`·`secret-access-key`.
/// 시험은 `lookup` 을 주입한다(실제 키체인을 읽지 않는다).
public struct LawKeychainCredentialProvider: LawR2CredentialProviding {
    public static let service = "agent-law-r2"
    public static let accessKeyAccount = "access-key-id"
    public static let secretKeyAccount = "secret-access-key"

    /// (서비스, 계정) → 값. nil 이면 없음. 읽기 오류는 `LawR2CredentialError.unreadable` 로 던진다.
    public typealias Lookup = @Sendable (_ service: String, _ account: String) throws -> String?

    let lookup: Lookup

    public init(lookup: @escaping Lookup = LawKeychainCredentialProvider.systemLookup) {
        self.lookup = lookup
    }

    public func credentials() throws -> LawR2Credentials {
        func read(_ account: String) throws -> String {
            guard let value = try lookup(Self.service, account)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty
            else { throw LawR2CredentialError.missing(service: Self.service, account: account) }
            return value
        }
        return LawR2Credentials(
            accessKeyID: try read(Self.accessKeyAccount), secretAccessKey: try read(Self.secretKeyAccount))
    }

    /// 이 기기 로그인 키체인의 일반 암호 항목.
    public static let systemLookup: Lookup = { service, account in
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw LawR2CredentialError.unreadable(service: service, account: account, status: status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - HTTP 전송(주입 가능)

public struct LawHTTPResponse: Sendable, Equatable {
    public let status: Int
    public let body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol LawHTTPTransport: Sendable {
    /// 응답을 받으면 상태 코드와 본문, 도달 실패면 `LawObjectStoreError.unreachable`.
    func send(_ request: URLRequest) throws -> LawHTTPResponse
}

public struct LawURLSessionTransport: LawHTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) throws -> LawHTTPResponse {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: Result<LawHTTPResponse, LawObjectStoreError> = .failure(.unreachable("응답 없음"))
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error {
                outcome = .failure(.unreachable(error.localizedDescription))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                outcome = .failure(.unreachable("HTTP 응답 아님"))
                return
            }
            outcome = .success(LawHTTPResponse(status: http.statusCode, body: data ?? Data()))
        }.resume()
        semaphore.wait()
        return try outcome.get()
    }
}

// MARK: - R2 클라이언트

/// S3 호환 R2 요청(SigV4 서명). 조건부 쓰기·읽기·있음 확인·가림 지우기·나열.
public struct LawR2Client: LawObjectStore {
    public let settings: LawStorageSettings
    let credentials: LawR2Credentials
    let transport: any LawHTTPTransport
    let now: @Sendable () -> Date

    public init(
        settings: LawStorageSettings, credentials: LawR2Credentials,
        transport: any LawHTTPTransport = LawURLSessionTransport(), now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.credentials = credentials
        self.transport = transport
        self.now = now
    }

    /// 호스트 설정 + 키체인. 엔드포인트가 없으면 `LawObjectStoreError.endpointMissing`(키체인을 읽기 전),
    /// 키가 없으면 `LawR2CredentialError.missing`.
    public static func standard(
        file: BoundLedgerFile, provider: any LawR2CredentialProviding = LawKeychainCredentialProvider()
    ) throws -> LawR2Client {
        let settings = file.lawStorage ?? LawStorageSettings()
        guard settings.resolvedEndpoint != nil else { throw LawObjectStoreError.endpointMissing }
        return LawR2Client(settings: settings, credentials: try provider.credentials())
    }

    public func putIfAbsent(key: String, data: Data, contentType: String) throws {
        let response = try send(
            method: "PUT", key: key, query: [], body: data,
            extraHeaders: [("If-None-Match", "*"), ("Content-Type", contentType)])
        switch response.status {
        case 200..<300: return
        case 412: throw LawObjectStoreError.alreadyExists(key)
        default: throw Self.failure(response)
        }
    }

    public func get(key: String) throws -> Data {
        let response = try send(method: "GET", key: key, query: [], body: nil)
        switch response.status {
        case 200..<300: return response.body
        case 404: throw LawObjectStoreError.notFound(key)
        default: throw Self.failure(response)
        }
    }

    public func exists(key: String) throws -> Bool {
        let response = try send(method: "HEAD", key: key, query: [], body: nil)
        switch response.status {
        case 200..<300: return true
        case 404: return false
        default: throw Self.failure(response)
        }
    }

    public func delete(key: String) throws {
        let response = try send(method: "DELETE", key: key, query: [], body: nil)
        switch response.status {
        case 200..<300, 404: return
        default: throw Self.failure(response)
        }
    }

    public func list(prefix: String) throws -> [String] {
        var keys: [String] = []
        var token: String?
        repeat {
            var query = [("list-type", "2"), ("prefix", prefix)]
            if let token { query.append(("continuation-token", token)) }
            let response = try send(method: "GET", key: nil, query: query, body: nil)
            guard (200..<300).contains(response.status) else { throw Self.failure(response) }
            let xml = String(decoding: response.body, as: UTF8.self)
            keys += GujoBlobSync.xmlValues(xml, tag: "Key").map(Self.xmlUnescape)
            token = xml.contains("<IsTruncated>true</IsTruncated>")
                ? GujoBlobSync.xmlValues(xml, tag: "NextContinuationToken").first.map(Self.xmlUnescape) : nil
        } while token != nil
        return keys.sorted()
    }

    // MARK: 요청

    /// 키의 각 조각을 RFC 3986 비예약 글자 밖은 퍼센트 인코딩한다(서명 경로와 요청 경로가 같아야 한다).
    static func encodedPath(bucket: String, key: String?) -> String {
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~")
        func enc(_ segment: Substring) -> String {
            String(segment).addingPercentEncoding(withAllowedCharacters: unreserved) ?? String(segment)
        }
        var path = "/" + enc(Substring(bucket))
        if let key {
            path += "/" + key.split(separator: "/", omittingEmptySubsequences: false).map(enc).joined(separator: "/")
        }
        return path
    }

    func makeRequest(
        method: String, key: String?, query: [(String, String)], body: Data?,
        extraHeaders: [(String, String)] = []
    ) throws -> URLRequest {
        guard let raw = settings.resolvedEndpoint else { throw LawObjectStoreError.endpointMissing }
        guard let endpoint = URL(string: raw), let host = endpoint.host else {
            throw LawObjectStoreError.configuration("엔드포인트가 URL 이 아님: \(raw)")
        }
        let path = Self.encodedPath(bucket: settings.resolvedBucket, key: key)
        let canonicalQuery = SigV4Signer.canonicalQuery(query)
        let payloadHash = body.map { LawHash.sha256Hex($0) } ?? SigV4Signer.emptyPayloadHash
        let amzDate = GujoBlobSync.amzDateFormatter.string(from: now())
        let hostHeader = endpoint.port.map { "\(host):\($0)" } ?? host
        let signer = SigV4Signer(
            accessKey: credentials.accessKeyID, secretKey: credentials.secretAccessKey,
            region: settings.resolvedRegion, service: "s3")
        let authorization = signer.authorization(
            method: method, canonicalUri: path, canonicalQueryString: canonicalQuery,
            headers: [("host", hostHeader), ("x-amz-content-sha256", payloadHash), ("x-amz-date", amzDate)],
            payloadHash: payloadHash, amzDate: amzDate, dateStamp: String(amzDate.prefix(8)))

        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = host
        components.port = endpoint.port
        components.percentEncodedPath = path
        if !canonicalQuery.isEmpty { components.percentEncodedQuery = canonicalQuery }
        guard let url = components.url else { throw LawObjectStoreError.configuration("URL 조립 실패") }

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        for (name, value) in extraHeaders { request.setValue(value, forHTTPHeaderField: name) }
        return request
    }

    private func send(
        method: String, key: String?, query: [(String, String)], body: Data?,
        extraHeaders: [(String, String)] = []
    ) throws -> LawHTTPResponse {
        try transport.send(
            makeRequest(method: method, key: key, query: query, body: body, extraHeaders: extraHeaders))
    }

    /// 거부 응답 → 오류. 응답 본문(요청 주소·버킷 정보가 섞일 수 있다)은 남기지 않고 S3 오류 `Code` 만 남긴다.
    static func failure(_ response: LawHTTPResponse) -> LawObjectStoreError {
        .rejected(status: response.status, detail: errorCode(response.body) ?? "")
    }

    /// S3 오류 XML 의 `<Code>…</Code>`. 영문자·숫자·`.`·`-`·`_` 만으로 된 64자 이내 값만 받는다.
    static func errorCode(_ body: Data) -> String? {
        let text = String(decoding: body.prefix(4096), as: UTF8.self)
        guard let open = text.range(of: "<Code>"),
              let close = text.range(of: "</Code>", range: open.upperBound..<text.endIndex)
        else { return nil }
        let code = String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        guard !code.isEmpty, code.count <= 64, code.unicodeScalars.allSatisfy({ allowed.contains($0) && $0.isASCII })
        else { return nil }
        return code
    }

    static func xmlUnescape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - gzip

public enum LawGzipError: Error, Equatable, Sendable {
    case notGzip
    case corrupt
}

/// 세션 조각 압축(`.jsonl.gz`). 머리 시각을 0 으로 두어 같은 입력은 같은 바이트가 된다(재시도 멱등).
public enum LawGzip {
    public static func compress(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        out.append(deflated)
        appendLE(&out, crc32(data))
        appendLE(&out, UInt32(truncatingIfNeeded: data.count))
        return out
    }

    public static func decompress(_ gz: Data) throws -> Data {
        let bytes = [UInt8](gz)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 0x08 else { throw LawGzipError.notGzip }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 {
            guard index + 2 <= bytes.count else { throw LawGzipError.corrupt }
            index += 2 + Int(bytes[index]) + Int(bytes[index + 1]) << 8
        }
        if flags & 0x08 != 0 { index = try skipZeroTerminated(bytes, from: index) }
        if flags & 0x10 != 0 { index = try skipZeroTerminated(bytes, from: index) }
        if flags & 0x02 != 0 { index += 2 }
        guard index <= bytes.count - 8 else { throw LawGzipError.corrupt }
        let raw = Data(bytes[index..<(bytes.count - 8)])
        let inflated: Data
        do {
            inflated = try (raw as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw LawGzipError.corrupt
        }
        let trailer = Array(bytes[(bytes.count - 8)...])
        guard readLE(trailer, 0) == crc32(inflated),
              readLE(trailer, 4) == UInt32(truncatingIfNeeded: inflated.count)
        else { throw LawGzipError.corrupt }
        return inflated
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        var index = start
        while index < bytes.count, bytes[index] != 0 { index += 1 }
        guard index < bytes.count else { throw LawGzipError.corrupt }
        return index + 1
    }

    private static func appendLE(_ data: inout Data, _ value: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> UInt32(shift)) & 0xFF)) }
    }

    private static func readLE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << UInt32($1 * 8) }
    }

    static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = crc & 1 != 0 ? 0xEDB8_8320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}
