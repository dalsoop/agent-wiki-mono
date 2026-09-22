import Foundation

// PIM 스위트(pim-calendar·pim-todo·pim-mail·pim-contacts·pim-notes·pim-agenda)가
// 공용 vault(~/PimVault)에서 공유하는 도메인 모델. 저장 형식은 JSON이므로
// 필드 추가는 옵셔널로만 한다(기존 vault 파일과의 하위 호환).

/// 도메인 간 크로스 링크 — "이 투두는 이 메일에서 왔다", "이 노트는 이 일정에 붙는다".
public struct PimLink: Codable, Equatable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case event, todo, contact, note, mail
    }

    public let kind: Kind
    public let id: String

    public init(kind: Kind, id: String) {
        self.kind = kind
        self.id = id
    }

    /// "mail:2F0A..." 같은 CLI 인자 문자열과 상호 변환.
    public var token: String { "\(kind.rawValue):\(id)" }

    public init?(token: String) {
        guard let sep = token.firstIndex(of: ":"),
              let kind = Kind(rawValue: String(token[..<sep])) else { return nil }
        let id = String(token[token.index(after: sep)...])
        guard !id.isEmpty else { return nil }
        self.init(kind: kind, id: id)
    }
}

public struct CalendarEvent: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date?
    public var location: String?
    public var notes: String?
    /// 참석자 — contact id 또는 자유 텍스트(이메일). contact 링크는 links 로도 가능.
    public var attendees: [String]
    public var links: [PimLink]

    public init(
        id: String = UUID().uuidString,
        title: String,
        start: Date,
        end: Date? = nil,
        location: String? = nil,
        notes: String? = nil,
        attendees: [String] = [],
        links: [PimLink] = []
    ) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.location = location
        self.notes = notes
        self.attendees = attendees
        self.links = links
    }
}

public struct TodoItem: Codable, Equatable, Sendable, Identifiable {
    public enum Priority: String, Codable, Sendable, CaseIterable {
        case low, normal, high
    }

    public var id: String
    public var title: String
    public var due: Date?
    public var done: Bool
    public var priority: Priority
    public var notes: String?
    public var links: [PimLink]
    public var createdAt: Date
    public var completedAt: Date?

    public struct Timeline: Sendable, Equatable {
        public var createdAt: Date
        public var completedAt: Date?

        public init(createdAt: Date = Date(), completedAt: Date? = nil) {
            self.createdAt = createdAt
            self.completedAt = completedAt
        }
    }

    public init(
        id: String = UUID().uuidString,
        title: String,
        due: Date? = nil,
        done: Bool = false,
        priority: Priority = .normal,
        notes: String? = nil,
        links: [PimLink] = [],
        timeline: Timeline = Timeline()
    ) {
        self.id = id
        self.title = title
        self.due = due
        self.done = done
        self.priority = priority
        self.notes = notes
        self.links = links
        self.createdAt = timeline.createdAt
        self.completedAt = timeline.completedAt
    }

    /// 하위호환 — 생성·완료 시각을 평평하게 넘기는 옛 호출부(pim-search 테스트 등)도
    /// 그대로 컴파일된다. 새 코드는 `timeline:` 그룹으로 쓴다.
    public init(
        id: String = UUID().uuidString,
        title: String,
        due: Date? = nil,
        done: Bool = false,
        priority: Priority = .normal,
        notes: String? = nil,
        links: [PimLink] = [],
        createdAt: Date,
        completedAt: Date? = nil
    ) {
        self.init(
            id: id, title: title, due: due, done: done, priority: priority,
            notes: notes, links: links,
            timeline: Timeline(createdAt: createdAt, completedAt: completedAt))
    }
}

public struct Contact: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var emails: [String]
    public var phones: [String]
    public var organization: String?
    public var notes: String?
    public var links: [PimLink]

    public init(
        id: String = UUID().uuidString,
        name: String,
        emails: [String] = [],
        phones: [String] = [],
        organization: String? = nil,
        notes: String? = nil,
        links: [PimLink] = []
    ) {
        self.id = id
        self.name = name
        self.emails = emails
        self.phones = phones
        self.organization = organization
        self.notes = notes
        self.links = links
    }
}

public struct Note: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// Markdown 본문.
    public var body: String
    public var links: [PimLink]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        title: String,
        body: String = "",
        links: [PimLink] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.links = links
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// IMAP 읽기 계정. 비밀번호는 vault 에 저장하지 않는다 —
/// `passwordCommand`(예: "security find-generic-password -w -s pim-mail-icloud")의
/// stdout 을 비밀번호로 쓴다.
public enum MailProvider: String, Codable, Sendable, CaseIterable {
    case google
    case apple
    case microsoft
    case custom
}
public typealias AccountProvider = MailProvider
public typealias PimProvider = MailProvider

public struct BrowserProfile: Codable, Equatable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var directory: String?

    public init(id: String = UUID().uuidString, name: String, directory: String? = nil) {
        self.id = id; self.name = name; self.directory = directory
    }
}

public struct BrowserSession: Codable, Equatable, Sendable, Hashable {
    public var id: String
    public var profileID: String
    public var startedAt: Date?
    public var lastUsedAt: Date?

    public init(id: String = UUID().uuidString, profileID: String, startedAt: Date? = nil, lastUsedAt: Date? = nil) {
        self.id = id; self.profileID = profileID; self.startedAt = startedAt; self.lastUsedAt = lastUsedAt
    }
}

public enum AuthState: String, Codable, Sendable, CaseIterable {
    case unknown
    case signedOut
    case pending
    case authenticated
    case expired
    case error
}

public struct MailAccount: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    /// 표시 이름이자 CLI 지정자. 예: "icloud", "work".
    public var name: String
    public var host: String
    public var port: Int
    public var username: String
    public var passwordCommand: String
    public var provider: MailProvider
    public var browserProfile: BrowserProfile?
    public var browserSession: BrowserSession?
    public var authState: AuthState
    /// mounter/synology 패턴 SSOT 핀. 있으면 Keychain 비밀번호·토큰 경로 전에 ClientKit `check` 게이트를 탄다.
    /// 비밀 원문은 포함하지 않으며, 미설정(nil)이면 기존 Keychain 경로만 쓴다 (Phase A).
    public var vaultCredentialID: String?

    public struct Auth: Sendable, Equatable {
        public var browserProfile: BrowserProfile?
        public var browserSession: BrowserSession?
        public var authState: AuthState
        public var vaultCredentialID: String?

        public init(
            browserProfile: BrowserProfile? = nil,
            browserSession: BrowserSession? = nil,
            authState: AuthState = .unknown,
            vaultCredentialID: String? = nil
        ) {
            self.browserProfile = browserProfile
            self.browserSession = browserSession
            self.authState = authState
            self.vaultCredentialID = vaultCredentialID
        }
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        host: String,
        port: Int = 993,
        username: String,
        passwordCommand: String,
        provider: MailProvider = .custom,
        auth: Auth = Auth()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.passwordCommand = passwordCommand
        self.provider = provider
        self.browserProfile = auth.browserProfile
        self.browserSession = auth.browserSession
        self.authState = auth.authState
        self.vaultCredentialID = auth.vaultCredentialID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, host, port, username, passwordCommand, provider, browserProfile, browserSession, authState
        case vaultCredentialID
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decode(String.self, forKey: .name)
        host = try c.decode(String.self, forKey: .host)
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? 993
        username = try c.decode(String.self, forKey: .username)
        passwordCommand = try c.decodeIfPresent(String.self, forKey: .passwordCommand) ?? ""
        provider = try c.decodeIfPresent(MailProvider.self, forKey: .provider) ?? .custom
        browserProfile = try c.decodeIfPresent(BrowserProfile.self, forKey: .browserProfile)
        browserSession = try c.decodeIfPresent(BrowserSession.self, forKey: .browserSession)
        authState = try c.decodeIfPresent(AuthState.self, forKey: .authState) ?? .unknown
        vaultCredentialID = try c.decodeIfPresent(String.self, forKey: .vaultCredentialID)
    }
}

public struct MailMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Box: String, Codable, Sendable {
        /// IMAP 에서 받아온 사본.
        case inbox
        /// 로컬 초안(발신은 후속 모듈).
        case draft
        /// 보관.
        case archive
    }

    public var id: String
    public var box: Box
    /// 소속 계정 name (draft 는 nil 가능).
    public var account: String?
    /// IMAP UID — inbox 사본의 재동기화 기준.
    public var imapUID: Int?
    public var from: String
    public var to: [String]
    public var subject: String
    public var date: Date
    public var body: String
    /// text/html 파트 원본(있을 때만). 평문 `body` 는 항상 채워지고, 이건 렌더러용 선택 필드다.
    /// Optional 이라 이 필드가 없던 시절의 vault 파일도 그대로 디코딩된다.
    public var bodyHTML: String?
    public var read: Bool
    public var links: [PimLink]

    public struct Source: Sendable, Equatable {
        public var account: String?
        public var imapUID: Int?

        public init(account: String? = nil, imapUID: Int? = nil) {
            self.account = account
            self.imapUID = imapUID
        }
    }

    public struct Content: Sendable, Equatable {
        public var body: String
        public var bodyHTML: String?
        public var read: Bool
        public var links: [PimLink]

        public init(
            body: String = "",
            bodyHTML: String? = nil,
            read: Bool = false,
            links: [PimLink] = []
        ) {
            self.body = body
            self.bodyHTML = bodyHTML
            self.read = read
            self.links = links
        }
    }

    public init(
        id: String = UUID().uuidString,
        box: Box,
        source: Source = Source(),
        from: String,
        to: [String] = [],
        subject: String,
        date: Date = Date(),
        content: Content = Content()
    ) {
        self.id = id
        self.box = box
        self.account = source.account
        self.imapUID = source.imapUID
        self.from = from
        self.to = to
        self.subject = subject
        self.date = date
        self.body = content.body
        self.bodyHTML = content.bodyHTML
        self.read = content.read
        self.links = content.links
    }

    /// 하위호환 — 본문·계정 축을 평평하게 나열하는 옛 호출부(pim-mailFetcher ·
    /// pim-search 테스트 등)도 그대로 컴파일된다. 새 코드는 `source:`/`content:` 그룹으로 쓴다.
    /// `body:` 는 필수 — 그룹 이니셜라이저와의 모호성을 피한다.
    public init(
        id: String = UUID().uuidString,
        box: Box,
        account: String? = nil,
        imapUID: Int? = nil,
        from: String,
        to: [String] = [],
        subject: String,
        date: Date = Date(),
        body: String,
        bodyHTML: String? = nil,
        read: Bool = false,
        links: [PimLink] = []
    ) {
        self.init(
            id: id, box: box,
            source: Source(account: account, imapUID: imapUID),
            from: from, to: to, subject: subject, date: date,
            content: Content(body: body, bodyHTML: bodyHTML, read: read, links: links))
    }
}
