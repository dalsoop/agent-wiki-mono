import XCTest
import EndpointRouterKit
@testable import GujoStoreOpsCore

final class AgentVaultAccountProbeTests: XCTestCase {
    func testParseTenantsAndPickGujo() throws {
        let jsonText = """
        {"ok":true,"result":[
          {"id":"tenant:personal","slug":"personal","name":"개인","isActive":true,"purpose":"기본",
           "agentIDs":["a","b"]},
          {"id":"tenant:gujo","slug":"gujo","name":"Gujo","isActive":false,
           "purpose":"Gujo 제품","agentIDs":["x","y","z"]}
        ]}
        """
        guard let json = jsonText.data(using: .utf8) else {
            XCTFail("utf8 tenants fixture")
            return
        }
        let rows = try AgentVaultAccountProbe.parseTenants(json: json)
        XCTAssertEqual(rows.count, 2)
        let gujo = rows.first { $0.slug == "gujo" }
        XCTAssertEqual(gujo?.id, AgentVaultAccountProbe.productTenantID)
        XCTAssertEqual(gujo?.agentCount, 3)
        XCTAssertFalse(gujo?.isActive ?? true)
    }

    func testParseCredentialsNoSecrets() throws {
        let jsonText = """
        {"ok":true,"result":[
          {"id":"AAA","name":"Gujo · devops@ranode.net","kind":"usernamePassword",
           "account":"devops@ranode.net","host":"\(EndpointRouter.app)",
           "ownerTenantID":"tenant:gujo","secretStored":true},
          {"id":"BBB","name":"Gujo Store Ops · Bearer · macbook","kind":"apiToken",
           "account":"ops@macbook","host":"\(EndpointRouter.apps)",
           "ownerTenantID":"tenant:gujo","secretStored":true}
        ]}
        """
        guard let json = jsonText.data(using: .utf8) else {
            XCTFail("utf8 credentials fixture")
            return
        }
        let rows = try AgentVaultAccountProbe.parseCredentials(json: json)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].ownerTenantID, "tenant:gujo")
        XCTAssertTrue(rows[0].secretStored)
        XCTAssertTrue(rows[0].line.contains("usernamePassword"))
        XCTAssertFalse(rows[0].line.lowercased().contains("password="))
    }

    func testSnapshotInjectedRunner() {
        let tenantText = """
        {"ok":true,"result":[{"id":"tenant:gujo","slug":"gujo","name":"Gujo","isActive":false,
          "purpose":"prod","agentIDs":["agent:grok@macbook"]}]}
        """
        let credText = """
        {"ok":true,"result":[{"id":"1","name":"Gujo API","kind":"apiToken","account":"x",
          "host":"\(EndpointRouter.app)","ownerTenantID":"tenant:gujo","secretStored":true}]}
        """
        guard let tenantJSON = tenantText.data(using: .utf8),
              let credJSON = credText.data(using: .utf8) else {
            XCTFail("utf8 snapshot fixtures")
            return
        }
        let snap = AgentVaultAccountProbe.snapshot(vaultPath: "/fake/agent-vault") { _, args in
            if args.first == "tenant" { return tenantJSON }
            if args.first == "credential" { return credJSON }
            throw NSError(domain: "t", code: 1)
        }
        XCTAssertTrue(snap.vaultAvailable)
        XCTAssertNil(snap.error)
        XCTAssertEqual(snap.productTenant?.slug, "gujo")
        XCTAssertEqual(snap.credentials.count, 1)
        XCTAssertTrue(
            snap.headline.contains("카드 1장")
                || snap.headline.contains("card")
                || snap.headline.contains("AgentVaultAccountProbe")
                || !snap.headline.isEmpty
        )
        let text = AgentVaultAccountProbe.plainText(snap)
        XCTAssertTrue(text.contains("tenant:gujo"))
        XCTAssertTrue(text.contains("Gujo API"))
    }

    func testProductTenantConstants() {
        XCTAssertEqual(AgentVaultAccountProbe.productTenantSlug, "gujo")
        XCTAssertEqual(AgentVaultAccountProbe.productTenantID, "tenant:gujo")
    }
}
