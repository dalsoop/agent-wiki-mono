import CommandKit
import Foundation
import Testing

@testable import KnowledgeBaseWikiCore

// R2 키 출처(키체인 · Bitwarden 재실행) 시험. 실제 설정·키체인·볼트는 쓰지 않는다:
// 설정은 임시 폴더, 키체인은 주입 공급자, 실행 파일 찾기는 주입 함수, 환경은 사전으로 넘긴다.
// 근거: docs/security.md "R2 와 세션", 결정 0009.

struct AgentLawR2CredentialSourceTests {
    static let item = "ecf2f682-4ad5-40b7-84bc-b4db0016e74d"
    static let executable = "/Applications/AgentWikiGlobal.app/Contents/Helpers/agent-wiki-synchronizer"
    static let client = "/opt/homebrew/bin/vaultwarden-client"

    static let missingKeychain = LawKeychainCredentialProvider { _, _ in nil }
    static let presentKeychain = LawKeychainCredentialProvider { _, account in
        account == LawKeychainCredentialProvider.accessKeyAccount ? "KC-ACCESS" : "KC-SECRET"
    }
    static let received = LawR2Credentials(accessKeyID: "BW-ACCESS", secretAccessKey: "BW-SECRET")

    static func file(source: String?, endpoint: String? = "https://r2.example.test", device: String? = "mac",
                     dreamDevice: String? = nil) -> BoundLedgerFile
    {
        BoundLedgerFile(
            currentDevice: device, dreamDevice: dreamDevice,
            lawStorage: LawStorageSettings(endpoint: endpoint, credentialSource: source))
    }

    static func decide(
        _ command: [String], original: [String]? = nil, file: BoundLedgerFile,
        keychain: LawKeychainCredentialProvider = missingKeychain,
        handoff: LawR2EnvHandoff = LawR2EnvHandoff(isReexecChild: false, credentials: nil),
        executable: String? = executable, locate: (String) -> String? = { $0 == "vaultwarden-client" ? client : nil }
    ) -> LawR2BitwardenReexec.Decision {
        LawR2BitwardenReexec.decide(
            command: command, originalArguments: original ?? command, file: file, keychain: keychain,
            handoff: handoff, executable: executable, locate: locate)
    }

    // MARK: - 출처 설정

    @Test func credentialSourceOptionParsesSetsAndClears() throws {
        #expect(LawR2CredentialSource.settingValue(forOption: "bitwarden:\(Self.item)") == .success("bitwarden:\(Self.item)"))
        #expect(LawR2CredentialSource.settingValue(forOption: "none") == .success(nil))
        #expect(LawR2CredentialSource.settingValue(forOption: "keychain") == .success(nil))
        for bad in ["bitwarden:", "bitwarden:--env", "bitwarden:a b", "bitwarden:x;rm", "vault:abc", ""] {
            guard case .failure(let error) = LawR2CredentialSource.settingValue(forOption: bad) else {
                Issue.record("형식이 틀린 값을 받음: \(bad)")
                continue
            }
            #expect("\(error)".contains("bitwarden:<item id>"))
        }
        #expect(LawStorageSettings().resolvedCredentialSource == .keychain)
        #expect(LawStorageSettings(credentialSource: "bitwarden:\(Self.item)").resolvedCredentialSource
            == .bitwarden(itemID: Self.item))
        // 손으로 망가뜨린 값은 키체인으로 본다.
        #expect(LawStorageSettings(credentialSource: "garbage").resolvedCredentialSource == .keychain)
    }

    @Test func credentialSourceRoundTripsThroughHostConfigInTemporaryRoot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("r2-source-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("config.json")

        var file = Self.file(source: nil)
        file.lawStorage?.credentialSource = try LawR2CredentialSource.settingValue(forOption: "bitwarden:\(Self.item)").get()
        try WorldConfigStore.save(file, to: url)
        let saved = try JSONDecoder().decode(BoundLedgerFile.self, from: Data(contentsOf: url))
        #expect(saved.lawStorage?.resolvedCredentialSource == .bitwarden(itemID: Self.item))
        #expect(saved.lawStorage?.endpoint == "https://r2.example.test")

        var cleared = saved
        cleared.lawStorage?.credentialSource = try LawR2CredentialSource.settingValue(forOption: "none").get()
        try WorldConfigStore.save(cleared, to: url)
        let reloaded = try JSONDecoder().decode(BoundLedgerFile.self, from: Data(contentsOf: url))
        #expect(reloaded.lawStorage?.credentialSource == nil)
        #expect(reloaded.lawStorage?.resolvedCredentialSource == .keychain)

        // 출처 칸이 없는 옛 설정도 읽힌다(기본 키체인).
        let legacy = Data(#"{"lawStorage":{"endpoint":"https://r2.example.test"}}"#.utf8)
        let old = try JSONDecoder().decode(BoundLedgerFile.self, from: legacy)
        #expect(old.lawStorage?.resolvedCredentialSource == .keychain)
    }

    // MARK: - 해석

    @Test func keychainWinsOverBitwardenAndHandoff() throws {
        let resolver = LawR2CredentialResolver(
            source: .bitwarden(itemID: Self.item), keychain: Self.presentKeychain,
            handoff: LawR2EnvHandoff(isReexecChild: true, credentials: Self.received))
        #expect(try resolver.credentials().accessKeyID == "KC-ACCESS")
        let client = try LawR2Client.standard(file: Self.file(source: "bitwarden:\(Self.item)"), provider: resolver)
        #expect(client.credentials.secretAccessKey == "KC-SECRET")
    }

    @Test func reexecChildUsesHandedOffValues() throws {
        let resolver = LawR2CredentialResolver(
            source: .bitwarden(itemID: Self.item), keychain: Self.missingKeychain,
            handoff: LawR2EnvHandoff(isReexecChild: true, credentials: Self.received))
        let credentials = try resolver.credentials()
        #expect(credentials == Self.received)
    }

    @Test func emptyHandoffInChildFailsWithoutAnotherReexec() throws {
        let resolver = LawR2CredentialResolver(
            source: .bitwarden(itemID: Self.item), keychain: Self.missingKeychain,
            handoff: LawR2EnvHandoff(isReexecChild: true, credentials: nil))
        #expect(throws: LawR2CredentialError.bitwardenHandoffEmpty) { try resolver.credentials() }
        // 판정도 자식에서는 다시 실행하지 않는다.
        let decision = Self.decide(
            ["sync"], file: Self.file(source: "bitwarden:\(Self.item)"),
            handoff: LawR2EnvHandoff(isReexecChild: true, credentials: nil))
        #expect(decision == .proceed)
    }

    @Test func missingKeysGuideToCredentialSource() throws {
        let keychainOnly = LawR2CredentialResolver(
            source: .keychain, keychain: Self.missingKeychain, handoff: LawR2EnvHandoff(isReexecChild: false, credentials: nil))
        do {
            _ = try keychainOnly.credentials()
            Issue.record("키가 없는데 성공함")
        } catch {
            let message = "\(error)"
            #expect(message.contains("agent-wiki world storage --credential-source bitwarden:<item id>"))
            #expect(message.contains("키체인에 넣어"))
            #expect(message.contains("환경 변수·설정 파일로는 받지 않습니다"))
        }
        let notReexecuted = LawR2CredentialResolver(
            source: .bitwarden(itemID: Self.item), keychain: Self.missingKeychain,
            handoff: LawR2EnvHandoff(isReexecChild: false, credentials: nil))
        #expect(throws: LawR2CredentialError.bitwardenNotReexecuted(itemID: Self.item)) {
            try notReexecuted.credentials()
        }
    }

    // MARK: - 재실행으로 받은 환경 변수

    @Test func environmentWithoutMarkerIsRefused() throws {
        let manual = LawR2EnvHandoff(environment: [
            LawR2EnvHandoff.accessKeyVariable: "MANUAL-ACCESS", LawR2EnvHandoff.secretKeyVariable: "MANUAL-SECRET",
        ], ticketRedeemed: true)
        #expect(!manual.isReexecChild)
        #expect(manual.credentials == nil)
        let resolver = LawR2CredentialResolver(source: .keychain, keychain: Self.missingKeychain, handoff: manual)
        #expect(throws: LawR2CredentialError.self) { try resolver.credentials() }
    }

    @Test func environmentWithRedeemedTicketIsAcceptedAndMasked() throws {
        let handoff = LawR2EnvHandoff(environment: [
            LawR2EnvHandoff.markerVariable: "TICKET",
            LawR2EnvHandoff.accessKeyVariable: "BW-ACCESS", LawR2EnvHandoff.secretKeyVariable: " BW-SECRET\n",
        ], ticketRedeemed: true)
        #expect(handoff.isReexecChild)
        #expect(handoff.credentials == Self.received)
        #expect(!"\(handoff)".contains("BW-SECRET") && !"\(handoff)".contains("BW-ACCESS"))
        let partial = LawR2EnvHandoff(environment: [
            LawR2EnvHandoff.markerVariable: "TICKET", LawR2EnvHandoff.accessKeyVariable: "BW-ACCESS",
        ], ticketRedeemed: true)
        #expect(partial.isReexecChild && partial.credentials == nil)
        #expect(!"\(LawR2CredentialError.bitwardenHandoffEmpty)".contains("BW-ACCESS"))
    }

    @Test func markerWithoutTicketIsRefused() throws {
        // 표지까지 손으로 세워도 부모가 발급한 표를 교환하지 못하면 받지 않는다.
        let spoofed = LawR2EnvHandoff(environment: [
            LawR2EnvHandoff.markerVariable: UUID().uuidString,
            LawR2EnvHandoff.accessKeyVariable: "A", LawR2EnvHandoff.secretKeyVariable: "B",
        ], ticketRedeemed: false)
        #expect(!spoofed.isReexecChild)
        #expect(spoofed.credentials == nil)
    }

    @Test func handoffTicketIsOneShotAndExpires() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let tickets = LawR2HandoffTicket(directory: dir, maxAge: 120)
        let token = try #require(tickets.issue())
        let attributes = try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(token).path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect(tickets.redeem(token))
        #expect(!tickets.redeem(token))  // 한 번만
        #expect(!tickets.redeem("not-a-uuid"))
        #expect(!tickets.redeem(UUID().uuidString))  // 발급 안 한 표
        let old = try #require(tickets.issue())
        #expect(!tickets.redeem(old, now: Date().addingTimeInterval(121)))  // 오래된 표
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent(old).path))  // 그래도 지운다
    }

    @Test func scrubRemovesHandoffVariablesFromProcessEnvironment() throws {
        for name in LawR2EnvHandoff.variables { setenv(name, "TEST-ONLY", 1) }
        LawR2EnvHandoff.scrubProcessEnvironment()
        let environment = ProcessInfo.processInfo.environment
        for name in LawR2EnvHandoff.variables { #expect(environment[name] == nil) }
    }

    // MARK: - 재실행 판정

    @Test func bitwardenSourceBuildsNestedFieldExecPreservingArguments() throws {
        let original = ["--world", "agent-law", "--as", "agent:x", "sync", "--json"]
        let decision = Self.decide(
            ["sync", "--json"], original: original, file: Self.file(source: "bitwarden:\(Self.item)"))
        guard case .reexec(let plan) = decision else {
            Issue.record("재실행하지 않음: \(decision)")
            return
        }
        #expect(plan.program == Self.client)
        #expect(plan.argv == [
            Self.client, "item", "field", "exec", Self.item, "field:access-key-id",
            "--env", "AGENT_LAW_R2_ACCESS_KEY_ID", "--",
            Self.client, "item", "field", "exec", Self.item, "field:secret-access-key",
            "--env", "AGENT_LAW_R2_SECRET_ACCESS_KEY", "--",
            Self.executable, "--world", "agent-law", "--as", "agent:x", "sync", "--json",
        ])
    }

    @Test func reexecOnlyWhenNeededAndPossible() throws {
        let bitwarden = Self.file(source: "bitwarden:\(Self.item)")
        // 키체인에 값이 있으면 그대로.
        #expect(Self.decide(["sync"], file: bitwarden, keychain: Self.presentKeychain) == .proceed)
        // 출처 미설정(키체인)이면 다시 실행하지 않는다 — 명령이 안내와 함께 실패한다.
        #expect(Self.decide(["sync"], file: Self.file(source: nil)) == .proceed)
        // 엔드포인트가 없으면 금고를 열지 않는다.
        #expect(Self.decide(["sync"], file: Self.file(source: "bitwarden:\(Self.item)", endpoint: nil)) == .proceed)
        // R2 키가 필요 없는 명령·도움말·dry-run.
        #expect(Self.decide(["search", "x"], file: bitwarden) == .proceed)
        #expect(Self.decide(["archive", "--dry-run"], file: bitwarden) == .proceed)
        #expect(Self.decide(["redact", "--help"], file: bitwarden) == .proceed)
        #expect(Self.decide(["dream", "status"], file: bitwarden) == .proceed)
        // 드리밍은 드리밍 기기에서만.
        #expect(Self.decide(["dream", "run"], file: bitwarden) == .proceed)
        let dreamHost = Self.file(source: "bitwarden:\(Self.item)", device: "mac", dreamDevice: "mac")
        guard case .reexec = Self.decide(["dream", "run", "--scheduled"], file: dreamHost) else {
            Issue.record("드리밍 기기에서 재실행하지 않음")
            return
        }
        for command in [["archive"], ["redact", "k", "--reason", "r"], ["sync"]] {
            guard case .reexec = Self.decide(command, file: bitwarden) else {
                Issue.record("재실행하지 않음: \(command)")
                continue
            }
        }
        // 실행 파일을 못 찾으면 안내와 함께 실패.
        guard case .failure(let noClient) = Self.decide(["sync"], file: bitwarden, locate: { _ in nil }) else {
            Issue.record("vaultwarden-client 없이 진행함")
            return
        }
        #expect(noClient.contains("vaultwarden-client"))
        guard case .failure = Self.decide(["sync"], file: bitwarden, executable: nil) else {
            Issue.record("실행 파일 경로 없이 진행함")
            return
        }
    }

    @Test func locateUsesPathThenStandardDirectories() throws {
        let found = LawR2BitwardenReexec.locate(
            "vaultwarden-client", environment: ["PATH": "relative/bin:/custom/bin:/other/bin"],
            isExecutable: { $0 == "/custom/bin/vaultwarden-client" || $0 == "relative/bin/vaultwarden-client" })
        #expect(found == "/custom/bin/vaultwarden-client")
        let fallback = LawR2BitwardenReexec.locate(
            "vaultwarden-client", environment: [:],
            isExecutable: { $0 == "\(HostPlatformPaths.homebrewBin)/vaultwarden-client" })
        #expect(fallback == "\(HostPlatformPaths.homebrewBin)/vaultwarden-client")
        #expect(LawR2BitwardenReexec.locate("vaultwarden-client", environment: ["PATH": "/x"], isExecutable: { _ in false }) == nil)
    }
}
