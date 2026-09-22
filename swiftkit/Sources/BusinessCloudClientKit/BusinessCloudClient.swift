import Foundation
import HTTPClientKit
import InteropKit
import MoneyLedgerModels

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - 서버 응답 결과타입(App.swift 응답 계약과 1:1)

/// `DELETE /<entity>/:id` 응답 본문. App.swift registerSimpleEntity DELETE 핸들러가
/// `API.ok(["deleted": id])` 로 반환한다 — 그 result 키가 `deleted` 이다(spec 의 `id` 가 아님).
public struct BusinessCloudDeleteResult: Codable, Sendable, Equatable {
    public let deleted: String
}

/// `PUT /transactions/:id` 응답 본문. content_hash 멱등 — 서버가 duplicate 여부를 판정한다.
/// App.swift 의 `TransactionMutationResponse` 와 같다.
public struct BusinessCloudTransactionUpsert: Codable, Sendable, Equatable {
    public let transaction: MoneyTransaction
    public let duplicate: Bool
}

/// `GET /sync/changes` 응답 본문. cursor = 처리 행들의 max(updated_at) ISO8601.
/// 각 엔티티 키는 요청한 CSV 항목(account/cards/.../import_batches)만 채워진다.
/// 파일럿은 upsert-only — delete/tombstone 전파는 미지원(한계).
public struct BusinessCloudSyncChanges: Codable, Sendable, Equatable {
    public struct Changes: Codable, Sendable, Equatable {
        public let accounts: [MoneyAccount]?
        public let cards: [MoneyCard]?
        public let subscriptions: [MoneySubscription]?
        public let transactions: [MoneyTransaction]?
        public let businesses: [BusinessProfile]?
        // snake_case 키 — 서버의 /import_batches 경로 토큰과 같다.
        public let import_batches: [ImportBatch]?
        public let attachments: [AttachmentRecord]?
    }

    public let cursor: String?
    public let changes: Changes

    public init(cursor: String?, changes: Changes) {
        self.cursor = cursor
        self.changes = changes
    }
}

// MARK: - 클라이언트

/// business-api 전용 typed CRUD + sync 클라이언트. HTTPClientKit 로 전송하고
/// InteropKit.Envelope 로 본문을 디코드한다. 인증은 매 요청 `Authorization: Bearer <token>`
/// 헤더(/health 제외).
public actor BusinessCloudClient {
    private let config: BusinessCloudConfig
    private let transport: any HTTPClient
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(config: BusinessCloudConfig, transport: any HTTPClient = URLSessionHTTPClient()) {
        self.config = config
        self.transport = transport
        decoder = JSONDecoder()
        // MoneyLedgerModels 의 createdAt: Date 등은 ISO8601 직렬. 서버의 JSON.encoder 와 정합.
        // (Envelope.decodeResult 은 기본 JSONDecoder 라 iso8601 미지원 — 직접 디코드.)
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    public func configuration() -> BusinessCloudConfig { config }

    // MARK: - Health (인증 면제)

    public func health() async throws -> Bool {
        let (status, _) = try await sendRaw(method: "GET", path: "/health", auth: false)
        return (200..<300).contains(status)
    }

    // MARK: - Transactions (특수: 필터 + content_hash 멱등)

    /// 거래 질의 필터. 서버 GET /transactions 쿼리파라미터(from/to/account_id/card_id/category) 와 1:1.
    /// from/to 는 `yyyy-MM-dd` — 서버가 payload->>'date' 와 사전순 비교한다.
    public struct TransactionFilter: Sendable, Equatable {
        public let from: String?
        public let to: String?
        public let accountID: String?
        public let cardID: String?
        public let category: String?

        public init(
            from: String? = nil,
            to: String? = nil,
            accountID: String? = nil,
            cardID: String? = nil,
            category: String? = nil
        ) {
            self.from = from
            self.to = to
            self.accountID = accountID
            self.cardID = cardID
            self.category = category
        }
    }

    public func listTransactions(filter: TransactionFilter = TransactionFilter()) async throws -> [MoneyTransaction] {
        var query: [String: String] = [:]
        if let v = filter.from { query["from"] = v }
        if let v = filter.to { query["to"] = v }
        if let v = filter.accountID { query["account_id"] = v }
        if let v = filter.cardID { query["card_id"] = v }
        if let v = filter.category { query["category"] = v }
        return try await request(method: "GET", path: "/transactions", query: query,
                                 as: [MoneyTransaction].self)
    }

    /// 거래 업서트 — content_hash 멱등. 동일 해시가 서버에 있으면 그 행을 돌려주고
    /// `duplicate == true`. 결과의 `transaction.id` 가 권위있는 id(서버가 이미 가진 id 일 수 있음).
    public func upsertTransaction(_ tx: MoneyTransaction) async throws -> BusinessCloudTransactionUpsert {
        let body = try encoder.encode(tx)
        return try await request(method: "PUT", path: "/transactions/\(tx.id)",
                                 body: body, as: BusinessCloudTransactionUpsert.self)
    }

    public func deleteTransaction(_ id: String) async throws -> BusinessCloudDeleteResult {
        try await deleteSimple(.transactions, id: id)
    }

    // MARK: - Sync

    /// `/sync/changes?since=<cursor>&entities=<csv>` — 증분 변경분 조회.
    /// since 생략시 전체. entities 비활성화시 명시한 엔티티만.
    public func syncChanges(
        since cursor: String?,
        entities: [BusinessCloudEntity] = BusinessCloudEntity.allCases
    ) async throws -> BusinessCloudSyncChanges {
        var query: [String: String] = [:]
        if let cursor, !cursor.isEmpty { query["since"] = cursor }
        // 빈 배열이면 파라미터 자체를 빼 "전체 엔티티" 로 해석시킨다(spec: 생략시 전체).
        if !entities.isEmpty {
            query["entities"] = entities.map(\.csvKey).joined(separator: ",")
        }
        return try await request(method: "GET", path: "/sync/changes", query: query,
                                 as: BusinessCloudSyncChanges.self)
    }

    // MARK: - 핵심 전송 + 봉투 디코드

    /// 단순 엔티티(registerSimpleEntity) 공통 list — include_archived 지원.
    func listSimple<T: Codable>(
        _ entity: BusinessCloudEntity,
        includeArchived: Bool,
        as type: T.Type
    ) async throws -> [T] {
        try await request(method: "GET", path: entity.path,
                          query: includeArchived ? ["include_archived": "true"] : [:],
                          as: [T].self)
    }

    /// 단순 엔티티 공통 upsert — `PUT /<entity>/:id`. path id 가 주권(바디 id 무시).
    func upsertSimple<T: Encodable & Decodable & Identifiable>(
        _ value: T,
        entity: BusinessCloudEntity
    ) async throws -> T where T.ID == String {
        let body = try encoder.encode(value)
        // value.id 가 T.ID == String 임을 보장.
        let id = value.id
        return try await request(method: "PUT", path: "\(entity.path)/\(id)",
                                 body: body, as: T.self)
    }

    /// 단순 엔티티 공통 delete — `DELETE /<entity>/:id` → `{deleted: "<id>"}`.
    func deleteSimple(
        _ entity: BusinessCloudEntity,
        id: String
    ) async throws -> BusinessCloudDeleteResult {
        try await request(method: "DELETE", path: "\(entity.path)/\(id)",
                          as: BusinessCloudDeleteResult.self)
    }

    private func request<Result: Codable>(
        method: String,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        auth: Bool = true,
        as type: Result.Type
    ) async throws -> Result {
        let (status, data) = try await sendRaw(method: method, path: path, query: query, body: body, auth: auth)
        return try decodeEnvelope(Result.self, status: status, data: data)
    }

    private func sendRaw(
        method: String,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        auth: Bool = true
    ) async throws -> (status: Int, data: Data) {
        // path 앞의 `/` 는 appendingPathComponent 가 중복 슬래시를 만들지 않도록 다듬는다.
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let resolved = config.baseURL.appendingPathComponent(trimmed)
        guard var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) else {
            throw BusinessCloudError.decode("잘못된 URL: \(resolved.absoluteString)")
        }
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            throw BusinessCloudError.decode("잘못된 URL: \(resolved.absoluteString)")
        }
        var headers = ["Accept": "application/json"]
        if body != nil { headers["Content-Type"] = "application/json" }
        if auth { headers["Authorization"] = "Bearer \(config.token)" }
        do {
            return try await transport.send(method: method, url: url, headers: headers, body: body)
        } catch {
            throw BusinessCloudError.transport(error.localizedDescription)
        }
    }

    /// InteropKit.Envelope.Success<Result> 를 iso8601 date 전략으로 디코드.
    /// 성공 봉투면 result, 실패 봉투/상태코드/비-JSON 을 BusinessCloudError 로 승격.
    ///
    /// Result 를 Codable 으로 잡은 것은 InteropKit.Envelope.Success<Result: Codable> 제약을
    /// 만족하기 위해서. 모든 응답 결과타입(도메인 모델·배열·DeleteResult·SyncChanges) 은
    /// 어차피 Codable 이라 범위 손해는 없다.
    private func decodeEnvelope<Result: Codable>(
        _ type: Result.Type,
        status: Int,
        data: Data
    ) throws -> Result {
        do {
            let success = try decoder.decode(Envelope.Success<Result>.self, from: data)
            if success.ok {
                return success.result
            }
        } catch {}
        do {
            let failure = try decoder.decode(Envelope.Failure.self, from: data)
            if !failure.ok {
                switch status {
                case 401: throw BusinessCloudError.unauthorized
                case 404: throw BusinessCloudError.notFound
                default: throw BusinessCloudError.server(failure.error.message)
                }
            }
        } catch let err as BusinessCloudError {
            throw err
        } catch {}
        // 봉투도 아니고 실패 봉투도 아닌 케이스 — 상태코드로 분기 후 malformed.
        switch status {
        case 401: throw BusinessCloudError.unauthorized
        case 404: throw BusinessCloudError.notFound
        case 200..<300:
            throw BusinessCloudError.decode(
                "봉투 구조가 계약과 다름(status=\(status), body=\(preview(data)))"
            )
        default:
            throw BusinessCloudError.http(status, preview(data))
        }
    }

    private func preview(_ data: Data) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        if raw.count > 240 {
            return String(raw.prefix(240)) + "…"
        }
        return raw
    }
}
