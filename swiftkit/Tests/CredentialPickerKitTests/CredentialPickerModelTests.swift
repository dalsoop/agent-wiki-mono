import AgentVaultClientKit
import XCTest
@testable import CredentialPickerKit

private final class StubClient: AgentVaultAccessClient, @unchecked Sendable {
    var cards: [AgentVaultCard]
    var error: (any Error)?
    var lastContext: AgentVaultCredentialContext?

    init(cards: [AgentVaultCard], error: (any Error)? = nil) {
        self.cards = cards
        self.error = error
    }

    func tenants() async throws -> [AgentVaultTenantSummary] {
        [AgentVaultTenantSummary(
            id: "tenant-personal", name: "personal", slug: "personal",
            purpose: "", agentIDs: [], isActive: true)]
    }

    func credentials() async throws -> [AgentVaultCard] {
        if let error { throw error }
        return cards
    }

    func check(_ context: AgentVaultCredentialContext) async throws -> AgentVaultAccessCheck {
        lastContext = context
        return AgentVaultAccessCheck(
            credentialID: context.credentialID, credentialName: "stub",
            agentID: context.agentID, tenantID: context.tenantID,
            allowed: true, level: "use", reason: nil)
    }

    func use(
        _ context: AgentVaultCredentialContext, command: [String], timeout: TimeInterval?
    ) async throws -> AgentVaultUseResult {
        AgentVaultUseResult(exitCode: 0, stdout: "", stderr: "")
    }

    func fetch(_ context: AgentVaultCredentialContext) async throws -> AgentVaultSecret {
        AgentVaultSecret(
            credentialID: context.credentialID, credentialName: "stub",
            username: "u", value: "secret")
    }
}

private func card(
    _ id: String, name: String, kind: String = "usernamePassword",
    host: String = "", external: Bool = false
) -> AgentVaultCard {
    AgentVaultCard(
        identity: .init(id: id, name: name, kind: kind),
        account: .init(
            account: "",
            host: host,
            secretStored: !external,
            locator: external
                ? AgentVaultCredentialLocator(providerID: "vaultwarden:default", itemID: id, path: "")
                : nil
        ))
}

@MainActor
final class CredentialPickerModelTests: XCTestCase {
    /// 개인 금고 미러가 대량으로 섞여 있어도 힌트로 걸러져야 사람이 고를 수 있다.
    func testHintFiltersMirrorNoise() async {
        var cards = (0..<50).map { card("vw-\($0)", name: "personal-\($0)", external: true) }
        cards.append(card("nas", name: "synology", host: "synology.internal.kr"))
        let model = CredentialPickerModel(
            agentID: "app:test@macbook",
            hint: CredentialHint(kind: "usernamePassword", host: "synology.internal.kr"),
            client: StubClient(cards: cards))

        await model.load()

        XCTAssertEqual(model.visibleCards.map(\.id), ["nas"])
        guard case .ready(let matching, let total) = model.state else {
            return XCTFail("ready 상태여야 함: \(model.state)")
        }
        XCTAssertEqual(matching, 1)
        XCTAssertEqual(total, 51)
    }

    /// 이미 고른 카드가 힌트에 안 맞아도 목록에서 사라지면 안 된다 (왜 사라졌는지 알 수 없다).
    func testSelectedCardSurvivesHintMismatch() async {
        let model = CredentialPickerModel(
            agentID: "app:test@macbook",
            selectedID: "other",
            hint: CredentialHint(host: "synology.internal.kr"),
            client: StubClient(cards: [
                card("other", name: "무관한 카드", host: "example.com"),
                card("nas", name: "synology", host: "synology.internal.kr"),
            ]))

        await model.load()

        XCTAssertEqual(Set(model.visibleCards.map(\.id)), ["other", "nas"])
        XCTAssertEqual(model.selectedCard?.id, "other")
    }

    /// vault CLI 부재는 앱 오류가 아니라 별도 상태로 보여야 한다.
    func testVaultUnavailableIsDistinctState() async {
        let model = CredentialPickerModel(
            agentID: "app:test@macbook",
            client: StubClient(cards: [], error: AgentVaultClientError.commandFailed(127, "not found")))

        await model.load()

        guard case .vaultUnavailable = model.state else {
            return XCTFail("vaultUnavailable 이어야 함: \(model.state)")
        }
    }

    /// 새 자격 딥링크에 consumer 가 실려야 vault 가 binding 을 만들 수 있다 (UUID 타이핑 제거).
    func testNewCredentialURLCarriesConsumerAndHint() {
        let model = CredentialPickerModel(
            agentID: "app:dns-zone-manager@macbook",
            hint: CredentialHint(kind: "apiToken", host: "api.cloudflare.com", purpose: "DNS 편집"),
            client: StubClient(cards: []))

        let url = model.newCredentialURL
        let items = URLComponents(url: XCTUnwrap2(url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        let map = Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } },
                             uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(url?.scheme, "agent-vault")
        XCTAssertEqual(map["consumer"], "app:dns-zone-manager@macbook")
        XCTAssertEqual(map["kind"], "apiToken")
        XCTAssertEqual(map["host"], "api.cloudflare.com")
        XCTAssertEqual(map["purpose"], "DNS 편집")
    }

    func testHintMatchesInferredHost() async {
        let model = CredentialPickerModel(
            agentID: "app:test@macbook",
            hint: CredentialHint(host: "192.168.2.1"),
            client: StubClient(cards: [
                card("r1", name: "iptime", host: "http://192.168.2.1/ui/"),
                card("other", name: "hometax", host: "https://hometax.go.kr/ui/"),
            ]))
        await model.load()
        XCTAssertEqual(model.visibleCards.map(\.id), ["r1"])
    }

    func testDumpCardsHiddenUnlessSelected() async {
        let dump = AgentVaultCard(
            identity: .init(id: "dump", name: "personal google", kind: "usernamePassword"),
            account: .init(account: "", host: "accounts.google.com", secretStored: true, locator: nil),
            status: .init(managementState: "dump"))
        let managed = AgentVaultCard(
            identity: .init(id: "ok", name: "nas", kind: "smb"),
            account: .init(account: "backup", host: "nas.local", secretStored: true, locator: nil),
            status: .init(managementState: "managed"))
        let model = CredentialPickerModel(
            agentID: "app:test@macbook",
            client: StubClient(cards: [dump, managed]))
        await model.load()
        XCTAssertEqual(model.visibleCards.map(\.id), ["ok"])
    }

    func testInitTrimsSelectedPin() {
        let model = CredentialPickerModel(
            agentID: "app:test@macbook",
            selectedID: "  pin-1  ",
            client: StubClient(cards: []))
        XCTAssertEqual(model.selectedID, "pin-1")
        XCTAssertEqual(model.selectedPin.rawValue, "pin-1")
    }

    func testCheckUsesCardOwnerTenant() async {
        let client = StubClient(cards: [
            AgentVaultCard(
                identity: .init(id: "g1", name: "gujo", kind: "apiToken"),
                account: .init(account: "", host: "gujo.ai", secretStored: true, locator: nil),
                status: .init(ownerTenantID: "tenant:gujo")),
        ])
        let model = CredentialPickerModel(
            agentID: "app:gujo@macbook",
            selectedID: "g1",
            client: client)
        await model.load()
        let result = await model.check()
        XCTAssertEqual(result?.allowed, true)
        XCTAssertEqual(client.lastContext?.tenantID, "tenant:gujo")
        XCTAssertEqual(client.lastContext?.credentialID, "g1")
    }
}

private func XCTUnwrap2<T>(_ value: T?) -> T {
    guard let value else { fatalError("nil") }
    return value
}
