import AgentVaultClientKit
import CommandKit
import Foundation
import Testing

@Suite("AgentVaultClientKit")
struct AgentVaultClientTests {
    @Test func decodesTenantAndCredentialMetadata() async throws {
        let runner = StubRunner(responses: [
            "tenant": CommandResult(
                stdout: #"[{"id":"tenant:personal","name":"개인","slug":"personal","purpose":"","agentIDs":["app:nas-cutoff-transfer-manager@macbook"],"isActive":true,"rootPaths":["/Volumes/proj"]}]"#,
                stderr: "", exitCode: 0),
            "credential": CommandResult(
                stdout: #"[{"id":"cred-1","name":"Synology","kind":"smb","account":"backup","host":"nas.local","secretStored":true,"locator":{"providerID":"vaultwarden","itemID":"item-1","path":"/"}}]"#,
                stderr: "", exitCode: 0),
        ])
        let client = AgentVaultCLIClient(executablePath: "/fake/agent-vault", runner: runner)

        let tenants = try await client.tenants()
        let credentials = try await client.credentials()

        #expect(tenants.first?.isActive == true)
        #expect(tenants.first?.rootPaths == ["/Volumes/proj"])
        #expect(credentials.first?.providerID == "vaultwarden")
        #expect(credentials.first?.host == "nas.local")
    }

    @Test func pathCandidatesIncludeResolvedSymlinkAndWrappingApp() {
        let helpers = "/Applications/Gujo Cloud Apps.app/Contents/Helpers/gujo-cloud-apps"
        let fromHelpers = Set(AgentVaultPathMatch.candidates(for: helpers))
        #expect(fromHelpers.contains(helpers))
        #expect(fromHelpers.contains("/Applications/Gujo Cloud Apps.app"))
    }

    @Test func credentialsListAsksForEveryTenant() async throws {
        let runner = RecordingRunner(result: CommandResult(
            stdout: #"[]"#, stderr: "", exitCode: 0))
        let client = AgentVaultCLIClient(executablePath: "/fake/agent-vault", runner: runner)
        _ = try await client.credentials()
        let args = await runner.lastArguments
        #expect(args == ["credential", "list", "--tenant", "all", "--json"])
    }

    @Test func tenantSummaryDecodesWithoutRootPaths() throws {
        let json = Data(#"{"id":"tenant:ops","name":"Ops","slug":"ops","purpose":"x","agentIDs":[],"isActive":false}"#.utf8)
        let t = try JSONDecoder().decode(AgentVaultTenantSummary.self, from: json)
        #expect(t.rootPaths.isEmpty)
        #expect(t.slug == "ops")
    }

    @Test func deniedCheckIsDecodedEvenWithPermissionExitCode() async throws {
        let runner = StubRunner(responses: [
            "credential": CommandResult(
                stdout: #"{"credentialID":"cred-1","credentialName":"Synology","agentID":"app:nas-cutoff-transfer-manager@macbook","tenantID":"tenant:personal","allowed":false,"level":null,"reason":"권한 없음"}"#,
                stderr: "", exitCode: 77),
        ])
        let client = AgentVaultCLIClient(executablePath: "/fake/agent-vault", runner: runner)
        let result = try await client.check(AgentVaultCredentialContext(
            tenantID: "tenant:personal", credentialID: "cred-1"))

        #expect(result.allowed == false)
        #expect(result.reason == "권한 없음")
    }

    @Test func allowedCheckRequiresASuccessExitCode() async throws {
        let runner = StubRunner(responses: [
            "credential": CommandResult(
                stdout: #"{"credentialID":"cred-1","credentialName":"Synology","agentID":"app:nas-cutoff-transfer-manager@macbook","tenantID":"tenant:personal","allowed":true,"level":"use","reason":null}"#,
                stderr: "", exitCode: 0),
        ])
        let client = AgentVaultCLIClient(executablePath: "/fake/agent-vault", runner: runner)

        let result = try await client.check(AgentVaultCredentialContext(
            tenantID: "tenant:personal", credentialID: "cred-1"))

        #expect(result.allowed)
        #expect(result.level == "use")
    }

    @Test func unexpectedFailureCannotReturnAnAllowedDecision() async throws {
        let runner = StubRunner(responses: [
            "credential": CommandResult(
                stdout: #"{"credentialID":"cred-1","credentialName":"Synology","agentID":"app:nas-cutoff-transfer-manager@macbook","tenantID":"tenant:personal","allowed":true,"level":"use","reason":null}"#,
                stderr: "internal failure", exitCode: 70),
        ])
        let client = AgentVaultCLIClient(executablePath: "/fake/agent-vault", runner: runner)

        await #expect(throws: AgentVaultClientError.commandFailed(70, "internal failure")) {
            _ = try await client.check(AgentVaultCredentialContext(
                tenantID: "tenant:personal", credentialID: "cred-1"))
        }
    }
}


    @Test func useRunsCredentialUseCommandWithoutExposingSecretArgs() async throws {
        let runner = RecordingRunner(result: CommandResult(stdout: "mounted", stderr: "", exitCode: 0))
        let client = AgentVaultCLIClient(executablePath: "/fake/agent-vault", runner: runner)
        let result = try await client.use(
            AgentVaultCredentialContext(
                tenantID: "tenant:personal",
                credentialID: "cred-1",
                agentID: "app:mounter@macbook"),
            command: ["/opt/homebrew/bin/mounter", "mount", "synology", "--password-stdin"],
            timeout: 30)

        #expect(result.ok)
        #expect(result.stdout == "mounted")
        let args = await runner.lastArguments
        #expect(args.starts(with: [
            "credential", "use", "cred-1",
            "--agent", "app:mounter@macbook",
            "--tenant", "tenant:personal",
            "--",
        ]))
        #expect(args.contains("/opt/homebrew/bin/mounter"))
        #expect(!args.contains(where: { $0.lowercased().contains("password=") }))
    }

    @Test func useDeniedMapsToCommandFailed77() async throws {
        let runner = StubRunner(responses: [
            "credential": CommandResult(stdout: "", stderr: "권한 없음", exitCode: 77),
        ])
        let client = AgentVaultCLIClient(executablePath: "/fake/agent-vault", runner: runner)
        await #expect(throws: AgentVaultClientError.commandFailed(77, "권한 없음")) {
            _ = try await client.use(
                AgentVaultCredentialContext(tenantID: "tenant:personal", credentialID: "cred-1"),
                command: ["true"],
                timeout: 5)
        }
    }

    @Test func stubPathLooksLikeCredentialManager() {
        #expect(AgentVaultCLIClient.looksLikeCredentialManagerStub(
            resolvedPath: "/Applications/Credential Manager.app/Contents/Helpers/credential-manager"))
        #expect(AgentVaultCLIClient.looksLikeCredentialManagerStub(
            resolvedPath: "/opt/homebrew/bin/credential-manager"))
        #expect(!AgentVaultCLIClient.looksLikeCredentialManagerStub(
            resolvedPath: "/Applications/AgentVault.app/Contents/Helpers/agent-vault"))
    }

    @Test func useRejectsEmptyCommand() async throws {
        let runner = StubRunner(responses: [:])
        let client = AgentVaultCLIClient(executablePath: "/fake/agent-vault", runner: runner)
        await #expect(throws: AgentVaultClientError.invalidResponse("command 가 비어 있습니다")) {
            _ = try await client.use(
                AgentVaultCredentialContext(tenantID: "t", credentialID: "c"),
                command: [],
                timeout: 1)
        }
    }

private actor StubRunner: CommandRunning {
    let responses: [String: CommandResult]

    init(responses: [String: CommandResult]) {
        self.responses = responses
    }

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        responses[arguments.first ?? ""]
            ?? CommandResult(stdout: "", stderr: "missing stub", exitCode: 127)
    }
}


private actor RecordingRunner: CommandRunning {
    let result: CommandResult
    private(set) var lastArguments: [String] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        lastArguments = arguments
        return result
    }
}

@Suite("AgentVaultCard")
struct AgentVaultCardTests {
    @Test func pinTrimsAndIsThePersistedValue() {
        let card = AgentVaultCard(
            identity: .init(id: " cred-1 ", name: "NAS", kind: "smb"),
            account: .init(account: "backup", host: "nas.local", secretStored: true, locator: nil))
        #expect(card.pin.rawValue == "cred-1")
        #expect(AgentVaultCard.Pin(rawValue: "  ").isEmpty)
    }

    @Test func inferredHostStripsURLPath() {
        let card = AgentVaultCard(
            identity: .init(id: "r1", name: "iptime", kind: "usernamePassword"),
            account: .init(account: "admin", host: "http://192.168.2.1/ui/", secretStored: true, locator: nil))
        #expect(card.inferredHost == "192.168.2.1")
        #expect(card.subtitle == "admin · 192.168.2.1")
    }

    @Test func contextPrefersCardOwnerTenantOverFallback() {
        let card = AgentVaultCard(
            identity: .init(id: "g1", name: "Gujo", kind: "apiToken"),
            account: .init(account: "", host: "gujo.ai", secretStored: true, locator: nil),
            status: .init(ownerTenantID: "tenant:gujo"))
        #expect(card.context(agentID: "app:gujo@macbook").tenantID == "tenant:gujo")
    }

    @Test func selectableKeepsPinnedDumpAndDropsArchive() {
        let dump = AgentVaultCard(
            identity: .init(id: "dump", name: "vw", kind: "usernamePassword"),
            account: .init(account: "", host: "", secretStored: true, locator: nil),
            status: .init(managementState: "dump"))
        let archived = AgentVaultCard(
            identity: .init(id: "old", name: "gone", kind: "custom"),
            account: .init(account: "", host: "", secretStored: false, locator: nil),
            status: .init(archivedAt: Date(timeIntervalSince1970: 1)))
        let live = AgentVaultCard(
            identity: .init(id: "ok", name: "nas", kind: "smb"),
            account: .init(account: "u", host: "nas.local", secretStored: true, locator: nil),
            status: .init(managementState: "managed"))
        let kept = AgentVaultCard.selectable([dump, archived, live], keeping: dump.pin)
        #expect(Set(kept.map(\.id)) == ["dump", "ok"])
    }

    @Test func gateEmptyPinDoesNotCallVault() async {
        let client = CardRecordingClient()
        let result = await client.gate(
            pin: "  ", fallbackAgentID: "app:test@macbook", deniedFallback: "grant 필요")
        #expect(result.allowed == false)
        #expect(result.reason == AgentVaultCardGate.emptyPinReason)
        #expect(await client.checkCalls == 0)
    }
}

private actor CardRecordingClient: AgentVaultAccessClient {
    var checkCalls = 0
    func tenants() async throws -> [AgentVaultTenantSummary] { [] }
    func credentials() async throws -> [AgentVaultCard] { [] }
    func agents() async throws -> [AgentVaultAgentSummary] { [] }
    func check(_ context: AgentVaultCredentialContext) async throws -> AgentVaultAccessCheck {
        checkCalls += 1
        return AgentVaultAccessCheck(
            credentialID: context.credentialID, credentialName: "", agentID: context.agentID,
            tenantID: context.tenantID, allowed: false, level: nil, reason: nil)
    }
    func use(_ context: AgentVaultCredentialContext, command: [String], timeout: TimeInterval?) async throws -> AgentVaultUseResult {
        AgentVaultUseResult(exitCode: 0, stdout: "", stderr: "")
    }
    func fetch(_ context: AgentVaultCredentialContext) async throws -> AgentVaultSecret {
        AgentVaultSecret(credentialID: context.credentialID, credentialName: "", username: nil, value: "x")
    }
}
