import Foundation
import Testing
import WikiLedgerKit

@testable import KnowledgeBaseWikiCore

// 세션 적재와 가림(T7) 시험. 가짜 R2(메모리)·주입 키 공급자·임시 세션·임시 상태 폴더만 쓴다.
// 근거: docs/architecture.md "agent-law (ledger 3)", docs/security.md "R2 와 세션", docs/contracts.md `archive`·`redact`.

/// 메모리 R2. 쓰기 순서를 남기고, 지정한 키에 도달 실패를 낼 수 있다.
final class FakeLawObjectStore: LawObjectStore, @unchecked Sendable {
    private let lock = NSLock()
    private var objects: [String: Data] = [:]
    private var order: [String] = []
    private var unreachable: Set<String> = []
    private var unreachablePrefixes: [String] = []

    func seed(_ key: String, _ data: Data) { lock.withLock { objects[key] = data } }
    func failPuts(prefix: String) { lock.withLock { unreachablePrefixes.append(prefix) } }
    func heal() { lock.withLock { unreachablePrefixes.removeAll(); unreachable.removeAll() } }
    var keys: [String] { lock.withLock { objects.keys.sorted() } }
    var writes: [String] { lock.withLock { order } }
    func object(_ key: String) -> Data? { lock.withLock { objects[key] } }

    func putIfAbsent(key: String, data: Data, contentType: String) throws {
        try lock.withLock {
            if unreachablePrefixes.contains(where: { key.hasPrefix($0) }) {
                throw LawObjectStoreError.unreachable("가짜 끊김")
            }
            guard objects[key] == nil else { throw LawObjectStoreError.alreadyExists(key) }
            objects[key] = data
            order.append(key)
        }
    }

    func get(key: String) throws -> Data {
        try lock.withLock {
            guard let data = objects[key] else { throw LawObjectStoreError.notFound(key) }
            return data
        }
    }

    func exists(key: String) throws -> Bool { lock.withLock { objects[key] != nil } }
    func delete(key: String) throws { _ = lock.withLock { objects.removeValue(forKey: key) } }
    func list(prefix: String) throws -> [String] { lock.withLock { objects.keys.filter { $0.hasPrefix(prefix) }.sorted() } }
}

/// 임시 세션 자리.
final class FakeSessionSource: LawSessionSource, @unchecked Sendable {
    struct Session {
        var runtime: LawRuntime
        var id: String
        var startedAt: Date
        var utterances: [LawSessionUtterance]
    }

    private let lock = NSLock()
    private var sessions: [Session] = []

    func add(_ session: Session) { lock.withLock { sessions.append(session) } }

    func append(_ id: String, _ utterance: LawSessionUtterance) {
        lock.withLock {
            if let index = sessions.firstIndex(where: { $0.id == id }) { sessions[index].utterances.append(utterance) }
        }
    }

    func sessions(activeSince: Date) -> [LawSessionCandidate] {
        lock.withLock { sessions.map { LawSessionCandidate(runtime: $0.runtime, sessionID: $0.id, startedAt: $0.startedAt) } }
    }

    func utterances(of candidate: LawSessionCandidate) -> [LawSessionUtterance] {
        lock.withLock { sessions.first { $0.id == candidate.sessionID }?.utterances ?? [] }
    }
}

/// 손으로 움직이는 시계. `sleep` 은 시각을 앞당긴다.
final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private(set) var slept: TimeInterval = 0

    init(_ start: Date) { current = start }

    func advance(_ seconds: TimeInterval) { lock.withLock { current += seconds } }

    var clock: LawArchiveClock {
        LawArchiveClock(
            now: { [self] in lock.withLock { current } },
            sleep: { [self] seconds in lock.withLock { current += seconds; slept += seconds } })
    }
}

@Suite struct AgentLawArchiveTests {
    struct Fixture {
        let dir: URL
        let file: BoundLedgerFile
        let registry: LawSessionRegistry
        let stateDirectory: URL
        let store = FakeLawObjectStore()
        let source = FakeSessionSource()
        let clock: ManualClock

        func runner(store: (any LawObjectStore)? = nil) -> LawArchiveRunner {
            LawArchiveRunner(
                device: "mac", file: file, source: source, registry: registry, stateDirectory: stateDirectory,
                store: store ?? self.store, clock: clock.clock)
        }

        func target(_ name: String) -> LawLedgerTarget { LawLedgerTarget(worldName: name, file: file) }

        func cleanup() { try? FileManager.default.removeItem(at: dir) }
    }

    /// 2026-10-04 00:00:00 UTC = 2026-10-04 09:00:00 KST.
    static let start = Date(timeIntervalSince1970: 1_791_072_000)

    static func fixture() throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-law-archive-\(UUID().uuidString)", isDirectory: true)
        func path(_ name: String) -> String { dir.appendingPathComponent(name).path }
        let file = BoundLedgerFile(
            worlds: [
                BoundWorld(name: "agent-law", rootPath: path("law"), key: "law"),
                BoundWorld(name: "agent-law-person-a", rootPath: path("person-a"), layer: "tenant",
                           parent: "agent-law", key: "person-a"),
                BoundWorld(name: "agent-law-tenant-b", rootPath: path("tenant-b"), layer: "tenant",
                           parent: "agent-law", key: "tenant-b"),
            ],
            currentWorld: "agent-law",
            tenantMap: ["personal": "agent-law-person-a", "gujo": "agent-law-tenant-b"],
            devices: ["mac"], currentDevice: "mac")
        return Fixture(
            dir: dir, file: file, registry: LawSessionRegistry(directory: dir.appendingPathComponent("sessions")),
            stateDirectory: dir.appendingPathComponent("archive-state"), clock: ManualClock(start))
    }

    static func say(_ role: String, _ text: String) -> LawSessionUtterance { LawSessionUtterance(role: role, text: text) }

    /// 처음 실행(켠 시각 기록) 뒤 1초 지나 시작한 세션을 둔다.
    static func enable(_ fx: Fixture) throws {
        let first = try fx.runner().run(dryRun: false)
        #expect(first.firstRun)
        #expect(first.chunks.isEmpty)
        fx.clock.advance(1)
    }

    // MARK: - 늘어난 부분만

    @Test func secondRunUploadsOnlyNewUtterances() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.enable(fx)
        fx.source.add(.init(runtime: .claudeCode, id: "s-1", startedAt: Self.start + 1, utterances: [
            Self.say("user", "안녕"), Self.say("assistant", "네"),
        ]))
        let first = try fx.runner().run(dryRun: false)
        #expect(first.chunks.count == 1)
        #expect(first.chunks[0].from == 0 && first.chunks[0].to == 2)

        fx.source.append("s-1", Self.say("user", "다음 질문"))
        fx.clock.advance(60)
        let second = try fx.runner().run(dryRun: false)
        #expect(second.chunks.count == 1)
        #expect(second.chunks[0].from == 2 && second.chunks[0].to == 3)
        let lines = try LawSessionChunks.read(store: fx.store, key: second.chunks[0].key)
        #expect(lines == [LawArchivedUtterance(index: 2, role: "user", text: "다음 질문")])

        // 조각을 시각 순서로 이으면 세션 전체.
        let refs = try LawSessionChunks.chunks(store: fx.store, ledgerKey: "person-a")
        let joined = try refs.flatMap { try LawSessionChunks.read(store: fx.store, key: $0.chunk.key) }
        #expect(joined.map(\.text) == ["안녕", "네", "다음 질문"])

        // 세 번째 실행: 늘어난 발화 없음 → 조각 없음.
        fx.clock.advance(60)
        #expect(try fx.runner().run(dryRun: false).chunks.isEmpty)
    }

    // MARK: - 가림

    @Test func secretsAndPersonalDataAreMaskedButUtterancesKept() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.enable(fx)
        let samples = [
            "키는 AKIAABCDEFGHIJKLMNOP 이고 토큰은 ghp_abcdefghijklmnopqrstuvwxyz0123",
            "export API_TOKEN=supersecretvalue123",
            "{\"password\": \"hunter2\"}",
            "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk\n-----END OPENSSH PRIVATE KEY-----",
            "전화 010-1234-5678 로 연락, 메일은 someone@example.com",
            "주민번호 900101-1234567, 카드 4111 1111 1111 1111",
            "평범한 문장",
        ]
        fx.source.add(.init(runtime: .codex, id: "s-2", startedAt: Self.start + 2,
                            utterances: samples.map { Self.say("user", $0) }))
        let outcome = try fx.runner().run(dryRun: false)
        let lines = try LawSessionChunks.read(store: fx.store, key: outcome.chunks[0].key)
        #expect(lines.count == samples.count)
        let text = lines.map(\.text).joined(separator: "\n")
        for secret in ["AKIAABCDEFGHIJKLMNOP", "ghp_abcdefghijklmnopqrstuvwxyz0123", "supersecretvalue123", "hunter2",
                       "b3BlbnNzaC1rZXk", "010-1234-5678", "someone@example.com", "900101-1234567", "4111 1111 1111 1111"] {
            #expect(!text.contains(secret), "남은 비밀: \(secret)")
        }
        #expect(text.contains("***"))
        #expect(lines.last?.text == "평범한 문장")
        // 같은 입력은 같은 출력(증언 대조가 기대는 성질).
        #expect(LawRedaction.redact(samples[4]) == LawRedaction.redact(samples[4]))
        // Luhn 이 안 맞는 16자리 숫자는 카드번호로 보지 않는다.
        #expect(LawRedaction.redact("주문 1234 5678 1234 5678") == "주문 1234 5678 1234 5678")
    }

    // MARK: - 조건부 쓰기 실패·요약

    @Test func conflictingObjectFailsRunWithoutManifestOrPositionAdvance() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.enable(fx)
        fx.source.add(.init(runtime: .grok, id: "s-3", startedAt: Self.start + 1, utterances: [Self.say("user", "a")]))
        let run = LawArchiveKeys.runVersion(fx.clock.clock.now())
        let chunkKey = LawArchiveKeys.chunk(ledgerKey: "person-a", device: "mac", runtime: "grok", sessionID: "s-3", run: run)
        fx.store.seed(chunkKey, Data("다른 내용".utf8))
        #expect(throws: LawArchiveError.conflict(chunkKey)) { try fx.runner().run(dryRun: false) }
        #expect(fx.store.keys.filter { $0.contains("/runs/archive/") && $0.contains(run) }.isEmpty)
        let state = LawArchiveStateStore(directory: fx.stateDirectory, device: "mac").load()
        #expect(state?.sessions["grok/s-3"] == nil)
    }

    @Test func identicalRetryIsIdempotentAndManifestIsLast() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.enable(fx)
        fx.source.add(.init(runtime: .claudeCode, id: "s-4", startedAt: Self.start + 1, utterances: [Self.say("user", "x")]))
        fx.source.add(.init(runtime: .codex, id: "s-5", startedAt: Self.start + 1, utterances: [Self.say("user", "y")]))
        let before = fx.store.writes.count
        let outcome = try fx.runner().run(dryRun: false)
        let writes = Array(fx.store.writes.dropFirst(before))
        #expect(writes.count == 3)
        #expect(writes.last?.hasSuffix("/manifest.json") == true)
        #expect(writes.dropLast().allSatisfy { $0.hasSuffix(".jsonl.gz") })
        let manifest = try JSONDecoder().decode(
            LawArchiveManifest.self, from: fx.store.get(key: outcome.manifests[0]))
        #expect(manifest.chunks.count == 2)
        #expect(manifest.chunks.allSatisfy { $0.sha256 == LawHash.sha256Hex(fx.store.object($0.key)!) })
        // 같은 바이트 재쓰기는 멱등 성공.
        let chunk = outcome.chunks[0]
        #expect(try fx.store.putImmutable(key: chunk.key, data: fx.store.get(key: chunk.key)) == .identical)
    }

    @Test func networkFailureKeepsPositionAndResumesNextRun() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.enable(fx)
        fx.source.add(.init(runtime: .claudeCode, id: "s-6", startedAt: Self.start + 1, utterances: [Self.say("user", "1")]))
        fx.source.add(.init(runtime: .codex, id: "s-7", startedAt: Self.start + 1, utterances: [Self.say("user", "2")]))
        fx.store.failPuts(prefix: "person-a/sessions/mac/codex/")
        let first = try fx.runner().run(dryRun: false)
        #expect(first.chunks.map(\.session) == ["s-6"])
        #expect(first.failures.count == 1)
        #expect(first.manifests.count == 1)
        let state = LawArchiveStateStore(directory: fx.stateDirectory, device: "mac").load()
        #expect(state?.sessions["claude-code/s-6"]?.uploaded == 1)
        #expect(state?.sessions["codex/s-7"] == nil)

        fx.store.heal()
        fx.clock.advance(5)
        let second = try fx.runner().run(dryRun: false)
        #expect(second.chunks.map(\.session) == ["s-7"])
        #expect(second.chunks[0].from == 0)
    }

    // MARK: - 키 형식

    @Test func keysUseKSTAndWaitForNextSecond() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        #expect(LawArchiveKeys.runVersion(Self.start) == "v261004090000")
        let first = try fx.runner().run(dryRun: false)
        #expect(first.run == "v261004090000")
        // 같은 초에 두 번째 실행 → 다음 초까지 기다린다.
        fx.clock.advance(0.2)
        let second = try fx.runner().run(dryRun: false)
        #expect(second.run == "v261004090001")
        #expect(fx.clock.slept > 0)
        #expect(second.manifests == ["person-a/runs/archive/mac/v261004090001/manifest.json"])
        fx.clock.advance(1)
        fx.source.add(.init(runtime: .antigravity, id: "s-8", startedAt: Self.start + 1, utterances: [Self.say("user", "z")]))
        let third = try fx.runner().run(dryRun: false)
        #expect(third.chunks[0].key == "person-a/sessions/mac/antigravity/s-8/\(third.run).jsonl.gz")
        #expect(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: String(repeating: "ab", count: 32))
            == "law/exhibits/ab/" + String(repeating: "ab", count: 32))
    }

    // MARK: - 테넌트

    @Test func tenantRoutingPersonalMappedAndUnassigned() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.enable(fx)
        fx.registry.register(LawSessionRegistration(sessionID: "t-gujo", tenant: "gujo"))
        fx.registry.register(LawSessionRegistration(sessionID: "t-acme", tenant: "acme"))
        for id in ["t-none", "t-gujo", "t-acme"] {
            fx.source.add(.init(runtime: .claudeCode, id: id, startedAt: Self.start + 1, utterances: [Self.say("user", id)]))
        }
        let outcome = try fx.runner().run(dryRun: false)
        let byID = Dictionary(uniqueKeysWithValues: outcome.chunks.map { ($0.session, $0) })
        #expect(byID["t-none"]?.ledgerKey == "person-a")
        #expect(byID["t-none"]?.tenant == "personal")
        #expect(byID["t-gujo"]?.ledgerKey == "tenant-b")
        #expect(byID["t-acme"]?.ledgerKey == "unassigned/acme")
        #expect(byID["t-acme"]?.key.hasPrefix("unassigned/acme/sessions/mac/") == true)
        #expect(outcome.unassigned == ["acme": 1])
        #expect(Set(outcome.manifests) == [
            "person-a/runs/archive/mac/\(outcome.run)/manifest.json",
            "tenant-b/runs/archive/mac/\(outcome.run)/manifest.json",
            "unassigned/acme/runs/archive/mac/\(outcome.run)/manifest.json",
        ])
        let manifest = try JSONDecoder().decode(LawArchiveManifest.self, from: fx.store.get(key: outcome.manifests[0]))
        #expect(manifest.unassigned == ["acme": 1])

        // 개인 대응이 없으면 무표시 세션은 unassigned/none.
        var file = fx.file
        file.tenantMap = ["gujo": "agent-law-tenant-b"]
        let runner = LawArchiveRunner(
            device: "mac", file: file, source: fx.source, registry: fx.registry, stateDirectory: fx.stateDirectory,
            store: fx.store, clock: fx.clock.clock)
        #expect(runner.route(tenant: nil).ledgerKey == "unassigned/none")
        #expect(runner.route(tenant: "  ").ledgerKey == "unassigned/none")
    }

    // MARK: - 켠 시각

    @Test func sessionsStartedBeforeEnablingAreExcluded() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        fx.source.add(.init(runtime: .claudeCode, id: "old", startedAt: Self.start - 3600, utterances: [Self.say("user", "옛")]))
        let first = try fx.runner().run(dryRun: false)
        #expect(first.firstRun)
        #expect(first.chunks.isEmpty)
        #expect(first.skippedBeforeEnabled == 1)
        fx.clock.advance(10)
        // 세션 등록의 시작 시각이 리더 값보다 먼저다.
        fx.registry.register(LawSessionRegistration(sessionID: "new", startedAt: "2026-10-04T00:00:05Z"))
        fx.source.add(.init(runtime: .claudeCode, id: "new", startedAt: Self.start - 3600, utterances: [Self.say("user", "새")]))
        let second = try fx.runner().run(dryRun: false)
        #expect(second.chunks.map(\.session) == ["new"])
        #expect(second.skippedBeforeEnabled == 1)
    }

    @Test func dryRunWritesNothing() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.enable(fx)
        fx.source.add(.init(runtime: .claudeCode, id: "d-1", startedAt: Self.start + 1, utterances: [Self.say("user", "d")]))
        let before = fx.store.keys
        let outcome = try fx.runner(store: nil).run(dryRun: true)
        #expect(outcome.dryRun)
        #expect(outcome.chunks.count == 1)
        #expect(fx.store.keys == before)
        #expect(LawArchiveStateStore(directory: fx.stateDirectory, device: "mac").load()?.sessions.isEmpty == true)
    }

    @Test func stateIsRebuiltFromManifests() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        try Self.enable(fx)
        fx.registry.register(LawSessionRegistration(sessionID: "r-2", tenant: "acme"))
        fx.source.add(.init(runtime: .claudeCode, id: "r-1", startedAt: Self.start + 1, utterances: [Self.say("user", "a")]))
        fx.source.add(.init(runtime: .claudeCode, id: "r-2", startedAt: Self.start + 1, utterances: [Self.say("user", "b")]))
        _ = try fx.runner().run(dryRun: false)
        let stateStore = LawArchiveStateStore(directory: fx.stateDirectory, device: "mac")
        let saved = try #require(stateStore.load())
        try FileManager.default.removeItem(at: stateStore.url)
        let rebuilt = try #require(try LawArchiveState.rebuild(store: fx.store, ledgerKeys: ["law", "person-a", "tenant-b"], device: "mac"))
        #expect(rebuilt.sessions == saved.sessions)
        #expect(rebuilt.enabledAt == saved.enabledAt)
        // 상태 없이 다음 실행 → 재구성 후 중복 없이 이어 올림.
        fx.source.append("r-1", Self.say("user", "c"))
        fx.clock.advance(5)
        let next = try fx.runner().run(dryRun: false)
        #expect(next.chunks.map(\.session) == ["r-1"])
        #expect(next.chunks[0].from == 1)
        #expect(!next.firstRun)
    }

    // MARK: - 키체인

    @Test func missingKeychainKeysFailFriendlyWithoutValues() throws {
        let missing = LawKeychainCredentialProvider { _, _ in nil }
        #expect(throws: LawR2CredentialError.missing(service: "agent-law-r2", account: "access-key-id")) {
            try missing.credentials()
        }
        let message = LawR2CredentialError.missing(service: "agent-law-r2", account: "access-key-id").description
        #expect(message.contains("agent-law-r2"))
        let partial = LawKeychainCredentialProvider { _, account in account == "access-key-id" ? "AKIDVALUE" : nil }
        do {
            _ = try partial.credentials()
            Issue.record("비밀 키가 없는데 성공함")
        } catch {
            #expect(!"\(error)".contains("AKIDVALUE"))
        }
        let present = LawKeychainCredentialProvider { _, account in account == "access-key-id" ? "AKID" : "SECRET" }
        let credentials = try present.credentials()
        #expect(credentials.accessKeyID == "AKID")
        #expect(!"\(credentials)".contains("SECRET") && !"\(credentials)".contains("AKID"))
        #expect(throws: LawR2CredentialError.self) {
            try LawR2Client.standard(file: BoundLedgerFile(), provider: missing)
        }
    }

    // MARK: - R2 요청

    final class RecordingTransport: LawHTTPTransport, @unchecked Sendable {
        let lock = NSLock()
        var requests: [URLRequest] = []
        var responses: [LawHTTPResponse]

        init(_ responses: [LawHTTPResponse]) { self.responses = responses }

        func send(_ request: URLRequest) throws -> LawHTTPResponse {
            try lock.withLock {
                requests.append(request)
                guard !responses.isEmpty else { throw LawObjectStoreError.unreachable("끝") }
                return responses.removeFirst()
            }
        }
    }

    @Test func r2ClientUsesConditionalPutDeleteAndPagination() throws {
        let credentials = LawR2Credentials(accessKeyID: "AKID", secretAccessKey: "SECRET")
        let settings = LawStorageSettings(endpoint: "https://r2.example.test")
        let transport = RecordingTransport([
            LawHTTPResponse(status: 200, body: Data()),
            LawHTTPResponse(status: 412, body: Data()),
            LawHTTPResponse(status: 404, body: Data()),
            LawHTTPResponse(status: 200, body: Data(
                "<ListBucketResult><IsTruncated>true</IsTruncated><Contents><Key>law/exhibits/ab/1</Key></Contents><NextContinuationToken>t2</NextContinuationToken></ListBucketResult>".utf8)),
            LawHTTPResponse(status: 200, body: Data(
                "<ListBucketResult><IsTruncated>false</IsTruncated><Contents><Key>law/exhibits/ab/2</Key></Contents></ListBucketResult>".utf8)),
        ])
        let client = LawR2Client(settings: settings, credentials: credentials, transport: transport, now: { Self.start })
        try client.putIfAbsent(key: "law/sessions/mac/codex/s 1/v1.jsonl.gz", data: Data("a".utf8), contentType: "application/gzip")
        #expect(throws: LawObjectStoreError.alreadyExists("law/x")) {
            try client.putIfAbsent(key: "law/x", data: Data("a".utf8), contentType: "application/gzip")
        }
        try client.delete(key: "law/exhibits/ab/gone")
        #expect(try client.list(prefix: "law/exhibits/") == ["law/exhibits/ab/1", "law/exhibits/ab/2"])

        let put = transport.requests[0]
        #expect(put.httpMethod == "PUT")
        #expect(put.value(forHTTPHeaderField: "If-None-Match") == "*")
        #expect(put.url?.absoluteString == "https://r2.example.test/agent-law/law/sessions/mac/codex/s%201/v1.jsonl.gz")
        #expect(put.value(forHTTPHeaderField: "Authorization")?.hasPrefix("AWS4-HMAC-SHA256 Credential=AKID/20261004/auto/s3/") == true)
        #expect(put.value(forHTTPHeaderField: "Authorization")?.contains("SECRET") == false)
        #expect(transport.requests[2].httpMethod == "DELETE")
        #expect(transport.requests[4].url?.query(percentEncoded: true)?.contains("continuation-token=t2") == true)
        #expect(transport.requests[3].url?.query(percentEncoded: true)?.contains("prefix=law%2Fexhibits%2F") == true)
    }

    @Test func gzipRoundTripsAndIsDeterministic() throws {
        let text = Data(String(repeating: "발화 한 줄\n", count: 200).utf8)
        let gz = try LawGzip.compress(text)
        #expect(gz.prefix(2) == Data([0x1F, 0x8B]))
        #expect(try LawGzip.decompress(gz) == text)
        #expect(try LawGzip.compress(text) == gz)
        var broken = gz
        broken[broken.count - 5] ^= 0xFF
        #expect(throws: LawGzipError.self) { try LawGzip.decompress(broken) }
    }

    // MARK: - 가림

    static let human = LawActor(author: "user:tester", kind: .human, device: "mac")

    @Test func redactDeletesRemoteAndLocalAndRecords() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let sha = try law.store.putExhibit(Data("비밀이 섞인 원자료".utf8))
        let key = LawArchiveKeys.exhibit(ledgerKey: "law", sha256: sha)
        fx.store.seed(key, Data("비밀이 섞인 원자료".utf8))
        // 증거물을 인용한 기록.
        _ = try LawEnactService.enact(
            LawDraft(actor: Self.human, title: "증거 인용", exhibits: [sha], body: "본문"), target: law)

        let outcome = try LawRedactService.redact(sha, reason: "비밀 포함", actor: Self.human, target: law, objectStore: fx.store)
        #expect(outcome.deletedRemote && outcome.deletedLocal && !outcome.alreadyRecorded)
        #expect(fx.store.object(key) == nil)
        #expect(!FileManager.default.fileExists(atPath: law.store.exhibitURL(sha256: sha).path))
        let record = try #require(law.store.scan().first { $0.id == outcome.recordID })
        #expect(record.record.type == "redaction")
        #expect(record.record.exhibits == [sha])
        let head = try LawHeadFields.parse(body: record.record.body, type: "redaction")
        #expect(head["target"] == key)
        #expect(head["reason"] == "비밀 포함")
        #expect(!record.record.body.contains("비밀이 섞인 원자료"))

        // 감사: 가림 기록이 있는 증거물의 부재는 "가림"(위반 아님).
        let report = law.store.audit(context: LawEnactService.context(index: LawEnactService.scope(of: law)))
        #expect(report.passed, "\(report.violations)")
        #expect(report.redactedExhibits.map(\.sha256) == [sha])

        // 다시 실행해도 기록을 또 공포하지 않는다.
        let again = try LawRedactService.redact(sha, reason: "비밀 포함", actor: Self.human, target: law, objectStore: fx.store)
        #expect(again.alreadyRecorded && again.recordID == outcome.recordID)
    }

    @Test func redactSessionChunkByKeyAndRefuseLedgerRecords() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let chunkKey = "law/sessions/mac/codex/s-9/v261004090000.jsonl.gz"
        fx.store.seed(chunkKey, Data("x".utf8))
        let outcome = try LawRedactService.redact(chunkKey, reason: "개인정보", actor: Self.human, target: law, objectStore: fx.store)
        #expect(fx.store.object(chunkKey) == nil)
        #expect(outcome.target == chunkKey)

        let record = try LawEnactService.enact(LawDraft(actor: Self.human, title: "기록", body: "본문"), target: law)
        #expect(throws: LawRedactError.ledgerRecord(record.id)) {
            try LawRedactService.redact(record.id, reason: "r", actor: Self.human, target: law, objectStore: fx.store)
        }
        #expect(throws: LawRedactError.notEvidence("law/runs/archive/mac/v1/manifest.json")) {
            try LawRedactService.redact("law/runs/archive/mac/v1/manifest.json", reason: "r", actor: Self.human, target: law, objectStore: fx.store)
        }
        #expect(throws: LawRedactError.otherLedger("tenant-b/sessions/mac/codex/s/v1.jsonl.gz")) {
            try LawRedactService.redact("tenant-b/sessions/mac/codex/s/v1.jsonl.gz", reason: "r", actor: Self.human, target: law, objectStore: fx.store)
        }
        #expect(throws: LawRedactError.emptyReason) {
            try LawRedactService.redact(chunkKey, reason: " ", actor: Self.human, target: law, objectStore: fx.store)
        }
        let missing = String(repeating: "c", count: 64)
        #expect(throws: LawRedactError.notFound(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: missing))) {
            try LawRedactService.redact(missing, reason: "r", actor: Self.human, target: law, objectStore: fx.store)
        }
    }

    // MARK: - 동기화

    @Test func syncSweepDeletesLocalCopiesNamedByRedactionRecords() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let data = Data("다른 기기에 남은 사본".utf8)
        let sha = try law.store.putExhibit(data)
        let sessionCopy = law.root.appendingPathComponent("sessions/mac/codex/s-1/v1.jsonl.gz")
        try FileManager.default.createDirectory(at: sessionCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("s".utf8).write(to: sessionCopy)
        // 다른 기기가 공포한 가림 기록이 동기화로 들어온 상황.
        _ = try LawEnactService.enact(LawDraft(
            actor: Self.human, title: "가림", type: "redaction", exhibits: [sha],
            body: "target: \(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: sha))\nreason: r\n"), target: law)
        _ = try LawEnactService.enact(LawDraft(
            actor: Self.human, title: "가림", type: "redaction",
            body: "target: law/sessions/mac/codex/s-1/v1.jsonl.gz\nreason: r\n"), target: law)
        let deleted = LawRedactionSweep.applyLocalDeletions(store: law.store, ledgerKey: "law")
        #expect(Set(deleted) == ["exhibits/\(sha.prefix(2))/\(sha)", "sessions/mac/codex/s-1/v1.jsonl.gz"])
        #expect(!FileManager.default.fileExists(atPath: law.store.exhibitURL(sha256: sha).path))
        #expect(!FileManager.default.fileExists(atPath: sessionCopy.path))
        // 가린 증거물은 R2 에서 다시 받지 않는다.
        fx.store.seed(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: sha), data)
        let sync = LawExhibitSync.sync(store: law.store, ledgerKey: "law", objectStore: fx.store)
        #expect(sync.downloaded.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: law.store.exhibitURL(sha256: sha).path))
    }

    @Test func exhibitSyncTransfersDifferenceAndVerifiesSHA() throws {
        let fx = try Self.fixture()
        defer { fx.cleanup() }
        let law = fx.target("agent-law")
        let localOnly = try law.store.putExhibit(Data("로컬에만".utf8))
        let remoteData = Data("원격에만".utf8)
        let remoteOnly = LawHash.sha256Hex(remoteData)
        fx.store.seed(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: remoteOnly), remoteData)
        let forged = String(repeating: "d", count: 64)
        fx.store.seed(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: forged), Data("위조".utf8))

        let outcome = LawExhibitSync.sync(store: law.store, ledgerKey: "law", objectStore: fx.store)
        #expect(outcome.uploaded == [localOnly])
        #expect(outcome.downloaded == [remoteOnly])
        #expect(outcome.rejected == [forged])
        #expect(!outcome.ok)
        #expect(fx.store.object(LawArchiveKeys.exhibit(ledgerKey: "law", sha256: localOnly)) == Data("로컬에만".utf8))
        #expect(try law.store.exhibit(sha256: remoteOnly) == remoteData)
        #expect((try? law.store.exhibit(sha256: forged)) == nil)
        #expect(Set(LawExhibitSync.localExhibits(law.store)) == [localOnly, remoteOnly])
    }
}
