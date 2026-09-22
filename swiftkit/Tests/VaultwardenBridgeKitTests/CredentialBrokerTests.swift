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

    @Test func homeControlAutofillLinkCarriesOnlyReferences() throws {
        let registrationID = UUID()
        let serverURL = try #require(URL(string: "https://home-assistant.external.kr"))
        let activationToken = String(repeating: "tok-", count: 8) + "x9y"
        let url = try #require(HomeControlAutofillLink.requestURL(
            registrationID: registrationID,
            vaultItemID: "home-control-card-42",
            serverURL: serverURL,
            activationToken: activationToken
        ))

        let request = try #require(HomeControlAutofillLink.request(from: url))
        #expect(request.registrationID == registrationID)
        #expect(request.vaultItemID == "home-control-card-42")
        #expect(request.serverURL == serverURL)
        #expect(request.activationToken == activationToken)
        #expect(!url.absoluteString.localizedCaseInsensitiveContains("password"))
        #expect(!url.absoluteString.localizedCaseInsensitiveContains("username"))
    }

    @Test func homeControlAutofillReadyCallbackRejectsUnexpectedValues() {
        let registrationID = UUID()
        let activationToken = String(repeating: "tok-", count: 8) + "x9y"
        let ready = HomeControlAutofillLink.ready(from: HomeControlAutofillLink.readyURL(
            registrationID: registrationID,
            activationToken: activationToken
        ))
        #expect(ready?.registrationID == registrationID)
        #expect(ready?.activationToken == activationToken)
        #expect(HomeControlAutofillLink.ready(from: URL(
            string: "home-control-dashboard://vault-autofill-ready?registration_id=\(registrationID.uuidString)&activation_token=\(activationToken)&password=no"
        )!) == nil)
    }

    @Test func homeControlAutofillLinkRejectsDuplicateOrInvalidLocatorFields() throws {
        let registrationID = UUID()
        let token = String(repeating: "tok-", count: 8) + "x9y"
        let duplicate = try #require(URL(string: "vaultwarden-client://home-control-autofill?registration_id=\(registrationID.uuidString)&item_id=one&item_id=two&uri=https%3A%2F%2Fhome.example&activation_token=\(token)"))
        #expect(HomeControlAutofillLink.request(from: duplicate) == nil)
        #expect(HomeControlAutofillLink.requestURL(
            registrationID: registrationID,
            vaultItemID: "item",
            serverURL: try #require(URL(string: "https://home.example")),
            activationToken: "too-short"
        ) == nil)
    }
}
