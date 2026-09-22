import CommandKit
import Foundation
import InteropKit

public struct AgentVaultTenantSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let slug: String
    public let purpose: String
    public let agentIDs: [String]
    public let isActive: Bool
    /// 작업 정본 절대경로 (`agent-vault tenant set-roots`). 미디어 복사가 아니라 검증 포인터.
    public let rootPaths: [String]

    public init(
        id: String,
        name: String,
        slug: String,
        purpose: String,
        agentIDs: [String],
        isActive: Bool,
        rootPaths: [String] = []
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.purpose = purpose
        self.agentIDs = agentIDs
        self.isActive = isActive
        self.rootPaths = rootPaths
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        slug = try c.decode(String.self, forKey: .slug)
        purpose = try c.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        agentIDs = try c.decodeIfPresent([String].self, forKey: .agentIDs) ?? []
        isActive = try c.decodeIfPresent(Bool.self, forKey: .isActive) ?? false
        rootPaths = try c.decodeIfPresent([String].self, forKey: .rootPaths) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, purpose, agentIDs, isActive, rootPaths
    }
}

public struct AgentVaultCredentialLocator: Codable, Equatable, Hashable, Sendable {
    public let providerID: String
    public let itemID: String
    public let path: String

    public init(providerID: String, itemID: String, path: String) {
        self.providerID = providerID
        self.itemID = itemID
        self.path = path
    }
}

/// 소비 앱이 다루는 Agent Vault 카드. 비밀값은 구조적으로 없다.
///
/// 앱이 저장해도 되는 값은 `pin`(`id`) 하나다. 테넌트·호스트·계정은 카드가 들고 다니므로
/// 호출마다 문자열 세 개를 따로 맞춰 넣지 않는다.
public struct AgentVaultCard: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: String
    public let account: String
    public let host: String
    public let secretStored: Bool?
    public let locator: AgentVaultCredentialLocator?
    /// 이 카드가 속한 작업 공간. 앱이 tenant 를 상수로 박으면 카드를 옮기는 순간
    /// 깨지고, vault 는 "작업 공간을 찾을 수 없습니다" 로만 답해 원인이 안 보인다.
    public let ownerTenantID: String?
    /// vault `credential list --json` 이 활성·아카이브를 같이 줄 수 있다.
    public let archivedAt: Date?
    /// `dump` | `triaged` | `managed`. 비면 미분류.
    public let managementState: String
    public let tags: [String]

    public struct Identity: Codable, Equatable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var kind: String
        public init(id: String, name: String, kind: String) {
            self.id = id
            self.name = name
            self.kind = kind
        }
    }

    public struct Account: Codable, Equatable, Hashable, Sendable {
        public var account: String
        public var host: String
        public var secretStored: Bool?
        public var locator: AgentVaultCredentialLocator?
        public init(
            account: String,
            host: String,
            secretStored: Bool?,
            locator: AgentVaultCredentialLocator?
        ) {
            self.account = account
            self.host = host
            self.secretStored = secretStored
            self.locator = locator
        }
    }

    public struct Status: Codable, Equatable, Hashable, Sendable {
        public var ownerTenantID: String?
        public var archivedAt: Date?
        public var managementState: String
        public var tags: [String]
        public init(
            ownerTenantID: String? = nil,
            archivedAt: Date? = nil,
            managementState: String = "",
            tags: [String] = []
        ) {
            self.ownerTenantID = ownerTenantID
            self.archivedAt = archivedAt
            self.managementState = managementState
            self.tags = tags
        }
    }

    public init(identity: Identity, account: Account, status: Status = Status()) {
        self.id = identity.id
        self.name = identity.name
        self.kind = identity.kind
        self.account = account.account
        self.host = account.host
        self.secretStored = account.secretStored
        self.locator = account.locator
        self.ownerTenantID = status.ownerTenantID
        self.archivedAt = status.archivedAt
        self.managementState = status.managementState
        self.tags = status.tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        account = try c.decodeIfPresent(String.self, forKey: .account) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        secretStored = try c.decodeIfPresent(Bool.self, forKey: .secretStored)
        locator = try c.decodeIfPresent(AgentVaultCredentialLocator.self, forKey: .locator)
        ownerTenantID = Self.nonEmpty(try c.decodeIfPresent(String.self, forKey: .ownerTenantID))
        archivedAt = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        managementState = try c.decodeIfPresent(String.self, forKey: .managementState) ?? ""
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, account, host, secretStored, locator, ownerTenantID, archivedAt
        case managementState, tags
    }

    public var providerID: String { locator?.providerID ?? "agent-vault-local" }
    public var isArchived: Bool { archivedAt != nil }
    public var isDump: Bool { managementState == "dump" }
    /// 소비 앱 고르기 목록에 올릴지. dump·아카이브는 숨기고, 이미 핀한 카드는 호출 측이 살린다.
    public var isSelectable: Bool { !isArchived && !isDump }
    public var pin: Pin { Pin(rawValue: id) }

    /// 힌트·검색이 같이 보는 문자열. 비밀 없음.
    public var searchBlob: String {
        ([name, host, inferredHost, account] + tags)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// 같은 이름 카드가 여럿일 때 고르는 한 줄. 비밀 없음.
    public var subtitle: String {
        [account, inferredHost].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// `host` 가 URL 이어도 비교·표시는 호스트만 쓴다.
    public var inferredHost: String {
        let raw = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        if let url = URL(string: raw), let h = url.host, !h.isEmpty { return h }
        let trimmed = raw
            .replacingOccurrences(of: "http://", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "https://", with: "", options: .caseInsensitive)
        return trimmed.split(separator: "/").first.map(String.init) ?? raw
    }

    /// check/fetch/use 에 넘기는 컨텍스트. 테넌트는 카드 소유가 이긴다.
    public func context(
        agentID: String,
        tenantID: String? = nil,
        fallbackTenantID: String = "tenant:personal"
    ) -> AgentVaultCredentialContext {
        AgentVaultCredentialContext(
            tenantID: Self.nonEmpty(tenantID) ?? Self.nonEmpty(ownerTenantID) ?? fallbackTenantID,
            credentialID: id,
            agentID: agentID
        )
    }

    /// 앱이 저장해도 되는 유일한 값. 비밀도 메타도 아니다.
    public struct Pin: Hashable, Sendable, Codable, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        public init(stringLiteral value: String) {
            self.init(rawValue: value)
        }

        public var isEmpty: Bool { rawValue.isEmpty }
        public var description: String { rawValue }
    }

    static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// dump·아카이브는 빼고, `keeping` 핀은 상태가 나빠도 남긴다.
    public static func selectable(
        _ cards: [AgentVaultCard],
        keeping pin: Pin = Pin(rawValue: "")
    ) -> [AgentVaultCard] {
        cards.filter { ($0.pin == pin && !pin.isEmpty) || $0.isSelectable }
    }
}

/// 예전 이름. 새 코드는 `AgentVaultCard` 를 쓴다.
public typealias AgentVaultCredentialSummary = AgentVaultCard

/// 소비 앱 check 래퍼가 각자 복제하던 허용/거절 결과.
public struct AgentVaultCardGate: Equatable, Sendable {
    public let allowed: Bool
    public let reason: String?

    public init(allowed: Bool, reason: String?) {
        self.allowed = allowed
        self.reason = reason
    }

    public static let emptyPinReason = "Vault 카드가 선택되지 않았습니다."
    public static let checkFailedReason =
        "Agent Vault 권한 확인에 실패했습니다. Agent Vault 앱과 grant 상태를 확인하세요."
}

public struct AgentVaultCredentialContext: Codable, Equatable, Hashable, Sendable {
    public static let nasTransferManagerAgentID = "app:nas-cutoff-transfer-manager@macbook"

    public let tenantID: String
    public let credentialID: String
    public let agentID: String

    public init(
        tenantID: String,
        credentialID: String,
        agentID: String = Self.nasTransferManagerAgentID
    ) {
        self.tenantID = tenantID
        self.credentialID = credentialID
        self.agentID = agentID
    }
}

public struct AgentVaultAccessCheck: Codable, Equatable, Sendable {
    public let credentialID: String
    public let credentialName: String
    public let agentID: String
    public let tenantID: String
    public let allowed: Bool
    public let level: String?
    public let reason: String?

    public init(
        credentialID: String,
        credentialName: String,
        agentID: String,
        tenantID: String,
        allowed: Bool,
        level: String?,
        reason: String?
    ) {
        self.credentialID = credentialID
        self.credentialName = credentialName
        self.agentID = agentID
        self.tenantID = tenantID
        self.allowed = allowed
        self.level = level
        self.reason = reason
    }
}

/// `credential use` 결과. 비밀값은 절대 포함하지 않는다 (vault 가 자식에 stdin 주입).
public struct AgentVaultUseResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }

    public var ok: Bool { exitCode == 0 }
}

/// `fetch` 응답. 값을 그대로 들고 다니지 말고 `withSecret` 스코프 안에서만 쓴다.
public struct AgentVaultSecret: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    public let credentialID: String
    public let credentialName: String
    public let username: String?
    public let value: String

    public init(credentialID: String, credentialName: String, username: String?, value: String) {
        self.credentialID = credentialID
        self.credentialName = credentialName
        self.username = username
        self.value = value
    }

    /// 로그·에러 메시지에 값이 새지 않게 한다.
    public var description: String { "AgentVaultSecret(\(credentialID), <redacted>)" }
    public var debugDescription: String { description }
}

public protocol AgentVaultAccessClient: Sendable {
    func tenants() async throws -> [AgentVaultTenantSummary]
    func credentials() async throws -> [AgentVaultCredentialSummary]
    func check(_ context: AgentVaultCredentialContext) async throws -> AgentVaultAccessCheck
    /// DevID agent-vault 가 비밀을 resolve 해 command stdin 으로 전달. 호출 측은 비밀을 받지 않는다.
    func use(_ context: AgentVaultCredentialContext, command: [String], timeout: TimeInterval?) async throws -> AgentVaultUseResult
    /// in-process 소비자(HTTPS 를 직접 치는 GUI 앱)용. `use` 는 서브프로세스 stdin 전용이라
    /// SDK·드라이버를 쓰는 앱을 덮지 못한다 (#28 D8).
    ///
    /// 호출 측 규칙: **저장 금지**(Keychain·파일·UserDefaults), 요청 수명만 보유, 로그 redact.
    /// 앱이 비밀을 잠깐 보는 것은 in-process HTTPS 인 이상 불가피하다. 목표는
    /// "앱이 절대 못 본다"가 아니라 "**앱이 저장소가 되지 않는다**" 이다.
    func fetch(_ context: AgentVaultCredentialContext) async throws -> AgentVaultSecret
    /// 등록된 소비자(agent) 목록. 앱이 자기 agentID 를 **추측하지 않고 확인**하기 위한 것이다.
    ///
    /// 왜 필요한가: agentID 는 `app:<슬러그>@<호스트>` 인데 <호스트>는 실제 hostname 이 아니라
    /// 사람이 정한 라벨이다(이 환경은 `@macbook`, 실제 hostname 은 `jeonghanui-macbookpro`).
    /// 앱이 hostname 으로 지어내면 등록된 것과 안 맞고, agent-vault 는 그걸 usage 오류로
    /// 돌려줘 진짜 원인이 안 보인다(2026-08-10 실측).
    func agents() async throws -> [AgentVaultAgentSummary]
}

/// 등록된 소비자 한 개.
public struct AgentVaultAgentSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    /// 이 ID 로 부를 수 있는 실행 파일 경로. 다른 경로에서 부르면 vault 가 거부한다.
    public let executablePath: String
    public let enabled: Bool

    public init(id: String, name: String, executablePath: String, enabled: Bool) {
        self.id = id
        self.name = name
        self.executablePath = executablePath
        self.enabled = enabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        executablePath = try c.decodeIfPresent(String.self, forKey: .executablePath) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, executablePath, enabled
    }
}

extension AgentVaultAccessClient {
    /// 기존 구현체가 깨지지 않도록 기본값을 둔다 — 목록을 모르면 빈 배열.
    public func agents() async throws -> [AgentVaultAgentSummary] { [] }

    /// 이 앱 슬러그로 **실제 등록된** agentID 를 찾는다. 없으면 nil —
    /// 호출자가 "아직 등록되지 않았다" 를 사용자에게 그대로 보여 줄 수 있게 한다.
    public func registeredAgentID(appSlug: String) async -> String? {
        guard let all = try? await agents() else { return nil }
        let prefix = "app:\(appSlug)@"
        return all.first { $0.id.hasPrefix(prefix) && $0.enabled }?.id
    }

    /// **실행 경로**로 등록된 agentID 를 찾는다. grant 가 묶이는 축이 경로라
    /// 슬러그 규칙보다 이쪽이 정확하다 — 등록된 이름이 슬러그와 다를 수 있다.
    /// 실측(2026-08-11): `/Applications/Gujo Cloud Apps.app` 은 슬러그와 달리
    /// `app:gujo@macbook` 으로 등록돼 있어, 슬러그로 찾으면 못 찾는다.
    ///
    /// 번들 안 실행 파일로 불릴 수도 있으므로 **감싸는 `.app` 경로로도** 맞춰본다.
    public func registeredAgentID(executablePath: String) async -> String? {
        guard let all = try? await agents() else { return nil }
        let candidates = Set(AgentVaultPathMatch.candidates(for: executablePath))
        return all.first { agent in
            agent.enabled && candidates.contains(AgentVaultPathMatch.normalize(agent.executablePath))
        }?.id
    }

    /// 카드가 실제로 속한 작업 공간. 상수로 박지 않기 위한 조회.
    public func ownerTenantID(credentialID: String) async -> String? {
        guard let all = try? await credentials() else { return nil }
        return all.first { $0.id == credentialID }?.ownerTenantID
    }
}

/// 앱이 vault 에 자기를 소개할 때 쓰는 신원 해석.
///
/// 앱마다 `app:<슬러그>@macbook` 을 상수로 박아 두면 두 가지로 깨진다 —
/// `@macbook` 은 사람이 정한 라벨이라 다른 기계엔 없고, 등록된 이름이 슬러그와
/// 다를 수도 있다. 실측(2026-08-11): 함대 18개 앱이 상수를 박았고 **12개가
/// 등록되지 않은 ID** 를 부르고 있었다. 증상은 전부 vault 의 usage 오류라
/// 진짜 원인이 안 보인다.
public enum AgentVaultIdentity {
    /// 명시값 > 레지스트리(실행 경로) > 기존 상수.
    ///
    /// 마지막 폴백을 남기는 이유: 레지스트리를 못 읽는 상황(CLI 미설치 등)에서
    /// 동작을 지금보다 나쁘게 만들지 않기 위해서다. 등록이 있으면 항상 그쪽이 이긴다.
    public static func resolve(
        _ explicit: String?,
        fallback: String,
        client: any AgentVaultAccessClient,
        executablePath: String = ProcessInfo.processInfo.arguments.first ?? ""
    ) async -> String {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty { return explicit }
        return await client.registeredAgentID(executablePath: executablePath) ?? fallback
    }

    /// 작업 공간은 카드가 안다. 상수로 박으면 카드를 옮기는 순간 깨진다.
    public static func resolveTenant(
        _ explicit: String?,
        credentialID: String,
        fallback: String,
        client: any AgentVaultAccessClient
    ) async -> String {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty { return explicit }
        return await client.ownerTenantID(credentialID: credentialID) ?? fallback
    }
}

/// 경로 비교 규칙 하나 — 호출자마다 다르게 정규화하면 같은 앱이 기계마다 다르게 판정된다.
public enum AgentVaultPathMatch {
    public static func normalize(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    /// 실행 경로 자신 + 감싸는 `.app` 번들 경로.
    /// (`…/Foo.app/Contents/MacOS/Foo` 와 `…/Foo.app` 둘 다 등록될 수 있다.)
    public static func candidates(for executablePath: String) -> [String] {
        let me = normalize(executablePath)
        let resolved = URL(fileURLWithPath: me).resolvingSymlinksInPath().path
        var out = [me]
        if resolved != me { out.append(normalize(resolved)) }
        for seed in out {
            var url = URL(fileURLWithPath: seed)
            while url.pathComponents.count > 1 {
                if url.pathExtension == "app" { out.append(normalize(url.path)); break }
                url = url.deletingLastPathComponent()
            }
        }
        return Array(Set(out))
    }
}

extension AgentVaultAccessClient {
    /// 소비 앱 고르기용 목록. `credentials()` 원본은 테넌트 조회 때문에 dump 도 포함한다.
    public func selectableCredentials(
        keeping pin: AgentVaultCard.Pin = AgentVaultCard.Pin(rawValue: "")
    ) async throws -> [AgentVaultCard] {
        AgentVaultCard.selectable(try await credentials(), keeping: pin)
    }

    /// 값의 수명을 클로저 스코프로 묶는다. 반환값에 비밀을 실어 내보내지 말 것.
    public func withSecret<Result: Sendable>(
        _ context: AgentVaultCredentialContext,
        _ operation: (AgentVaultSecret) async throws -> Result
    ) async throws -> Result {
        try await operation(fetch(context))
    }

    public func check(
        _ card: AgentVaultCard,
        agentID: String,
        tenantID: String? = nil,
        fallbackTenantID: String = "tenant:personal"
    ) async throws -> AgentVaultAccessCheck {
        try await check(card.context(agentID: agentID, tenantID: tenantID, fallbackTenantID: fallbackTenantID))
    }

    public func fetch(
        _ card: AgentVaultCard,
        agentID: String,
        tenantID: String? = nil,
        fallbackTenantID: String = "tenant:personal"
    ) async throws -> AgentVaultSecret {
        try await fetch(card.context(agentID: agentID, tenantID: tenantID, fallbackTenantID: fallbackTenantID))
    }

    public func use(
        _ card: AgentVaultCard,
        agentID: String,
        command: [String],
        tenantID: String? = nil,
        fallbackTenantID: String = "tenant:personal",
        timeout: TimeInterval? = 120
    ) async throws -> AgentVaultUseResult {
        try await use(
            card.context(agentID: agentID, tenantID: tenantID, fallbackTenantID: fallbackTenantID),
            command: command,
            timeout: timeout)
    }

    public func gate(
        pin: AgentVaultCard.Pin,
        fallbackAgentID: String,
        fallbackTenantID: String = "tenant:personal",
        deniedFallback: String,
        agentID: String? = nil,
        tenantID: String? = nil,
        card: AgentVaultCard? = nil
    ) async -> AgentVaultCardGate {
        guard !pin.isEmpty else {
            return AgentVaultCardGate(allowed: false, reason: AgentVaultCardGate.emptyPinReason)
        }
        let agentID = await AgentVaultIdentity.resolve(
            agentID, fallback: fallbackAgentID, client: self)
        let tenant = AgentVaultCard.nonEmpty(tenantID)
            ?? AgentVaultCard.nonEmpty(card?.ownerTenantID)
            ?? fallbackTenantID
        let context = AgentVaultCredentialContext(
            tenantID: tenant, credentialID: pin.rawValue, agentID: agentID)
        do {
            let result = try await check(context)
            if result.allowed {
                return AgentVaultCardGate(allowed: true, reason: nil)
            }
            let reason = AgentVaultCard.nonEmpty(result.reason)
            return AgentVaultCardGate(allowed: false, reason: reason ?? deniedFallback)
        } catch {
            return AgentVaultCardGate(allowed: false, reason: AgentVaultCardGate.checkFailedReason)
        }
    }

    public func gate(
        pin: String,
        fallbackAgentID: String,
        fallbackTenantID: String = "tenant:personal",
        deniedFallback: String,
        agentID: String? = nil,
        tenantID: String? = nil,
        card: AgentVaultCard? = nil
    ) async -> AgentVaultCardGate {
        await gate(
            pin: AgentVaultCard.Pin(rawValue: pin),
            fallbackAgentID: fallbackAgentID,
            fallbackTenantID: fallbackTenantID,
            deniedFallback: deniedFallback,
            agentID: agentID,
            tenantID: tenantID,
            card: card)
    }

    public func gate(
        _ card: AgentVaultCard,
        fallbackAgentID: String,
        deniedFallback: String,
        agentID: String? = nil,
        tenantID: String? = nil,
        fallbackTenantID: String = "tenant:personal"
    ) async -> AgentVaultCardGate {
        await gate(
            pin: card.pin,
            fallbackAgentID: fallbackAgentID,
            fallbackTenantID: fallbackTenantID,
            deniedFallback: deniedFallback,
            agentID: agentID,
            tenantID: tenantID,
            card: card)
    }
}

public enum AgentVaultClientError: LocalizedError, Equatable {
    case commandFailed(Int32, String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let code, let message):
            "AgentVault CLI 실패(\(code)): \(message)"
        case .invalidResponse(let message):
            "AgentVault 응답을 읽을 수 없습니다: \(message)"
        }
    }
}

public struct AgentVaultCLIClient: AgentVaultAccessClient, Sendable {
    private let executablePath: String
    private let runner: any CommandRunning

    public init(
        executablePath: String? = nil,
        runner: any CommandRunning = ProcessCommandRunner(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.executablePath = executablePath
            ?? Self.resolveExecutable(environment: environment)
            ?? Self.appHelperPath
        self.runner = runner
    }

    public func tenants() async throws -> [AgentVaultTenantSummary] {
        try await decode(["tenant", "list", "--json"])
    }

    public func agents() async throws -> [AgentVaultAgentSummary] {
        try await decode(["agent", "list", "--json"])
    }

    public func credentials() async throws -> [AgentVaultCredentialSummary] {
        // 활성 작업 공간이 personal 이면 기본 list 는 Gujo 카드를 안 보여
        // ownerTenantID 조회가 비고, software list 가 자격 실패로 죽는다.
        try await decode(["credential", "list", "--tenant", "all", "--json"])
    }

    public func check(_ context: AgentVaultCredentialContext) async throws -> AgentVaultAccessCheck {
        let arguments = [
            "credential", "check", context.credentialID,
            "--agent", context.agentID,
            "--tenant", context.tenantID,
            "--json",
        ]
        let result = await runner.run(executablePath, arguments, timeout: 10)
        guard result.exitCode == 0 || result.exitCode == 77 else {
            throw AgentVaultClientError.commandFailed(
                result.exitCode,
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "응답 없음")
        }
        let value: AgentVaultAccessCheck = try decodeOutput(result.stdout)
        guard result.exitCode != 77 || !value.allowed else {
            throw AgentVaultClientError.invalidResponse("권한 거부 exit code가 허용 응답과 충돌합니다.")
        }
        return value
    }

    /// in-process 소비자용 비밀 조회.
    ///
    /// 이름이 안 맞으면 폴백하지 않는다. 한때 `mount` 로 폴백하게 두었는데, `mount` 는
    /// 이 명령의 새 이름이 아니라 **SMB 공유를 붙이는 전혀 다른 기능**이었다 — 비밀을
    /// 못 받았을 때 엉뚱한 부작용을 부를 뻔했다(2026-08-05). 이름이 안 맞으면 원인은
    /// 하나다: 설치된 agent-vault 가 main 이 아닌 트리에서 빌드됐다. 그건 여기서
    /// 우회할 문제가 아니라 그 설치본을 고칠 문제다.
    public func fetch(_ context: AgentVaultCredentialContext) async throws -> AgentVaultSecret {
        let arguments = [
            "credential", "fetch", context.credentialID,
            "--agent", context.agentID,
            "--tenant", context.tenantID,
            "--json",
        ]
        let result = await runner.run(executablePath, arguments, timeout: 15)
        guard result.exitCode == 0 else {
            // stdout 에는 비밀이 실릴 수 있으므로 실패 메시지에 stderr 만 쓴다.
            throw AgentVaultClientError.commandFailed(
                result.exitCode,
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "권한 거부 또는 응답 없음")
        }
        let payload: FetchPayload = try decodeOutput(result.stdout)
        return AgentVaultSecret(
            credentialID: payload.credentialID,
            credentialName: payload.credentialName,
            username: payload.username,
            value: payload.value)
    }

    private struct FetchPayload: Decodable {
        let credentialID: String
        let credentialName: String
        let username: String?
        let value: String
    }

    public func use(
        _ context: AgentVaultCredentialContext,
        command: [String],
        timeout: TimeInterval? = 120
    ) async throws -> AgentVaultUseResult {
        guard !command.isEmpty else {
            throw AgentVaultClientError.invalidResponse("command 가 비어 있습니다")
        }
        // agent-vault credential use <id> --agent A --tenant T -- <cmd>...
        var arguments = [
            "credential", "use", context.credentialID,
            "--agent", context.agentID,
            "--tenant", context.tenantID,
            "--",
        ]
        arguments.append(contentsOf: command)
        let result = await runner.run(executablePath, arguments, timeout: timeout)
        // 비밀이 stdout/stderr 에 섞일 수 있어 vault 쪽이 redact 한다. 클라이언트는 그대로 전달만.
        if result.exitCode == 77 {
            throw AgentVaultClientError.commandFailed(
                77,
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "권한 거부")
        }
        return AgentVaultUseResult(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr)
    }

    private func decode<Value: Decodable>(_ arguments: [String]) async throws -> Value {
        let result = await runner.run(executablePath, arguments, timeout: 10)
        guard result.ok else {
            throw AgentVaultClientError.commandFailed(
                result.exitCode,
                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                    ?? "응답 없음")
        }
        return try decodeOutput(result.stdout)
    }

    /// agent-vault CLI 는 `{ "ok": true, "result": … }` 봉투를 쓴다.
    /// 예전 flat 응답도 한동안 허용한다.
    private func decodeOutput<Value: Decodable>(_ output: String) throws -> Value {
        let data = Data(output.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let envelope = try decoder.decode(AgentVaultJSONEnvelope<Value>.self, from: data)
            return envelope.result
        } catch {
            // flat 응답 폴백 (구 CLI)
            do {
                return try decoder.decode(Value.self, from: data)
            } catch {
                throw AgentVaultClientError.invalidResponse(Self.diagnose(error, output: output))
            }
        }
    }

    /// 디코드 실패를 **원인이 읽히는 문장**으로 바꾼다.
    ///
    /// 실사고 2026-08-10: `business-tax-records vault list` 가
    /// "AgentVault 응답을 읽을 수 없습니다: The data couldn't be read because it isn't in
    /// the correct format." 만 뱉었다. 원인은 **설치본이 낡아** 이 앱이 들고 있는 모델이
    /// 새 agent-vault 출력과 어긋난 것이었는데(앱 8/6 · agent-vault 8/9), 그 문장만으로는
    /// 파이프 절단·권한·볼트 잠금 같은 엉뚱한 곳을 파게 된다. 실제로 그렇게 팠다.
    /// 어느 키에서 깨졌는지와 재설치 힌트를 같이 준다.
    static func diagnose(_ error: Error, output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "agent-vault 가 빈 응답을 돌려줬습니다." }
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            return "agent-vault 응답이 JSON 이 아닙니다: \(trimmed.prefix(120))"
        }
        let detail: String
        switch error as? DecodingError {
        case .keyNotFound(let key, _):
            detail = "응답에 '\(key.stringValue)' 키가 없습니다"
        case .typeMismatch(let type, let context):
            detail = "'\(context.codingPath.map(\.stringValue).joined(separator: "."))' 의 타입이 \(type) 와 다릅니다"
        case .valueNotFound(_, let context):
            detail = "'\(context.codingPath.map(\.stringValue).joined(separator: "."))' 값이 비었습니다"
        default:
            detail = error.localizedDescription
        }
        return detail
            + " — 설치된 agent-vault 와 이 앱의 모델이 어긋납니다."
            + " 대개 앱 설치본이 낡은 경우입니다: app-build-manager install <앱> 으로 재설치하세요."
    }

    private struct AgentVaultJSONEnvelope<Value: Decodable>: Decodable {
        let ok: Bool?
        let result: Value
    }

    /// Agent Vault 정본 Helper. Credential Manager stub·옛 /usr/local 0.20.1 보다 앞.
    /// 위키 `411b5932` 결정: 자격 표면 역할 지도 v1.
    public static let appHelperPath = "/Applications/AgentVault.app/Contents/Helpers/agent-vault"

    /// Credential Manager 가 argv0 `agent-vault` 를 가로챈 stub 경로인가.
    // Tests need this; keep package-visible so AgentVaultClientKitTests can call it.
    package static func looksLikeCredentialManagerStub(resolvedPath: String) -> Bool {
        resolvedPath.contains("Credential Manager.app")
            || resolvedPath.hasSuffix("/credential-manager")
    }

    private static func resolveExecutable(environment: [String: String]) -> String? {
        let fileManager = FileManager.default
        if let override = environment["AGENT_VAULT_CLI_PATH"],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }
        let candidates = [
            appHelperPath,
            HostPlatform.cliBinPath("agent-vault"),
        ]
        if let path = candidates.first(where: { isUsableAgentVaultCLI($0, fileManager: fileManager) }) {
            return path
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let path = String(directory) + "/agent-vault"
            if isUsableAgentVaultCLI(path, fileManager: fileManager) { return path }
        }
        return nil
    }

    private static func isUsableAgentVaultCLI(_ path: String, fileManager: FileManager) -> Bool {
        guard fileManager.isExecutableFile(atPath: path) else { return false }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return !looksLikeCredentialManagerStub(resolvedPath: resolved)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
