import XCTest
@testable import PackageIdentityKit

final class IdentityFormulaTests: XCTestCase {
    func testAppPrefixOmitsPrefixToken() {
        XCTAssertEqual(
            IdentityFormula.liveCLIName(prefix: "app", objectNoun: "Gujo VPN"),
            "gujo-vpn")
    }

    func testAgentPrefixKeepsToken() {
        XCTAssertEqual(
            IdentityFormula.liveCLIName(prefix: "agent", objectNoun: "Identity Install Ledger"),
            "agent-identity-install-ledger")
    }

    func testDirectoryStemStripsSwiftSuffix() {
        XCTAssertEqual(
            IdentityFormula.directoryStem("agent-never-shipped-swift"),
            "agent-never-shipped")
    }
}
