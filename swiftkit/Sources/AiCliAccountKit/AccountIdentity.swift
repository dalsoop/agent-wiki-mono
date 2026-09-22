import Foundation

/// 저장된 계정 행이 "어떤 계정인가"를 답할 수 있게 하는 최소 계약.
///
/// 앱마다 계정 타입의 필드는 다르지만(구독·한도·모델 매핑 등), 동일성 판정에
/// 필요한 건 이 셋뿐이다. 판정 로직을 앱에 두지 않기 위한 좁은 창구다.
public protocol AiCliAccountIdentifiable {
    var identityClient: AiCliClient { get }
    var identityKind: AiCliAccountKind { get }
    /// 활성 세션과 대조하는 키. Claude = organization UUID, Codex/Gemini = email,
    /// Grok = email/user_id, opencode = 자격 파일 내용 해시.
    var identitySessionKey: String? { get }
}

/// 계정 동일성 판정의 **단일 정본**.
///
/// 이전에는 `client == X && kind == .oauthSession && sessionKey == key` 술어가
/// 3개 타깃 8곳에 복붙돼 있었고, 그중 한 곳만 nil 처리가 달라서 새로고침마다
/// 같은 계정이 한 행씩 늘어나는 중복 버그가 났다. 판정은 여기서만 한다.
public struct AccountIdentity: Sendable, Hashable, Codable {
    public let client: AiCliClient
    public let kind: AiCliAccountKind
    /// 비어 있지 않음이 보장된다. 키가 없는 계정은 `AccountIdentity` 를 가질 수 없다.
    public let sessionKey: String

    /// 키가 없거나 공백뿐이면 nil — 식별 불가한 계정에 가짜 동일성을 부여하지 않는다.
    public init?(client: AiCliClient, kind: AiCliAccountKind, sessionKey: String?) {
        guard let key = sessionKey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        self.client = client
        self.kind = kind
        self.sessionKey = key
    }

    /// 저장된 행에서 동일성을 뽑는다. 키 없는 행이면 nil.
    public init?(_ account: some AiCliAccountIdentifiable) {
        self.init(
            client: account.identityClient,
            kind: account.identityKind,
            sessionKey: account.identitySessionKey
        )
    }

    /// 라이브 캡처 키로 만드는 OAuth 세션 동일성(가장 흔한 용례).
    public static func oauthSession(client: AiCliClient, sessionKey: String?) -> AccountIdentity? {
        AccountIdentity(client: client, kind: .oauthSession, sessionKey: sessionKey)
    }

    /// 이 동일성에 해당하는 행인지.
    public func matches(_ account: some AiCliAccountIdentifiable) -> Bool {
        AccountIdentity(account) == self
    }
}

/// 라이브 캡처 1건을 저장 목록에 어떻게 반영할지에 대한 판정.
public enum AccountImportDecision<Account>: Sendable where Account: Sendable {
    /// 같은 계정이 이미 있다 — blob 만 갱신한다.
    case update(Account)
    /// 처음 보는 계정 — 새로 만든다.
    case create(AccountIdentity)
    /// 식별 불가 — **아무것도 하지 않는다**.
    case skip(AccountImportSkipReason)
}

/// 자동 반영을 건너뛴 이유. UI·CLI 가 사용자에게 설명할 수 있도록 값으로 남긴다.
public enum AccountImportSkipReason: String, Sendable, Codable, Equatable {
    /// 캡처는 됐는데 세션 키가 없다. 이 상태로 계정을 만들면 다음 새로고침에
    /// 같은 계정을 또 못 알아보고 행이 무한히 늘어난다 — 그래서 만들지 않는다.
    case unidentifiableSession
}

extension AccountIdentity {
    /// 동일성 판정의 유일한 진입점. 8곳에 흩어졌던 술어를 대신한다.
    ///
    /// - Parameters:
    ///   - accounts: 저장된 계정 목록.
    ///   - client: 캡처한 클라이언트.
    ///   - sessionKey: 캡처에서 추출한 세션 키. nil 이면 `.skip` 이 된다.
    public static func decide<A: AiCliAccountIdentifiable & Sendable>(
        accounts: [A],
        client: AiCliClient,
        sessionKey: String?,
        kind: AiCliAccountKind = .oauthSession
    ) -> AccountImportDecision<A> {
        guard let identity = AccountIdentity(client: client, kind: kind, sessionKey: sessionKey) else {
            return .skip(.unidentifiableSession)
        }
        if let existing = accounts.first(where: { identity.matches($0) }) {
            return .update(existing)
        }
        return .create(identity)
    }

    /// 저장 목록에서 이 동일성의 행을 찾는다. 없으면 nil.
    public static func find<A: AiCliAccountIdentifiable>(
        in accounts: [A],
        client: AiCliClient,
        sessionKey: String?,
        kind: AiCliAccountKind = .oauthSession
    ) -> A? {
        guard let identity = AccountIdentity(client: client, kind: kind, sessionKey: sessionKey) else {
            return nil
        }
        return accounts.first(where: { identity.matches($0) })
    }

    /// 이 클라이언트의 활성 세션을 새 계정으로 들여올 여지가 있는지.
    /// 키가 없으면 `false` — 식별 못 하는 세션은 자동으로 만들지 않는다.
    public static func canImport<A: AiCliAccountIdentifiable>(
        client: AiCliClient,
        activeSessionKey: String?,
        accounts: [A],
        kind: AiCliAccountKind = .oauthSession
    ) -> Bool {
        guard let identity = AccountIdentity(client: client, kind: kind, sessionKey: activeSessionKey) else {
            return false
        }
        return !accounts.contains(where: { identity.matches($0) })
    }
}

extension Array where Element: AiCliAccountIdentifiable {
    /// 같은 동일성을 가진 행들을 묶는다. 키 없는 행은 어디에도 속하지 않는다.
    /// 중복 정리 마이그레이션이 이 그룹을 쓴다.
    public func groupedByIdentity() -> [AccountIdentity: [Element]] {
        var out: [AccountIdentity: [Element]] = [:]
        for account in self {
            guard let identity = AccountIdentity(account) else { continue }
            out[identity, default: []].append(account)
        }
        return out
    }
}
