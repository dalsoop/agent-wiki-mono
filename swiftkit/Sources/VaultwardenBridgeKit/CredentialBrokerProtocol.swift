// 이 파일은 b0f1d6857(search/item op 확장) 이 정본이다.
// main 이 어떤 머지에서 이 파일만 옛 72줄 판으로 되돌아가 있었고, 그 바람에
// vaultwarden-client 가 `VaultItemMeta`·`VaultSearchResponse` 를 못 찾아
// 컴파일 불가였다(2026-07-27 전수 빌드 스윕). 되돌리지 말 것.
import Foundation

public struct VaultCredentialRequest: Codable, Equatable, Sendable {
    public let id: String
    public let requestingApp: String
    public let domain: String
    /// 같은 도메인에 여러 계정이 있을 때 어느 계정인지 좁히는 힌트(대소문자 무시 정확 일치).
    /// nil 이면 기존 동작(단일 매치 자동, 다중이면 사용자 선택). 하위호환: 구 페이로드는 이 키가 없다.
    public let username: String?

    /// 요청 종류. nil 또는 "credentials" = 기존 도메인 매칭(비밀 반환),
    /// "search" = 메타데이터 검색(비밀 없음), "item" = itemId 로 특정 항목 비밀 요청,
    /// "session" = dual-entry 세션 이관(userKey+토큰, GUI unlocked 일 때만).
    /// 하위호환: 구 페이로드는 이 키가 없다(nil → credentials).
    public let op: String?
    /// op="search" 용 부분일치 질의(name/username/uri, 대소문자 무시).
    public let query: String?
    /// op="item" 용 항목 id.
    public let itemId: String?

    public init(
        id: String = UUID().uuidString,
        requestingApp: String,
        domain: String,
        username: String? = nil,
        op: String? = nil,
        query: String? = nil,
        itemId: String? = nil
    ) {
        self.id = id
        self.requestingApp = requestingApp
        self.domain = domain
        self.username = username
        self.op = op
        self.query = query
        self.itemId = itemId
    }
}

/// op="search" 응답. **비밀번호·TOTP 를 절대 담지 않는다 — 메타데이터 목록만.**
public struct VaultSearchResponse: Codable, Equatable, Sendable {
    public let status: VaultCredentialResponse.Status
    public let items: [VaultItemMeta]

    public init(status: VaultCredentialResponse.Status, items: [VaultItemMeta] = []) {
        self.status = status
        self.items = items
    }
}

/// 검색 결과 항목의 **메타데이터 전용** 표현. 비밀번호/TOTP 필드는 의도적으로 없다.
public struct VaultItemMeta: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let username: String?
    public let domain: String?

    public init(id: String, name: String, username: String? = nil, domain: String? = nil) {
        self.id = id
        self.name = name
        self.username = username
        self.domain = domain
    }
}

public struct VaultCredentialResponse: Codable, Equatable, Sendable, CustomStringConvertible {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case success
        case locked
        case notFound
        case multipleMatches
        case denied
        case unavailable
    }

    public let status: Status
    public let username: String?
    public let password: String?
    /// 성공 시 현재 유효한 6자리 TOTP 코드(항목에 TOTP 시드가 있으면). 2FA 무인 입력용.
    /// nil = TOTP 미설정. 하위호환: 구 서버 응답엔 이 키가 없다.
    public let totp: String?

    public init(status: Status, username: String? = nil, password: String? = nil, totp: String? = nil) {
        self.status = status
        if status == .success {
            self.username = username
            self.password = password
            self.totp = totp
        } else {
            self.username = nil
            self.password = nil
            self.totp = nil
        }
    }

    public static func success(username: String, password: String, totp: String? = nil) -> Self {
        Self(status: .success, username: username, password: password, totp: totp)
    }

    public var description: String {
        "VaultCredentialResponse(status: \(status.rawValue))"
    }
}

public enum VaultCredentialCodec {
    public static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable, Bytes: DataProtocol>(
        _ type: T.Type,
        from data: Bytes
    ) throws -> T {
        try JSONDecoder().decode(type, from: Data(data))
    }
}

public enum VaultCredentialBrokerPaths {
    public static func socketURL(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library/Application Support/VaultwardenClient", isDirectory: true)
            .appendingPathComponent("credential-broker.sock", isDirectory: false)
    }
}

// MARK: - dual-entry 세션 이관 (op="session")

/// GUI 메모리 세션 → CLI/에이전트 프로세스. **소켓은 로컬 0600**, 응답은 unlocked 일 때만.
/// 비밀 필드 로그 금지.
public struct VaultSessionExportResponse: Codable, Equatable, Sendable {
    public enum Status: String, Codable, CaseIterable, Sendable {
        case success
        case locked
        case denied
        case unavailable
    }

    public let status: Status
    /// userKey 64바이트 base64 (enc|mac).
    public let userKeyBase64: String?
    public let accessToken: String?
    public let refreshToken: String?
    public let identity: String?
    public let api: String?
    public let label: String?
    public let email: String?
    public let kdf: Int?
    public let iterations: Int?

    public struct Secrets: Equatable, Sendable {
        public var userKeyBase64: String?
        public var accessToken: String?
        public var refreshToken: String?

        public init(
            userKeyBase64: String? = nil,
            accessToken: String? = nil,
            refreshToken: String? = nil
        ) {
            self.userKeyBase64 = userKeyBase64
            self.accessToken = accessToken
            self.refreshToken = refreshToken
        }
    }

    public struct Account: Equatable, Sendable {
        public var identity: String?
        public var api: String?
        public var label: String?
        public var email: String?

        public init(
            identity: String? = nil,
            api: String? = nil,
            label: String? = nil,
            email: String? = nil
        ) {
            self.identity = identity
            self.api = api
            self.label = label
            self.email = email
        }
    }

    public struct KDF: Equatable, Sendable {
        public var kdf: Int?
        public var iterations: Int?

        public init(kdf: Int? = nil, iterations: Int? = nil) {
            self.kdf = kdf
            self.iterations = iterations
        }
    }

    public init(
        status: Status,
        secrets: Secrets? = nil,
        account: Account? = nil,
        kdf: KDF? = nil
    ) {
        self.status = status
        if status == .success {
            self.userKeyBase64 = secrets?.userKeyBase64
            self.accessToken = secrets?.accessToken
            self.refreshToken = secrets?.refreshToken
            self.identity = account?.identity
            self.api = account?.api
            self.label = account?.label
            self.email = account?.email
            self.kdf = kdf?.kdf
            self.iterations = kdf?.iterations
        } else {
            self.userKeyBase64 = nil
            self.accessToken = nil
            self.refreshToken = nil
            self.identity = nil
            self.api = nil
            self.label = nil
            self.email = nil
            self.kdf = nil
            self.iterations = nil
        }
    }
}

/// GUI 가 풀린 뒤 같은 사용자 프로세스가 세션을 물려받는다.
/// 소켓은 로컬 0600 — 요청 이름 문자열은 신뢰 경계가 아니다.
public enum VaultSessionExportPolicy {
    public static let allowedApps: Set<String> = [
        "vaultwarden-client-cli",
        "agent-vault",
        "agent-vault-cli",
        "credential-manager",
        "llm-route-manager",
    ]

    public static func allows(_ requestingApp: String) -> Bool {
        !requestingApp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
