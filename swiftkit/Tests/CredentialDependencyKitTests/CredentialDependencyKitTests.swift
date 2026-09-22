import Foundation
import Testing
@testable import CredentialDependencyKit

private struct FakeProvider: CredentialProviding {
    let descriptor = CredentialProviderDescriptor(
        id: "provider", name: "Fake", kind: .custom)
    let secret: String

    func listMetadata() async throws -> [CredentialDescriptor] { [] }
    func resolve(_ locator: CredentialLocator) async throws -> CredentialSecret {
        CredentialSecret(username: "test-user", value: secret)
    }
}

private actor FakeConsumer: CredentialConsuming {
    nonisolated let descriptor = CredentialConsumerDescriptor(
        id: "consumer", name: "Fake", kind: .application, executablePath: "/bin/cat")
    private(set) var received = false

    func consume(_ secret: CredentialSecret, binding: CredentialBinding) async throws -> CredentialConsumptionResult {
        received = true
        return CredentialConsumptionResult(exitCode: 0, standardOutput: "ok")
    }
}

private func fixture(access: CredentialDependencyAccess? = nil) -> (CredentialDependencyCatalog, CredentialBinding) {
    let credential = CredentialDescriptor(
        id: "credential", name: "NAS", kind: "smb",
        locator: CredentialLocator(providerID: "provider", itemID: "item"))
    let consumer = CredentialConsumerDescriptor(
        id: "consumer", name: "Mounter", kind: .application, executablePath: "/bin/cat")
    let binding = CredentialBinding(
        id: "binding", credentialID: credential.id, consumerID: consumer.id,
        purpose: "mount", delivery: .stdin)
    return (CredentialDependencyCatalog(
        providers: [CredentialProviderDescriptor(id: "provider", name: "Fake", kind: .custom)],
        credentials: [credential],
        consumers: [consumer],
        authorizations: access.map { [CredentialAuthorization(
            credentialID: credential.id, consumerID: consumer.id, access: $0)] } ?? [],
        bindings: [binding]), binding)
}

@Suite struct CredentialDependencyKitTests {
    @Test func authorizationScopeDoesNotLeakAcrossTenants() {
        var value = fixture().0
        value.authorizations = [CredentialAuthorization(
            credentialID: "credential", consumerID: "consumer", access: .use,
            scopeID: "tenant-a")]
        #expect(CredentialDependencyPolicy.decision(
            credentialID: "credential", consumerID: "consumer",
            catalog: value, scopeID: "tenant-a") == .allowed(.use))
        #expect(!CredentialDependencyPolicy.decision(
            credentialID: "credential", consumerID: "consumer",
            catalog: value, scopeID: "tenant-b").isAllowed)
    }

    @Test func defaultDenyAndManageSeparation() {
        let denied = fixture()
        #expect(!CredentialDependencyPolicy.bindingDecision(
            bindingID: denied.1.id, catalog: denied.0).isAllowed)

        let use = fixture(access: .use)
        #expect(CredentialDependencyPolicy.bindingDecision(
            bindingID: use.1.id, catalog: use.0) == .allowed(.use))
        #expect(!CredentialDependencyPolicy.managementDecision(
            credentialID: "credential", consumerID: "consumer", catalog: use.0).isAllowed)

        let manage = fixture(access: .manage)
        #expect(CredentialDependencyPolicy.managementDecision(
            credentialID: "credential", consumerID: "consumer", catalog: manage.0) == .allowed(.manage))
    }

    @Test func graphValidationFindsBrokenReferences() {
        var value = fixture(access: .use).0
        value.providers = []
        let issues = CredentialDependencyPolicy.validate(value)
        #expect(issues.contains { $0.id == "credential-provider:credential" })
    }

    @Test func brokerNeverResolvesBeforeAuthorization() async throws {
        let value = fixture()
        let consumer = FakeConsumer()
        let broker = CredentialDependencyBroker(
            catalog: value.0,
            providers: [FakeProvider(secret: "fake-secret")],
            consumers: [consumer])
        await #expect(throws: CredentialDependencyError.self) {
            try await broker.deliver(bindingID: value.1.id)
        }
        #expect(await !consumer.received)
    }

    @Test func brokerDeliversOnlyAfterAuthorization() async throws {
        let value = fixture(access: .use)
        let consumer = FakeConsumer()
        let broker = CredentialDependencyBroker(
            catalog: value.0,
            providers: [FakeProvider(secret: "fake-secret")],
            consumers: [consumer])
        let result = try await broker.deliver(bindingID: value.1.id)
        #expect(result.exitCode == 0)
        #expect(await consumer.received)
    }

    @Test func processConsumerRedactsSecretAndUsername() async throws {
        let descriptor = CredentialConsumerDescriptor(
            id: "cat", name: "cat", kind: .application, executablePath: "/bin/cat")
        let consumer = ProcessCredentialConsumer(descriptor: descriptor)
        let binding = CredentialBinding(
            credentialID: "credential", consumerID: descriptor.id,
            purpose: "test", delivery: .stdin)
        let result = try await consumer.consume(
            CredentialSecret(username: "fake-user", value: "fake-secret"), binding: binding)
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == "[REDACTED]\n")
        #expect(!result.standardOutput.contains("fake-secret"))
    }

    @Test func secretDescriptionIsAlwaysRedacted() {
        let secret = CredentialSecret(username: "fake-user", value: "fake-secret")
        #expect(String(describing: secret) == "CredentialSecret(<redacted>)")
        #expect(!String(reflecting: secret).contains("fake-secret"))
    }

    @Test func executableMatchesAllowsHelpersInsideRegisteredAppBundle() {
        let app = "/Applications/Example.app"
        let helper = app + "/Contents/Helpers/example"
        #expect(CredentialDependencyPolicy.executableMatches(
            expectedPath: app, requestedPath: helper))
        #expect(!CredentialDependencyPolicy.executableMatches(
            expectedPath: app, requestedPath: "/bin/zsh"))
    }
}
