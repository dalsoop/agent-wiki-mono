import Foundation

/// 형태를 미리 못 박지 않은 JSON(health·reports·audit·events 같은 서버 주도 페이로드).
/// 타입 모델이 있는 리소스는 이걸 쓰지 않는다.
public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        guard let value = Self.decodeValue(container) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "JSON 값이 아님")
        }
        self = value
    }

    private static func decodeValue(_ container: SingleValueDecodingContainer) -> JSONValue? {
        if container.decodeNil() { return .null }
        let probes: [() -> JSONValue?] = [
            { probe(container, as: Bool.self).map(JSONValue.bool) },
            { probe(container, as: Double.self).map(JSONValue.number) },
            { probe(container, as: String.self).map(JSONValue.string) },
            { probe(container, as: [JSONValue].self).map(JSONValue.array) },
            { probe(container, as: [String: JSONValue].self).map(JSONValue.object) },
        ]
        return probes.lazy.compactMap { $0() }.first
    }

    private static func probe<T: Decodable>(
        _ container: SingleValueDecodingContainer, as type: T.Type
    ) -> T? {
        do {
            return try container.decode(T.self)
        } catch {
            return nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}

public typealias JSONObject = [String: JSONValue]

/// Laravel 페이지네이션 봉투(`data` + `meta`). `meta` 가 없는 단순 배열 응답도 받는다.
public struct Page<Item: Decodable & Sendable>: Decodable, Sendable {
    public var data: [Item]
    public var currentPage: Int?
    public var lastPage: Int?
    public var total: Int?

    private struct Meta: Decodable {
        var currentPage: Int?
        var lastPage: Int?
        var total: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case data, meta
    }

    public init(data: [Item], currentPage: Int? = nil, lastPage: Int? = nil, total: Int? = nil) {
        self.data = data
        self.currentPage = currentPage
        self.lastPage = lastPage
        self.total = total
    }

    public init(from decoder: Decoder) throws {
        do {
            let list = try decoder.singleValueContainer().decode([Item].self)
            self.init(data: list)
            return
        } catch {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let data = try container.decode([Item].self, forKey: .data)
            let meta = try container.decodeIfPresent(Meta.self, forKey: .meta)
            self.init(data: data, currentPage: meta?.currentPage, lastPage: meta?.lastPage, total: meta?.total)
        }
    }
}

/// 단건 봉투 — Laravel 리소스는 `{ "data": {...} }` 로도, 맨몸으로도 온다.
public struct Single<Item: Decodable & Sendable>: Decodable, Sendable {
    public var data: Item

    public init(data: Item) { self.data = data }

    public init(from decoder: Decoder) throws {
        do {
            self.data = try decoder.container(keyedBy: DataKey.self).decode(Item.self, forKey: .data)
        } catch {
            self.data = try Item(from: decoder)
        }
    }

    private enum DataKey: String, CodingKey { case data }
}

// MARK: - commerce

public struct Customer: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String?
    public var email: String?
    public var createdAt: Date?
    public var updatedAt: Date?
}

public struct CustomerDraft: Encodable, Equatable, Sendable {
    public var name: String?
    public var email: String?
    public init(name: String? = nil, email: String? = nil) {
        self.name = name
        self.email = email
    }
}

public struct CustomerDevice: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String?
    public var platform: String?
    public var lastSeenAt: Date?
    public var revokedAt: Date?
}

public struct Invoice: Codable, Equatable, Sendable {
    public var id: Int
    public var number: String?
    public var status: String?
    public var amount: Double?
    public var currency: String?
    public var issuedAt: Date?
}

public struct CreditNote: Codable, Equatable, Sendable {
    public var id: Int
    public var invoiceId: Int?
    public var amount: Double?
    public var currency: String?
    public var reason: String?
    public var createdAt: Date?
}

public struct CreditNoteDraft: Encodable, Equatable, Sendable {
    public var invoiceId: Int?
    public var amount: Double
    public var reason: String?
    public init(invoiceId: Int? = nil, amount: Double, reason: String? = nil) {
        self.invoiceId = invoiceId
        self.amount = amount
        self.reason = reason
    }
}

public struct CreditBalance: Codable, Equatable, Sendable {
    public var balance: Double
    public var currency: String?
}

public struct EntitlementChange: Encodable, Equatable, Sendable {
    public var productId: Int
    public var reason: String?
    public var expiresAt: Date?
    public init(productId: Int, reason: String? = nil, expiresAt: Date? = nil) {
        self.productId = productId
        self.reason = reason
        self.expiresAt = expiresAt
    }
}

public struct Product: Codable, Equatable, Sendable {
    public var id: Int
    public var slug: String?
    public var name: String?
    public var status: String?
    public var price: Double?
    public var currency: String?
}

public struct Order: Codable, Equatable, Sendable {
    public var id: Int
    public var status: String?
    public var customerId: Int?
    public var total: Double?
    public var currency: String?
    public var createdAt: Date?
}

public struct RefundRequest: Encodable, Equatable, Sendable {
    public var amount: Double?
    public var reason: String?
    public init(amount: Double? = nil, reason: String? = nil) {
        self.amount = amount
        self.reason = reason
    }
}

public struct Subscription: Codable, Equatable, Sendable {
    public var id: Int
    public var status: String?
    public var customerId: Int?
    public var productId: Int?
    public var renewsAt: Date?
    public var endsAt: Date?
}

public struct SubscriptionGrant: Encodable, Equatable, Sendable {
    public var customerId: Int
    public var productId: Int
    public var endsAt: Date?
    public var reason: String?
    public init(customerId: Int, productId: Int, endsAt: Date? = nil, reason: String? = nil) {
        self.customerId = customerId
        self.productId = productId
        self.endsAt = endsAt
        self.reason = reason
    }
}

// MARK: - support

public struct Inquiry: Codable, Equatable, Sendable {
    public var id: Int
    public var subject: String?
    public var status: String?
    public var customerId: Int?
    public var createdAt: Date?
    public var updatedAt: Date?
}

public struct InquiryMessage: Codable, Equatable, Sendable {
    public var id: Int
    public var author: String?
    public var body: String?
    public var createdAt: Date?
}

public struct InquiryMessageDraft: Encodable, Equatable, Sendable {
    public var body: String
    public init(body: String) { self.body = body }
}

// MARK: - ops

public struct OpsPackage: Codable, Equatable, Sendable {
    public var id: Int?
    public var slug: String
    public var version: String?
    public var channel: String?
    public var publishedAt: Date?
}

public struct OpsPackagePublish: Encodable, Equatable, Sendable {
    public var slug: String
    public var version: String
    public var channel: String?
    public var artifactUrl: String?
    public var sha256: String?
    public init(slug: String, version: String, channel: String? = nil, artifactUrl: String? = nil, sha256: String? = nil) {
        self.slug = slug
        self.version = version
        self.channel = channel
        self.artifactUrl = artifactUrl
        self.sha256 = sha256
    }
}

public struct OpsDevice: Codable, Equatable, Sendable {
    public var id: Int
    public var name: String?
    public var hostname: String?
    public var platform: String?
    public var lastSeenAt: Date?
}

public struct OpsDeviceDraft: Encodable, Equatable, Sendable {
    public var name: String?
    public var hostname: String?
    public var platform: String?
    public init(name: String? = nil, hostname: String? = nil, platform: String? = nil) {
        self.name = name
        self.hostname = hostname
        self.platform = platform
    }
}

public struct InstallJob: Codable, Equatable, Sendable {
    public var id: Int
    public var deviceId: Int?
    public var packageSlug: String?
    public var status: String?
    public var createdAt: Date?
}

public struct InstallJobDraft: Encodable, Equatable, Sendable {
    public var deviceId: Int
    public var packageSlug: String
    public var version: String?
    public init(deviceId: Int, packageSlug: String, version: String? = nil) {
        self.deviceId = deviceId
        self.packageSlug = packageSlug
        self.version = version
    }
}

public struct Runner: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    public var status: String?
    public var lastHeartbeatAt: Date?
}

public struct RunnerHeartbeat: Encodable, Equatable, Sendable {
    public var status: String
    public var load: Double?
    public init(status: String, load: Double? = nil) {
        self.status = status
        self.load = load
    }
}

public struct ReceiptIngest: Encodable, Equatable, Sendable {
    public var receipts: [JSONValue]
    public init(receipts: [JSONValue]) { self.receipts = receipts }
}

// MARK: - intake · skills

public struct ReleaseIntake: Encodable, Equatable, Sendable {
    public var slug: String
    public var version: String
    public var artifactUrl: String?
    public var sha256: String?
    public var notes: String?
    public init(slug: String, version: String, artifactUrl: String? = nil, sha256: String? = nil, notes: String? = nil) {
        self.slug = slug
        self.version = version
        self.artifactUrl = artifactUrl
        self.sha256 = sha256
        self.notes = notes
    }
}

public struct ReleaseIntakeReceipt: Codable, Equatable, Sendable {
    public var id: Int?
    public var slug: String?
    public var version: String?
    public var status: String?
}

public struct SkillPublish: Encodable, Equatable, Sendable {
    public var slug: String
    public var version: String
    public var manifest: JSONValue
    public init(slug: String, version: String, manifest: JSONValue) {
        self.slug = slug
        self.version = version
        self.manifest = manifest
    }
}

public struct SkillRecord: Codable, Equatable, Sendable {
    public var slug: String
    public var version: String?
    public var status: String?
    public var deprecatedAt: Date?
}
