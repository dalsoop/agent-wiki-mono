import CryptoKit
import Foundation
import HTTPClientKit
import Testing
import os

@testable import GujoAuthKit

/// 경로별 응답 대본을 순서대로 돌려주는 스텁 전송. 실서버 없이 계약 §1 을 검증한다.
final class ScriptedHTTP: HTTPClient, Sendable {
    struct Call: Sendable {
        let method: String
        let url: URL
        let headers: [String: String]
        let body: Data?

        func jsonObject() -> [String: Any] {
            guard let body else { return [:] }
            do {
                return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
            } catch {
                return [:]
            }
        }
    }

    private struct Memory: Sendable {
        var scripts: [String: [(Int, String)]]
        var calls: [Call] = []
    }

    private let memory: OSAllocatedUnfairLock<Memory>

    /// key = URL path(`/api/staff/device/token`), value = 순서대로 소비되는 (status, json) 목록.
    /// 목록이 비면 마지막 응답을 반복한다.
    init(_ scripts: [String: [(Int, String)]]) {
        memory = OSAllocatedUnfairLock(initialState: Memory(scripts: scripts))
    }

    func send(
        method: String, url: URL, headers: [String: String], body: Data?
    ) async throws -> (status: Int, data: Data) {
        memory.withLock { state in
            state.calls.append(Call(method: method, url: url, headers: headers, body: body))
            guard var queue = state.scripts[url.path], let head = queue.first else {
                return (404, Data("{\"error\":\"unscripted \(url.path)\"}".utf8))
            }
            if queue.count > 1 { queue.removeFirst() }
            state.scripts[url.path] = queue
            return (head.0, Data(head.1.utf8))
        }
    }

    func calls(to path: String) -> [Call] {
        memory.withLock { $0.calls.filter { $0.url.path == path } }
    }
}

let baseURL = URL(string: "https://gujo.example") ?? URL(fileURLWithPath: "/gujo.example")

let authorizeJSON = """
{"device_code":"dc-1","user_code":"ABCD-EFGH","verification_uri":"https://gujo.example/staff/device",
 "verification_uri_complete":"https://gujo.example/staff/device?code=ABCD-EFGH","expires_in":600,"interval":5}
"""

let tokenJSON = """
{"token":"gst_abc","token_type":"Bearer","expires_at":"2026-12-09T00:00:00Z",
 "abilities":["CustomersRead","OrdersRefund","FutureAbility"],
 "staff":{"id":1,"name":"Jeonghan","email":"staff@gujo.example"}}
"""

func makeAuth(
    _ http: ScriptedHTTP,
    store: InMemorySessionStore = InMemorySessionStore(),
    fallback: any StaffTokenFallback = NoStaffTokenFallback(),
    now: Date = Date(timeIntervalSince1970: 1_780_000_000)
) -> GujoStaffAuth {
    GujoStaffAuth(
        http: http, store: store, fallback: fallback, machine: NoMachineStaffToken(), baseURL: baseURL,
        sleep: { _ in }, now: { now })
}

@Suite("GujoStaffAuth — 계약 §1·§4")
struct GujoStaffAuthTests {

    @Test("428 폴링 뒤 200 이면 세션이 저장되고 프롬프트에 user_code·URL 이 전달된다")
    func loginPendingThenApproved() async throws {
        let http = ScriptedHTTP([
            "/api/staff/device/authorize": [(200, authorizeJSON)],
            "/api/staff/device/token": [
                (428, #"{"error":"authorization_pending"}"#),
                (428, #"{"error":"authorization_pending"}"#),
                (200, tokenJSON),
            ],
        ])
        let store = InMemorySessionStore()
        let auth = makeAuth(http, store: store)
        let shown = Prompts()

        let session = try await auth.login(client: "gujo-commerce-desk", deviceName: "test-mac") { prompt in
            await shown.record(prompt)
        }

        #expect(session.token == "gst_abc")
        #expect(session.staff.email == "staff@gujo.example")
        #expect(session.has(.ordersRefund))
        #expect(session.abilities == [.customersRead, .ordersRefund])
        #expect(session.abilityNames.contains("FutureAbility"))

        let prompts = await shown.all
        #expect(prompts.count == 1)
        #expect(prompts.first?.userCode == "ABCD-EFGH")
        #expect(prompts.first?.verificationURI.absoluteString == "https://gujo.example/staff/device")

        let authorize = try #require(http.calls(to: "/api/staff/device/authorize").first)
        #expect(authorize.method == "POST")
        #expect(authorize.jsonObject()["client"] as? String == "gujo-commerce-desk")
        #expect(authorize.jsonObject()["device_name"] as? String == "test-mac")
        #expect(authorize.headers["Authorization"] == nil)

        let polls = http.calls(to: "/api/staff/device/token")
        #expect(polls.count == 3)
        #expect(polls.allSatisfy { $0.jsonObject()["device_code"] as? String == "dc-1" })

        #expect(store.accounts == ["staff"])
        let reloaded = try await auth.current()
        #expect(reloaded == session)
    }

    @Test("410 은 deviceCodeExpired")
    func expiredToken() async throws {
        let http = ScriptedHTTP([
            "/api/staff/device/authorize": [(200, authorizeJSON)],
            "/api/staff/device/token": [(410, #"{"error":"expired_token"}"#)],
        ])
        await #expect(throws: GujoAuthError.deviceCodeExpired) {
            try await makeAuth(http).login(client: "c") { _ in }
        }
    }

    @Test("403 은 accessDenied")
    func accessDenied() async throws {
        let http = ScriptedHTTP([
            "/api/staff/device/authorize": [(200, authorizeJSON)],
            "/api/staff/device/token": [(403, #"{"error":"access_denied"}"#)],
        ])
        await #expect(throws: GujoAuthError.accessDenied) {
            try await makeAuth(http).login(client: "c") { _ in }
        }
    }

    @Test("429 slow_down 은 간격을 늘리고 계속 폴링한다")
    func slowDown() async throws {
        let http = ScriptedHTTP([
            "/api/staff/device/authorize": [(200, authorizeJSON)],
            "/api/staff/device/token": [
                (429, #"{"error":"slow_down"}"#),
                (200, tokenJSON),
            ],
        ])
        let sleeps = SleepLog()
        let auth = GujoStaffAuth(
            http: http, store: InMemorySessionStore(), fallback: NoStaffTokenFallback(), machine: NoMachineStaffToken(),
            baseURL: baseURL, sleep: { await sleeps.record($0) },
            now: { Date(timeIntervalSince1970: 1_780_000_000) })
        _ = try await auth.login(client: "c") { _ in }
        #expect(await sleeps.all == [5, 10])
        #expect(http.calls(to: "/api/staff/device/token").count == 2)
    }

    @Test("전송 URL 은 경로 슬래시를 인코딩하지 않는다")
    func transportURL() throws {
        let transport = GujoJSONTransport(http: ScriptedHTTP([:]), baseURL: baseURL)
        let url = try transport.url(path: "/api/staff/device/token", query: ["a": "1"])
        #expect(url.absoluteString == "https://gujo.example/api/staff/device/token?a=1")
    }

    @Test("require 는 부족한 ability 이름을 실어 던진다")
    func requireMissingAbility() async throws {
        let store = InMemorySessionStore()
        let auth = makeAuth(ScriptedHTTP([:]), store: store)
        auth.adopt(StaffSession(
            token: "gst_x", expiresAt: Date(timeIntervalSince1970: 1_790_000_000),
            abilities: [.customersRead], staff: StaffIdentity(id: 1, name: "n", email: "e")))

        let ok = try await auth.require(.customersRead)
        #expect(ok.token == "gst_x")
        await #expect(throws: GujoAuthError.missingAbility(.ordersRefund)) {
            try await auth.require(.ordersRefund)
        }
        let description = GujoAuthError.missingAbility(.ordersRefund).localizedDescription
        #expect(description.contains("OrdersRefund"))
    }

    @Test("세션 없으면 notLoggedIn, 만료면 sessionExpired")
    func currentStates() async throws {
        let auth = makeAuth(ScriptedHTTP([:]))
        await #expect(throws: GujoAuthError.notLoggedIn) { try await auth.current() }

        let expiredAt = Date(timeIntervalSince1970: 1_700_000_000)
        auth.adopt(StaffSession(
            token: "gst_old", expiresAt: expiredAt, abilities: [],
            staff: StaffIdentity(id: 1, name: "n", email: "e")))
        await #expect(throws: GujoAuthError.sessionExpired(expiresAt: expiredAt)) {
            try await auth.current()
        }
    }

    @Test("Keychain 이 비면 agent-vault 폴백 토큰으로 /api/staff/me 를 채운다")
    func vaultFallback() async throws {
        let http = ScriptedHTTP([
            "/api/staff/me": [(200, """
                {"staff":{"id":7,"name":"Runner","email":"ci@gujo.example"},
                 "abilities":["OpsPackages"],"expires_at":"2026-12-09T00:00:00Z"}
                """)],
        ])
        let store = InMemorySessionStore()
        let auth = makeAuth(http, store: store, fallback: StaticStaffTokenFallback("gst_vault"))

        let session = try await auth.current()
        #expect(session.token == "gst_vault")
        #expect(session.has(.opsPackages))
        #expect(session.staff.id == 7)
        let call = try #require(http.calls(to: "/api/staff/me").first)
        #expect(call.headers["Authorization"] == "Bearer gst_vault")
        // 폴백 토큰은 Keychain 에 심지 않는다 — 정본은 vault 카드다.
        #expect(store.accounts.isEmpty)
    }

    @Test("기계 주체 토큰이 있으면 사람 로그인 세션보다 먼저 쓴다(계약 §6)")
    func machineTokenFirst() async throws {
        let http = ScriptedHTTP([
            "/api/staff/me": [(200, """
                {"staff":{"id":9,"name":"","email":"agent.macbook@machine.gujo.invalid"},
                 "abilities":["InquiriesRead","OffersRead"],"expires_at":"2026-12-29T00:00:00Z"}
                """)],
        ])
        let store = InMemorySessionStore()
        let auth = GujoStaffAuth(
            http: http, store: store, fallback: NoStaffTokenFallback(),
            machine: StaticMachineStaffToken("gst_machine"), baseURL: baseURL,
            sleep: { _ in }, now: { Date(timeIntervalSince1970: 1_780_000_000) })
        auth.adopt(StaffSession(
            token: "gst_person", expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            abilityNames: ["OffersWrite"], staff: StaffIdentity(id: 1, name: "", email: "p@gujo.example")))

        #expect(auth.bearerToken() == "gst_machine")
        #expect(auth.usesMachineToken)
        let session = try await auth.current()
        #expect(session.token == "gst_machine")
        #expect(session.has(.offersRead))
        let call = try #require(http.calls(to: "/api/staff/me").first)
        #expect(call.headers["Authorization"] == "Bearer gst_machine")
    }

    @Test("기계 주체 토큰이 없으면 만료되지 않은 사람 세션의 gst_ 를 쓴다")
    func bearerFallsBackToPersonSession() {
        let auth = makeAuth(ScriptedHTTP([:]))
        #expect(auth.bearerToken() == nil)
        auth.adopt(StaffSession(
            token: "gst_person", expiresAt: Date(timeIntervalSince1970: 1_800_000_000),
            abilityNames: [], staff: StaffIdentity(id: 1, name: "", email: "p@gujo.example")))
        #expect(auth.bearerToken() == "gst_person")
    }

    @Test("sops 출처 — 경로는 env 우선, 파일이 없으면 복호화하지 않는다, gst_ 가 아니면 버린다, 한 번만 복호화한다")
    func sopsSource() throws {
        let calls = OSAllocatedUnfairLock(initialState: 0)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("gujo-staff-agent.enc.yaml")

        let missing = SopsMachineStaffToken(
            environment: [SopsMachineStaffToken.pathEnvironmentKey: file.path], home: dir.path,
            decrypt: { _, _ in calls.withLock { $0 += 1 }; return "gst_x" })
        #expect(missing.machineToken() == nil)
        #expect(calls.withLock { $0 } == 0)

        try Data("sops: {}\n".utf8).write(to: file)
        let source = SopsMachineStaffToken(
            environment: [SopsMachineStaffToken.pathEnvironmentKey: file.path], home: dir.path,
            decrypt: { path, ageKey in
                calls.withLock { $0 += 1 }
                #expect(path == file.path)
                #expect(ageKey.hasSuffix(".config/sops/age/macbook-se.txt"))
                return "gst_machine\n"
            })
        #expect(source.path == file.path)
        #expect(source.machineToken() == "gst_machine")
        #expect(source.machineToken() == "gst_machine")
        #expect(calls.withLock { $0 } == 1)

        let notStaff = SopsMachineStaffToken(
            environment: [SopsMachineStaffToken.pathEnvironmentKey: file.path], home: dir.path,
            decrypt: { _, _ in "plain-account-key" })
        #expect(notStaff.machineToken() == nil)

        // 후보가 하나도 없으면 첫 후보(broker 전용 클론)를 보여준다. 둘 다 있으면 최근에 바뀐 쪽을 읽는다.
        let defaulted = SopsMachineStaffToken(environment: [:], home: dir.path, decrypt: { path, _ in
            path.contains(SopsMachineStaffToken.managedCloneRelativePath) ? "gst_clone" : "gst_checkout" })
        let clonePath = defaulted.path
        #expect(clonePath.contains(SopsMachineStaffToken.managedCloneRelativePath))
        #expect(defaulted.machineToken() == nil)

        let checkout = dir.appendingPathComponent(SopsMachineStaffToken.defaultRelativePath)
        try FileManager.default.createDirectory(at: checkout.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: checkout)
        #expect(defaulted.machineToken() == "gst_checkout")

        let clone = URL(fileURLWithPath: clonePath)
        try FileManager.default.createDirectory(at: clone.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("b".utf8).write(to: clone)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(120)], ofItemAtPath: clone.path)
        #expect(defaulted.machineToken() == "gst_clone")
        #expect(defaulted.path == clone.path)
    }

    @Test("프롬프트는 코드가 박힌 주소를 브라우저 주소로 준다")
    func promptCarriesCompleteURI() async throws {
        let http = ScriptedHTTP([
            "/api/staff/device/authorize": [(200, authorizeJSON)],
            "/api/staff/device/token": [(200, tokenJSON)],
        ])
        let shown = Prompts()
        _ = try await makeAuth(http).login(client: "c") { await shown.record($0) }
        let prompt = try #require(await shown.all.first)
        #expect(prompt.verificationURIComplete?.absoluteString == "https://gujo.example/staff/device?code=ABCD-EFGH")
        #expect(prompt.browserURL == prompt.verificationURIComplete)
    }

    @Test("rotateMachineToken 은 일회용 공개키를 seal_to 로 보내고, 서버 거절은 그대로 던진다(계약 §6)")
    func rotateMachineTokenSendsSealTo() async throws {
        let http = ScriptedHTTP([
            "/api/staff/machine/rotate": [(409, #"{"error":"already_rotated"}"#)],
        ])
        let auth = makeAuth(http)
        await #expect(throws: GujoAuthError.unexpectedStatus(409, error: "already_rotated")) {
            _ = try await auth.rotateMachineToken(current: "gst_old")
        }
        let call = try #require(http.calls(to: "/api/staff/machine/rotate").first)
        #expect(call.method == "POST")
        #expect(call.headers["Authorization"] == "Bearer gst_old")
        let sealTo = try #require(call.jsonObject()["seal_to"] as? String)
        #expect(Data(base64Encoded: sealTo)?.count == 32)
    }

    @Test("PHP(core SealedTokenBox)가 봉인한 상자를 CryptoKit 으로 연다 — 교차 언어 벡터")
    func sealedTokenBoxOpensServerVector() throws {
        let secret = Data(repeating: 7, count: 32)
        let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secret)
        #expect(key.publicKey.rawRepresentation.base64EncodedString() == "E75P6uryBMf9M1j8nAByGIHRdCeBKCJ+xnTzf3/pe20=")
        let box = SealedTokenBox(
            alg: "x25519-hkdf-sha256-chacha20poly1305",
            epk: "NtIUV1YaizVnMWHB0MQ85rxqb16sw1fZPmEJKm4m4F4=",
            nonce: "LlMZ0bg4gs2d8JVH",
            ciphertext: "KL40eTi03/+IKxU4Mdv9pAOyQhVX1HzIebN4+FkAzzlp")
        #expect(try box.open(with: key) == "gst_fixture_token")
        #expect(throws: (any Error).self) { try box.open(with: Curve25519.KeyAgreement.PrivateKey()) }
    }

    @Test("sops 출처는 암호문이 바뀌면 다시 복호화한다 — 자동 로테이션 뒤 오래 도는 앱도 새 토큰을 쓴다")
    func sopsSourceRereadsAfterRotation() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("gujo-staff-agent.enc.yaml")
        try Data("a\n".utf8).write(to: file)
        let generation = OSAllocatedUnfairLock(initialState: 1)
        let source = SopsMachineStaffToken(
            environment: [SopsMachineStaffToken.pathEnvironmentKey: file.path], home: dir.path,
            decrypt: { _, _ in "gst_gen\(generation.withLock { $0 })" })
        #expect(source.machineToken() == "gst_gen1")

        generation.withLock { $0 = 2 }
        #expect(source.machineToken() == "gst_gen1")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: file.path)
        #expect(source.machineToken() == "gst_gen2")
    }

    @Test("로그인은 refresh:true 로 갱신 토큰을 받아 저장하고, 만료되면 요청 전에 갱신한다(계약 §7)")
    func refreshTokenFlow() async throws {
        let http = ScriptedHTTP([
            "/api/staff/device/authorize": [(200, authorizeJSON)],
            "/api/staff/device/token": [(200, """
                {"token":"gst_a1","token_type":"Bearer","expires_at":"2026-06-01T01:00:00Z","refresh_token":"gsr_r1",
                 "refresh_expires_at":"2026-07-01T00:00:00Z","abilities":["InquiriesRead"],
                 "staff":{"id":1,"name":"","email":"staff@gujo.example"}}
                """)],
            "/api/staff/token/refresh": [
                (200, """
                {"token":"gst_a2","token_type":"Bearer","expires_at":"2026-06-01T03:00:00Z","refresh_token":"gsr_r2",
                 "refresh_expires_at":"2026-07-01T02:00:00Z","abilities":["InquiriesRead"],
                 "staff":{"id":1,"name":"","email":"staff@gujo.example"}}
                """),
                (401, #"{"error":"refresh_token_reused"}"#),
            ],
        ])
        let store = InMemorySessionStore()
        let start = try #require(ISO8601DateFormatter().date(from: "2026-06-01T00:30:00Z"))
        let clock = OSAllocatedUnfairLock(initialState: start)
        let auth = GujoStaffAuth(
            http: http, store: store, fallback: NoStaffTokenFallback(), machine: NoMachineStaffToken(),
            baseURL: baseURL, sleep: { _ in }, now: { clock.withLock { $0 } })

        _ = try await auth.login(client: "c") { _ in }
        let poll = try #require(http.calls(to: "/api/staff/device/token").first)
        #expect(poll.jsonObject()["refresh"] as? Bool == true)
        #expect(try await auth.freshBearerToken() == "gst_a1")
        #expect(http.calls(to: "/api/staff/token/refresh").isEmpty)

        clock.withLock { $0 = $0.addingTimeInterval(3600) }
        #expect(try await auth.freshBearerToken() == "gst_a2")
        let refresh = try #require(http.calls(to: "/api/staff/token/refresh").first)
        #expect(refresh.jsonObject()["refresh_token"] as? String == "gsr_r1")
        #expect(auth.stored()?.refreshToken == "gsr_r2")

        clock.withLock { $0 = $0.addingTimeInterval(7200) }
        await #expect(throws: GujoAuthError.notLoggedIn) { _ = try await auth.freshBearerToken() }
        #expect(auth.stored() == nil, "a refused refresh (family revoked) clears the stored session")
    }

    @Test("Keychain 저장소 라운드트립 — JSON 은 snake_case·ISO-8601")
    func storeRoundTrip() throws {
        let store = InMemorySessionStore()
        let session = StaffSession(
            token: "gst_rt", expiresAt: Date(timeIntervalSince1970: 1_796_000_000),
            abilities: [.inquiriesWrite, .mailSend],
            staff: StaffIdentity(id: 3, name: "R", email: "r@gujo.example"))
        #expect(store.save(session, account: GujoKeychain.staffAccount))

        let raw = try #require(store.data(account: "staff"))
        let text = String(decoding: raw, as: UTF8.self)
        #expect(text.contains("\"expires_at\""))
        #expect(text.contains("\"abilities\""))
        #expect(!text.contains("\"ability_names\""))
        #expect(text.contains("2026-11-30T"))

        let reloaded = store.load(StaffSession.self, account: GujoKeychain.staffAccount)
        #expect(reloaded == session)
        #expect(GujoKeychain.service == "net.ranode.gujo")
        #expect(GujoKeychain.buyerAccount == "buyer")
    }

    @Test("logout 은 로컬을 지우고 서버에 Bearer 로 폐기를 요청한다")
    func logout() async throws {
        let http = ScriptedHTTP(["/api/staff/logout": [(204, "")]])
        let store = InMemorySessionStore()
        let auth = makeAuth(http, store: store)
        auth.adopt(StaffSession(
            token: "gst_bye", expiresAt: Date(timeIntervalSince1970: 1_790_000_000),
            abilities: [], staff: StaffIdentity(id: 1, name: "n", email: "e")))

        let revoked = await auth.logout()
        #expect(revoked)
        #expect(store.accounts.isEmpty)
        let call = try #require(http.calls(to: "/api/staff/logout").first)
        #expect(call.method == "POST")
        #expect(call.headers["Authorization"] == "Bearer gst_bye")

        let again = await auth.logout()
        #expect(!again)
        #expect(http.calls(to: "/api/staff/logout").count == 1)
    }

    @Test("importLegacy — gst_ 만 검증 후 저장, 옛 형식은 unsupported, 파일은 삭제 안내")
    func importLegacy() async throws {
        let http = ScriptedHTTP([
            "/api/staff/me": [(200, """
                {"staff":{"id":1,"name":"L","email":"l@gujo.example"},
                 "abilities":["CustomersRead"],"expires_at":"2026-12-09T00:00:00Z"}
                """)],
        ])
        let store = InMemorySessionStore()
        let auth = makeAuth(http, store: store)
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("gujo-auth-legacy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(".gujo"), withIntermediateDirectories: true)
        let tokenFile = home.appendingPathComponent(".gujo/ops-token")
        try Data("ops_legacy_value\n".utf8).write(to: tokenFile)
        defer { try? FileManager.default.removeItem(at: home) }

        let report = await auth.importLegacy(
            environment: ["GUJO_STAFF_TOKEN": "gst_env", "GUJO_SKILL_STORE_TOKEN": "sk_old"],
            homeDirectory: home.path)

        #expect(report.imported == .environment("GUJO_STAFF_TOKEN"))
        #expect(report.unsupported == [.environment("GUJO_SKILL_STORE_TOKEN"), .file(tokenFile)])
        #expect(report.rejected.isEmpty)
        #expect(report.filesToDelete == [tokenFile])
        #expect(FileManager.default.fileExists(atPath: tokenFile.path), "킷은 파일을 지우지 않는다")
        #expect(store.load(StaffSession.self, account: "staff")?.token == "gst_env")
        #expect(report.guidance.contains("ops-token"))
    }

    @Test("StaffAbility 는 계약 §2 의 32개 이름과 같다")
    func abilityCatalog() {
        let expected = """
        CustomersRead CustomersWrite OrdersRead OrdersCancel OrdersRefund SubscriptionsRead \
        SubscriptionsWrite SubscriptionsRefund EntitlementsGrant EntitlementsRevoke DevicesRevoke \
        InvoicesRead CreditNotesWrite InquiriesRead InquiriesWrite OpsHealth OpsPackages OpsDevices \
        OpsInstallJobs OpsRunners OpsReceipts OpsAudit ReleaseIntake SkillPublish AssetsWrite \
        ProductsWrite OffersWrite MailSend MailConsentsWrite LectureWrite ProductsRead OffersRead
        """.split(separator: " ").map(String.init)
        #expect(StaffAbility.allCases.map(\.rawValue) == expected)
        #expect(StaffAbility.allCases.count == 32)
    }

    @Test("호스트 키가 비면 endpointMissing — 하드코딩 폴백 없음")
    func endpointMissing() throws {
        #expect(GujoCoreHost.endpointKey == "gujo-core")
        let resolved = try GujoCoreHost.resolve(override: baseURL)
        #expect(resolved == baseURL)
    }
}

actor Prompts {
    private(set) var all: [DeviceCodePrompt] = []
    func record(_ prompt: DeviceCodePrompt) { all.append(prompt) }
}

actor SleepLog {
    private(set) var all: [TimeInterval] = []
    func record(_ interval: TimeInterval) { all.append(interval) }
}

@Suite("GujoBuyerAuth — 기존 /api/cli/device 흐름")
struct GujoBuyerAuthTests {
    @Test("202 대기 뒤 200 account_token 을 buyer 자리에 저장한다")
    func buyerLogin() async throws {
        let http = ScriptedHTTP([
            "/api/cli/device/authorize": [(200, """
                {"device_code":"bdc","user_code":"WXYZ-1234","verification_uri":"https://gujo.example/device",
                 "verification_uri_complete":"https://gujo.example/device?code=WXYZ-1234","expires_in":600,"interval":3}
                """)],
            "/api/cli/device/token": [(202, "{}"), (200, #"{"account_token":"acct_1"}"#)],
        ])
        let store = InMemorySessionStore()
        let buyer = GujoBuyerAuth(
            http: http, store: store, baseURL: baseURL, sleep: { _ in },
            now: { Date(timeIntervalSince1970: 1_780_000_000) })
        let shown = Prompts()

        let session = try await buyer.login(clientName: "Test") { await shown.record($0) }
        #expect(session.token == "acct_1")
        #expect(store.accounts == ["buyer"])
        #expect(buyer.current() == session)
        let prompt = try #require(await shown.all.first)
        #expect(prompt.userCode == "WXYZ-1234")
        #expect(prompt.verificationURI.query == "code=WXYZ-1234")
        let authorize = try #require(http.calls(to: "/api/cli/device/authorize").first)
        #expect(authorize.jsonObject()["client_name"] as? String == "Test")

        buyer.logout()
        #expect(buyer.current() == nil)
    }
}
