import XCTest
@testable import AgentVaultClientKit

/// 실행 경로로 등록된 agentID 를 찾는다 — grant 가 묶이는 축이 경로다.
final class AgentIdentityResolutionTests: XCTestCase {
    private func client(_ agents: [AgentVaultAgentSummary],
                        credentials: [AgentVaultCredentialSummary] = []) -> StubClient {
        StubClient(agentList: agents, credentialList: credentials)
    }

    private func agent(_ id: String, _ path: String, enabled: Bool = true) -> AgentVaultAgentSummary {
        AgentVaultAgentSummary(id: id, name: id, executablePath: path, enabled: enabled)
    }

    func testMatchesExactExecutablePath() async {
        let c = client([agent("app:gujo@macbook", "/Applications/Gujo Cloud Apps.app")])
        let id = await c.registeredAgentID(executablePath: "/Applications/Gujo Cloud Apps.app")
        XCTAssertEqual(id, "app:gujo@macbook")
    }

    /// 번들 안 실행 파일로 불려도 감싸는 `.app` 등록과 맞아야 한다.
    func testMatchesEnclosingAppBundle() async {
        let c = client([agent("app:gujo@macbook", "/Applications/Gujo Cloud Apps.app")])
        let id = await c.registeredAgentID(
            executablePath: "/Applications/Gujo Cloud Apps.app/Contents/MacOS/GujoCloudApps")
        XCTAssertEqual(id, "app:gujo@macbook")
    }

    /// **등록된 이름이 슬러그와 다를 수 있다.** 실측: Gujo Cloud Apps.app → app:gujo@macbook.
    /// 슬러그로만 찾으면 못 찾고, 지어낸 ID 를 넘기면 vault 가 usage 오류로 원인을 가린다.
    func testSlugLookupMissesWhatPathLookupFinds() async {
        let c = client([agent("app:gujo@macbook", "/Applications/Gujo Cloud Apps.app")])
        let bySlug = await c.registeredAgentID(appSlug: "gujo-cloud-apps")
        let byPath = await c.registeredAgentID(executablePath: "/Applications/Gujo Cloud Apps.app")
        XCTAssertNil(bySlug)
        XCTAssertEqual(byPath, "app:gujo@macbook")
    }

    func testDisabledAgentIsNotUsed() async {
        let c = client([agent("app:x@macbook", "/Applications/X.app", enabled: false)])
        let id = await c.registeredAgentID(executablePath: "/Applications/X.app")
        XCTAssertNil(id, "비활성 등록은 쓰지 않는다")
    }

    /// 못 찾으면 지어내지 않는다 — 호출자가 "등록되지 않았다" 를 그대로 말할 수 있게.
    func testUnregisteredPathReturnsNil() async {
        let c = client([agent("app:other@macbook", "/Applications/Other.app")])
        let id = await c.registeredAgentID(executablePath: "/Applications/Mine.app")
        XCTAssertNil(id)
    }

    /// 작업 공간은 카드가 안다 — 상수로 박으면 카드를 옮기는 순간 깨진다.
    func testOwnerTenantComesFromTheCard() async {
        let card = AgentVaultCredentialSummary(
            identity: .init(id: "CARD-1", name: "Gujo API", kind: "apiToken"),
            account: .init(account: "", host: "gujo", secretStored: true, locator: nil),
            status: .init(ownerTenantID: "tenant:personal"))
        let c = client([], credentials: [card])
        let tenant = await c.ownerTenantID(credentialID: "CARD-1")
        XCTAssertEqual(tenant, "tenant:personal")
        let missing = await c.ownerTenantID(credentialID: "CARD-2")
        XCTAssertNil(missing)
    }
}

private actor StubClient: AgentVaultAccessClient {
    let agentList: [AgentVaultAgentSummary]
    let credentialList: [AgentVaultCredentialSummary]

    init(agentList: [AgentVaultAgentSummary], credentialList: [AgentVaultCredentialSummary]) {
        self.agentList = agentList
        self.credentialList = credentialList
    }

    func agents() async throws -> [AgentVaultAgentSummary] { agentList }
    func credentials() async throws -> [AgentVaultCredentialSummary] { credentialList }
    func tenants() async throws -> [AgentVaultTenantSummary] { [] }
    func check(_ context: AgentVaultCredentialContext) async throws -> AgentVaultAccessCheck {
        AgentVaultAccessCheck(
            credentialID: context.credentialID, credentialName: "", agentID: context.agentID,
            tenantID: context.tenantID, allowed: false, level: nil, reason: nil)
    }
    func use(_ context: AgentVaultCredentialContext, command: [String],
             timeout: TimeInterval?) async throws -> AgentVaultUseResult {
        throw AgentVaultClientError.invalidResponse("stub")
    }
    func fetch(_ context: AgentVaultCredentialContext) async throws -> AgentVaultSecret {
        throw AgentVaultClientError.invalidResponse("stub")
    }
}
