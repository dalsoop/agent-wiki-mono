import Foundation
import Testing
@testable import VaultwardenBridgeKit

@Suite struct CredentialBrokerTests {
    @Test func sessionExportAllowsAnyNamedLocalRequester() {
        #expect(VaultSessionExportPolicy.allows("agent-vault"))
        #expect(VaultSessionExportPolicy.allows("credential-manager"))
        #expect(VaultSessionExportPolicy.allows("llm-route-manager"))
        #expect(!VaultSessionExportPolicy.allows(""))
        #expect(!VaultSessionExportPolicy.allows("   "))
    }

    @Test func requestRoundTripsThroughNDJSON() throws {
        let request = VaultCredentialRequest(
            id: "request-1",
            requestingApp: "agent-browser",
            domain: "naver.com"
        )

        let encoded = try VaultCredentialCodec.encodeLine(request)
        #expect(encoded.last == 0x0A)
        #expect(try VaultCredentialCodec.decode(VaultCredentialRequest.self, from: encoded.dropLast()) == request)
    }

    @Test func successResponseKeepsCredentialsOutOfDescription() {
        let response = VaultCredentialResponse.success(username: "user@example.com", password: "secret-value")
        let description = String(describing: response)

        #expect(response.status == .success)
        #expect(!description.contains("user@example.com"))
        #expect(!description.contains("secret-value"))
    }

    @Test func statusResponsesCarryNoCredentials() {
        for status in VaultCredentialResponse.Status.allCases where status != .success {
            let response = VaultCredentialResponse(status: status)
            #expect(response.username == nil)
            #expect(response.password == nil)
        }
    }

    @Test func socketPathUsesApplicationSupport() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        #expect(VaultCredentialBrokerPaths.socketURL(homeDirectory: home).path ==
            "/Users/tester/Library/Application Support/VaultwardenClient/credential-broker.sock")
    }
}
