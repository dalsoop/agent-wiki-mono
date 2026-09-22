import Foundation

/// 자격증명 수명주기 공용 계층 — GitLab PAT·Infisical 토큰·OAuth refresh 등
/// "발급되고, 쓰이고, 만료되고, 폐기되는" 모든 것에 공통인 부분만 담는다.
///
/// 제공자별(GitLab/Infisical/…) API 는 `CredentialProvider` 로 주입한다.

public struct CredentialID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
    public init(_ raw: Int) { self.raw = String(raw) }
    public var description: String { raw }
}

/// 제공자에서 읽어온 자격증명 한 건.
///
/// - Important: `value`(실제 비밀값)는 **여기 없다.** 대부분의 제공자는 발급 시점
///   외에는 값을 돌려주지 않는다. 그래서 "이게 어디에 저장돼 쓰이는지"는 API 만으로
///   알 수 없고, `lastUsedAt` 이 살아있음의 유일한 권위 있는 신호다.
public struct ManagedCredential: Sendable, Equatable, Identifiable, Codable {
    public let id: CredentialID
    public let name: String
    /// 소유 주체(계정·서비스). 제공자 안에서만 의미 있는 문자열.
    public let owner: String
    public let ownerID: String?
    public let scopes: [String]
    public let createdAt: Date
    public let lastUsedAt: Date?
    public let expiresAt: Date?
    public let revoked: Bool

    public struct Identity: Sendable, Equatable, Codable {
        public var id: CredentialID
        public var name: String
        public var owner: String
        public var ownerID: String?
        public init(id: CredentialID, name: String, owner: String, ownerID: String? = nil) {
            self.id = id
            self.name = name
            self.owner = owner
            self.ownerID = ownerID
        }
    }

    public struct Life: Sendable, Equatable, Codable {
        public var scopes: [String]
        public var createdAt: Date
        public var lastUsedAt: Date?
        public var expiresAt: Date?
        public var revoked: Bool
        public init(
            scopes: [String] = [],
            createdAt: Date,
            lastUsedAt: Date? = nil,
            expiresAt: Date? = nil,
            revoked: Bool = false
        ) {
            self.scopes = scopes
            self.createdAt = createdAt
            self.lastUsedAt = lastUsedAt
            self.expiresAt = expiresAt
            self.revoked = revoked
        }
    }

    public init(identity: Identity, life: Life) {
        self.id = identity.id
        self.name = identity.name
        self.owner = identity.owner
        self.ownerID = identity.ownerID
        self.scopes = life.scopes
        self.createdAt = life.createdAt
        self.lastUsedAt = life.lastUsedAt
        self.expiresAt = life.expiresAt
        self.revoked = life.revoked
    }
}

/// 방금 발급받은 자격증명 — **값이 들어 있는 유일한 타입**이다.
///
/// 로그·상태미러·에러 메시지에 새어 나가지 않도록 `CustomStringConvertible` 를
/// 마스킹 구현으로 덮고 `Codable` 을 채택하지 않는다(직렬화로 흘리는 경로 차단).
public struct IssuedCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let id: CredentialID
    public let name: String
    public let value: String
    public let expiresAt: Date?

    public init(id: CredentialID, name: String, value: String, expiresAt: Date? = nil) {
        self.id = id
        self.name = name
        self.value = value
        self.expiresAt = expiresAt
    }

    public var description: String { "IssuedCredential(id: \(id), name: \(name), value: <redacted>)" }
    public var debugDescription: String { description }

    /// 로그에 남겨도 되는 형태. 값 전체가 아니라 앞 4자만.
    public var maskedValue: String {
        value.count <= 8 ? "<redacted>" : String(value.prefix(4)) + "…<redacted>"
    }
}

// MARK: - 판정

public enum CredentialSeverity: String, Sendable, Codable, Comparable, CaseIterable {
    case ok, notice, warning, critical

    private var rank: Int {
        switch self {
        case .ok: 0
        case .notice: 1
        case .warning: 2
        case .critical: 3
        }
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

public enum CredentialFlag: String, Sendable, Codable {
    /// 오래 안 쓰였다 — 폐기 1순위.
    case stale
    /// 발급 후 한 번도 안 쓰였다.
    case neverUsed
    /// 곧 만료.
    case expiringSoon
    /// 이미 만료됐는데 폐기되지 않았다.
    case expired
    /// 방치 + 쓰기 권한. 가장 위험한 조합.
    case staleWriteCapable
    /// 짧은 시간에 무더기로 생성된 무리의 일부 — 생성 루프 폭주 신호.
    case burst
}

public struct CredentialVerdict: Sendable, Equatable, Identifiable, Codable {
    public let credential: ManagedCredential
    public let flags: [CredentialFlag]
    public let severity: CredentialSeverity
    /// 마지막 사용 이후 경과일. 한 번도 안 썼으면 발급 이후 경과일.
    public let idleDays: Int
    public let daysUntilExpiry: Int?

    public var id: CredentialID { credential.id }

    public init(credential: ManagedCredential, flags: [CredentialFlag],
                severity: CredentialSeverity, idleDays: Int, daysUntilExpiry: Int?) {
        self.credential = credential
        self.flags = flags
        self.severity = severity
        self.idleDays = idleDays
        self.daysUntilExpiry = daysUntilExpiry
    }
}

public struct OwnerRollup: Sendable, Equatable, Identifiable, Codable {
    public let owner: String
    public let active: Int
    public let stale: Int
    public let expiringSoon: Int
    public let worst: CredentialSeverity
    /// 가장 최근 쓰인 것의 유휴일 — 소유 주체가 살아 있는지 보는 값.
    public let freshestIdleDays: Int?

    public var id: String { owner }

    public init(owner: String, active: Int, stale: Int, expiringSoon: Int,
                worst: CredentialSeverity, freshestIdleDays: Int?) {
        self.owner = owner
        self.active = active
        self.stale = stale
        self.expiringSoon = expiringSoon
        self.worst = worst
        self.freshestIdleDays = freshestIdleDays
    }
}

/// 짧은 창 안에 무더기로 만들어진 무리 — 발급 루프가 폭주한 흔적.
public struct BurstGroup: Sendable, Equatable, Identifiable, Codable {
    public let owner: String
    public let count: Int
    public let firstCreated: Date
    public let lastCreated: Date
    public let credentialIDs: [CredentialID]

    public var id: String { "\(owner)-\(credentialIDs.first?.raw ?? "")" }

    public init(owner: String, count: Int, firstCreated: Date, lastCreated: Date,
                credentialIDs: [CredentialID]) {
        self.owner = owner
        self.count = count
        self.firstCreated = firstCreated
        self.lastCreated = lastCreated
        self.credentialIDs = credentialIDs
    }
}

public struct CredentialAuditReport: Sendable, Equatable, Codable {
    public let source: String
    public let generatedAt: Date
    public let totalActive: Int
    public let stale: Int
    public let expiringSoon: Int
    public let expired: Int
    public let staleWriteCapable: Int
    public let owners: [OwnerRollup]
    public let verdicts: [CredentialVerdict]
    public let bursts: [BurstGroup]
    /// 권한이 부족해 일부만 조회한 경우 true — 숫자를 전체로 읽으면 안 된다.
    public let partialScope: Bool

    public var worst: CredentialSeverity { verdicts.map(\.severity).max() ?? .ok }

    public struct Origin: Sendable, Equatable, Codable {
        public var source: String
        public var generatedAt: Date
        public var partialScope: Bool
        public init(source: String, generatedAt: Date, partialScope: Bool) {
            self.source = source
            self.generatedAt = generatedAt
            self.partialScope = partialScope
        }
    }

    public struct Counts: Sendable, Equatable, Codable {
        public var totalActive: Int
        public var stale: Int
        public var expiringSoon: Int
        public var expired: Int
        public var staleWriteCapable: Int
        public init(
            totalActive: Int,
            stale: Int,
            expiringSoon: Int,
            expired: Int,
            staleWriteCapable: Int
        ) {
            self.totalActive = totalActive
            self.stale = stale
            self.expiringSoon = expiringSoon
            self.expired = expired
            self.staleWriteCapable = staleWriteCapable
        }
    }

    public struct Rows: Sendable, Equatable, Codable {
        public var owners: [OwnerRollup]
        public var verdicts: [CredentialVerdict]
        public var bursts: [BurstGroup]
        public init(
            owners: [OwnerRollup],
            verdicts: [CredentialVerdict],
            bursts: [BurstGroup]
        ) {
            self.owners = owners
            self.verdicts = verdicts
            self.bursts = bursts
        }
    }

    public init(origin: Origin, counts: Counts, rows: Rows) {
        self.source = origin.source
        self.generatedAt = origin.generatedAt
        self.totalActive = counts.totalActive
        self.stale = counts.stale
        self.expiringSoon = counts.expiringSoon
        self.expired = counts.expired
        self.staleWriteCapable = counts.staleWriteCapable
        self.owners = rows.owners
        self.verdicts = rows.verdicts
        self.bursts = rows.bursts
        self.partialScope = origin.partialScope
    }
}

public struct CredentialPolicy: Sendable, Equatable, Codable {
    /// 이 일수를 넘게 안 쓰이면 방치로 본다.
    public var staleDays: Int
    /// 발급 후 이 일수가 지나도록 한 번도 안 쓰이면 방치로 본다(갓 만든 것 오탐 방지).
    public var neverUsedGraceDays: Int
    /// 이 일수 안에 만료되면 경고.
    public var expiringWithinDays: Int
    /// 이 시간(분) 안에 이 개수 이상 생기면 폭주로 본다.
    public var burstWindowMinutes: Int
    public var burstMinimumCount: Int
    /// 방치됐을 때 위험도를 올리는 스코프. 제공자마다 어휘가 다르므로 주입받는다.
    public var writeCapableScopes: Set<String>

    public static let `default` = CredentialPolicy(
        staleDays: 60, neverUsedGraceDays: 7, expiringWithinDays: 30,
        burstWindowMinutes: 60, burstMinimumCount: 5,
        writeCapableScopes: ["api", "write_repository", "write_registry",
                             "sudo", "admin_mode", "create_runner", "manage_runner",
                             "write", "admin"]
    )

    public init(staleDays: Int, neverUsedGraceDays: Int, expiringWithinDays: Int,
                burstWindowMinutes: Int, burstMinimumCount: Int,
                writeCapableScopes: Set<String>) {
        self.staleDays = staleDays
        self.neverUsedGraceDays = neverUsedGraceDays
        self.expiringWithinDays = expiringWithinDays
        self.burstWindowMinutes = burstWindowMinutes
        self.burstMinimumCount = burstMinimumCount
        self.writeCapableScopes = writeCapableScopes
    }

    public func isWriteCapable(_ credential: ManagedCredential) -> Bool {
        credential.scopes.contains { writeCapableScopes.contains($0) }
    }
}
