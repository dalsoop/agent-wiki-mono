import AgentVaultClientKit
import Foundation
import Observation

/// 앱이 어떤 자격을 원하는지 선언한다. 피커는 이걸로 목록을 좁힌다.
///
/// vault 카드에는 개인 금고 미러가 대량으로 섞여 있어(2026-08 기준 446장 중 439장)
/// 힌트 없이 전체를 보여주면 사람이 못 고른다.
public struct CredentialHint: Sendable, Equatable {
    /// `usernamePassword` · `apiToken` 등. nil 이면 종류로 거르지 않는다.
    public var kind: String?
    /// 호스트 부분 일치 (예: `synology.internal.kr`).
    public var host: String?
    /// 사람이 읽을 용도 설명. 새 자격 만들기 딥링크에 그대로 실린다.
    public var purpose: String

    public init(kind: String? = nil, host: String? = nil, purpose: String = "") {
        self.kind = kind
        self.host = host
        self.purpose = purpose
    }

    func matches(_ card: AgentVaultCard) -> Bool {
        if let kind, !kind.isEmpty, card.kind != kind { return false }
        if let host, !host.isEmpty {
            let needle = host.lowercased()
            if !card.searchBlob.lowercased().contains(needle) { return false }
        }
        return true
    }
}

/// 피커가 보여줄 상태. 앱마다 다르게 쓰던 문구를 한 곳으로 모은다.
public enum CredentialPickerState: Sendable, Equatable {
    case idle
    case loading
    /// vault CLI 자체를 못 찾거나 응답이 없음 (앱 잘못이 아님을 구분해서 보여준다)
    case vaultUnavailable(String)
    case ready(matching: Int, total: Int)
    case failed(String)
}

@MainActor
@Observable
public final class CredentialPickerModel {
    public private(set) var cards: [AgentVaultCard] = []
    public private(set) var state: CredentialPickerState = .idle
    /// 앱이 저장하는 유일한 값. 비밀이 아니므로 Keychain 이 아니라 앱 설정에 둔다 (#28 D4).
    public var selectedID: String

    /// `selectedID` 의 핀 객체. 앱 설정에는 `rawValue` 만 넣는다.
    public var selectedPin: AgentVaultCard.Pin {
        get { AgentVaultCard.Pin(rawValue: selectedID) }
        set { selectedID = newValue.rawValue }
    }

    public var hint: CredentialHint
    public let agentID: String
    public var searchText: String = ""

    private let client: any AgentVaultAccessClient
    private var tenantID: String?

    public init(
        agentID: String,
        selectedID: String = "",
        hint: CredentialHint = CredentialHint(),
        client: any AgentVaultAccessClient = AgentVaultCLIClient()
    ) {
        self.agentID = agentID
        self.selectedID = AgentVaultCard.Pin(rawValue: selectedID).rawValue
        self.hint = hint
        self.client = client
    }

    /// 힌트 + 검색어로 좁힌 목록. 선택된 카드는 힌트에 안 맞아도 항상 남긴다
    /// (사람이 이미 고른 것을 목록에서 지워버리면 왜 사라졌는지 알 수 없다).
    public var visibleCards: [AgentVaultCard] {
        let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return cards.filter { card in
            if card.id == selectedID { return true }
            guard hint.matches(card) else { return false }
            guard !needle.isEmpty else { return true }
            return card.searchBlob.lowercased().contains(needle)
        }
    }

    public var selectedCard: AgentVaultCard? {
        cards.first { $0.id == selectedID }
    }

    public func load() async {
        state = .loading
        do {
            cards = try await client.selectableCredentials(keeping: selectedPin)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            do {
                tenantID = try await client.tenants().first(where: \.isActive)?.id
            } catch {
                tenantID = nil
            }
            state = .ready(matching: cards.filter(hint.matches).count, total: cards.count)
        } catch let error as AgentVaultClientError {
            // CLI 부재와 권한 거부를 구분해서 보여준다.
            state = .vaultUnavailable(error.errorDescription ?? "Agent Vault 응답 없음")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// 선택된 카드를 이 앱이 쓸 수 있는지 확인. 비밀은 받지 않는다.
    public func check() async -> AgentVaultAccessCheck? {
        guard let card = selectedCard else { return nil }
        return try? await client.check(
            card,
            agentID: agentID,
            fallbackTenantID: tenantID ?? "tenant:personal")
    }

    /// 카드가 없을 때 Agent Vault 로 보낸다. binding 생성 주체는 vault 이고,
    /// 앱은 요청만 한다 — 그래서 UUID 를 사람이 타이핑할 일이 없다 (#28 D5).
    public var newCredentialURL: URL? {
        var components = URLComponents()
        components.scheme = "agent-vault"
        components.host = "credential"
        components.path = "/new"
        var items = [URLQueryItem(name: "consumer", value: agentID)]
        if let kind = hint.kind, !kind.isEmpty { items.append(URLQueryItem(name: "kind", value: kind)) }
        if let host = hint.host, !host.isEmpty {
            items.append(URLQueryItem(name: "host", value: host))
            items.append(URLQueryItem(name: "name", value: host))
        }
        if !hint.purpose.isEmpty { items.append(URLQueryItem(name: "purpose", value: hint.purpose)) }
        components.queryItems = items
        return components.url
    }
}
