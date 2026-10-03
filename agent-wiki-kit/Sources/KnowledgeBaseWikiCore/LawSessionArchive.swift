import AgentSessionStorageKit
import Foundation
import StateRootKit
import WikiLedgerKit

// 세션 적재(`archive`) — 네 실행 도구 세션의 늘어난 발화만 가려서 R2 에 조각으로 올린다.
// 근거: docs/architecture.md "agent-law (ledger 3)"(R2 키 표·적재 흐름), docs/security.md "R2 와 세션",
// docs/business-rules.md "원장 구성"(테넌트 대응), docs/contracts.md `archive [--dry-run]`, 결정 0007.
//
// - 대상: Claude Code·Codex·Grok·Antigravity 세션(공용 리더 `AgentSessionStorageKit` 로만 찾는다, 홈 전역 검색 없음).
// - 적재를 처음 켠 시각 이후에 시작한 세션만(소급 없음). 켠 시각은 처음 실행 때 기록한다.
// - 실행마다 세션별로 지난 적재 뒤 늘어난 발화만 새 조각으로 올린다. 조각을 시각 순서로 이으면 세션 전체.
// - 모든 조각을 올린 뒤 맨 마지막에 실행 요약(manifest)을 쓴다. 요약 없는 실행은 실패한 실행이다.
// - 세션별로 어디까지 올렸는지는 기기마다 로컬 상태에 두고, 요약에서 다시 만들 수 있다.

// MARK: - 발화·세션

/// 세션의 발화 하나(가리기 전).
public struct LawSessionUtterance: Codable, Sendable, Equatable {
    /// `user` · `assistant`.
    public var role: String
    public var text: String

    public init(role: String, text: String) {
        self.role = role
        self.text = text
    }
}

/// 세션 조각의 한 줄(가린 뒤). `index` 는 세션 안의 발화 번호(0부터).
public struct LawArchivedUtterance: Codable, Sendable, Equatable {
    public var index: Int
    public var role: String
    public var text: String

    public init(index: Int, role: String, text: String) {
        self.index = index
        self.role = role
        self.text = text
    }
}

/// 적재 후보 세션.
public struct LawSessionCandidate: Sendable, Equatable {
    public let runtime: LawRuntime
    public let sessionID: String
    /// 세션 시작 시각(리더가 아는 경우). 세션 등록의 시작 시각이 있으면 그것이 먼저다.
    public let startedAt: Date?
    /// 실제 리더가 다시 읽을 때 쓰는 참조. 시험 가짜는 비운다.
    public let ref: SessionRef?

    public init(runtime: LawRuntime, sessionID: String, startedAt: Date?, ref: SessionRef? = nil) {
        self.runtime = runtime
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.ref = ref
    }
}

/// 세션을 찾고 읽는 자리. 실제는 `LawAgentSessionSource`, 시험은 임시 세션을 주입한다.
public protocol LawSessionSource: Sendable {
    /// `activeSince` 뒤에 움직인 세션.
    func sessions(activeSince: Date) -> [LawSessionCandidate]
    /// 세션 전체 발화(읽은 순서).
    func utterances(of candidate: LawSessionCandidate) -> [LawSessionUtterance]
}

/// 공용 세션 리더 위의 얇은 자리. 네 실행 도구만 본다.
public struct LawAgentSessionSource: LawSessionSource {
    let claude: ClaudeSessionReader
    let codex: CodexSessionReader
    let grok: GrokSessionReader
    let agy: AntigravitySessionReader
    let limitPerTool: Int

    public init(
        claude: ClaudeSessionReader = .init(), codex: CodexSessionReader = .init(),
        grok: GrokSessionReader = .init(), agy: AntigravitySessionReader = .init(), limitPerTool: Int = 100_000
    ) {
        self.claude = claude
        self.codex = codex
        self.grok = grok
        self.agy = agy
        self.limitPerTool = limitPerTool
    }

    public func sessions(activeSince: Date) -> [LawSessionCandidate] {
        let refs = claude.discover(limit: limitPerTool, since: activeSince)
            + codex.discover(limit: limitPerTool, since: activeSince)
            + grok.discover(limit: limitPerTool, since: activeSince)
            + agy.discover(limit: limitPerTool, since: activeSince)
        return refs.compactMap { ref in
            guard let runtime = LawRuntime(cli: ref.tool) else { return nil }
            let created = (try? FileManager.default.attributesOfItem(atPath: ref.path))?[.creationDate] as? Date
            return LawSessionCandidate(runtime: runtime, sessionID: ref.id, startedAt: created, ref: ref)
        }
    }

    public func utterances(of candidate: LawSessionCandidate) -> [LawSessionUtterance] {
        guard let ref = candidate.ref else { return [] }
        let index = SessionIndex(grok: grok, claude: claude, codex: codex, agy: agy)
        return index.digest(ref, window: .full, recoverIfEmpty: false).turns.map {
            LawSessionUtterance(role: $0.speaker == .user ? "user" : "assistant", text: $0.text)
        }
    }
}

// MARK: - 주소

public enum LawArchiveKeys {
    public static let unassignedPrefix = "unassigned"

    /// 실행 시작 한국 시간 `v<yymmddhhmmss>`.
    public static func runVersion(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.dateFormat = "yyMMddHHmmss"
        return "v" + formatter.string(from: date)
    }

    /// 사람이 읽는 한국 시간(`…+09:00`).
    public static func kstTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// `<원장 키>/sessions/<기기 키>/<runtime>/<세션 id>/v<yymmddhhmmss>.jsonl.gz`
    public static func chunk(ledgerKey: String, device: String, runtime: String, sessionID: String, run: String) -> String {
        "\(ledgerKey)/sessions/\(device)/\(runtime)/\(sessionID)/\(run).jsonl.gz"
    }

    /// `<원장 키>/runs/archive/<기기 키>/v<yymmddhhmmss>/manifest.json`
    public static func manifest(ledgerKey: String, device: String, run: String) -> String {
        "\(ledgerKey)/runs/archive/\(device)/\(run)/manifest.json"
    }

    public static func manifestPrefix(ledgerKey: String, device: String? = nil) -> String {
        device.map { "\(ledgerKey)/runs/archive/\($0)/" } ?? "\(ledgerKey)/runs/archive/"
    }

    /// `<원장 키>/exhibits/<sha256 앞 2자>/<sha256>`
    public static func exhibit(ledgerKey: String, sha256: String) -> String {
        "\(ledgerKey)/exhibits/\(sha256.prefix(2))/\(sha256)"
    }

    /// 테넌트 미상의 원장 키 자리 `unassigned/<테넌트 표시 또는 none>`. 주소에 못 쓰는 글자는 `-` 로 바꾼다.
    public static func unassigned(tenant: String?) -> String {
        "\(unassignedPrefix)/\(unassignedLabel(tenant))"
    }

    public static func unassignedLabel(_ tenant: String?) -> String {
        let trimmed = tenant?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return "none" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let cleaned = String(trimmed.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        return cleaned.allSatisfy({ $0 == "." || $0 == "-" }) ? "none" : cleaned
    }
}

// MARK: - 실행 요약

public struct LawArchiveFailure: Codable, Sendable, Equatable {
    public var target: String
    public var reason: String

    public init(target: String, reason: String) {
        self.target = target
        self.reason = reason
    }
}

/// 적재 실행 요약. 원장 키마다 하나, 모든 조각을 올린 뒤 쓴다.
public struct LawArchiveManifest: Codable, Sendable, Equatable {
    public struct Chunk: Codable, Sendable, Equatable {
        public var key: String
        public var runtime: String
        public var session: String
        /// 판정한 테넌트(무표시는 `personal`).
        public var tenant: String
        /// 이 조각의 첫 발화 번호와 끝(미포함). 다음 조각은 `to` 에서 시작한다.
        public var from: Int
        public var to: Int
        /// 압축된 조각 바이트의 sha256.
        public var sha256: String
        public var bytes: Int
    }

    public var kind: String
    public var ledgerKey: String
    public var device: String
    public var run: String
    public var startedAt: String
    public var finishedAt: String
    /// 이 기기에서 적재를 처음 켠 시각(ms UTC).
    public var enabledAt: String
    public var chunks: [Chunk]
    /// 이 실행 전체에서 테넌트 미상으로 올린 조각 수(테넌트 표시 → 수).
    public var unassigned: [String: Int]
    public var failures: [LawArchiveFailure]
}

// MARK: - 기기별 상태

public struct LawArchivePosition: Codable, Sendable, Equatable {
    public var ledgerKey: String
    /// 올린 발화 수(다음 조각의 시작 번호).
    public var uploaded: Int
    public var lastRun: String

    public init(ledgerKey: String, uploaded: Int, lastRun: String) {
        self.ledgerKey = ledgerKey
        self.uploaded = uploaded
        self.lastRun = lastRun
    }
}

/// 이 기기의 적재 상태. R2 실행 요약에서 다시 만들 수 있다(`rebuild`).
public struct LawArchiveState: Codable, Sendable, Equatable {
    /// 적재를 처음 켠 시각(ms UTC, `LawTime`).
    public var enabledAt: String
    /// 마지막으로 연 실행 폴더(같은 초 대기 판정).
    public var lastRun: String?
    /// `<runtime>/<세션 id>` → 올린 위치.
    public var sessions: [String: LawArchivePosition]

    public init(enabledAt: Date, lastRun: String? = nil, sessions: [String: LawArchivePosition] = [:]) {
        self.enabledAt = LawTime.format(enabledAt)
        self.lastRun = lastRun
        self.sessions = sessions
    }

    public var enabledDate: Date { LawTime.parse(enabledAt) ?? Date.distantFuture }

    public static func sessionKey(runtime: String, sessionID: String) -> String { "\(runtime)/\(sessionID)" }

    /// R2 의 완료된 실행 요약(이 기기)으로 상태를 다시 만든다. 요약이 하나도 없으면 nil.
    public static func rebuild(store: any LawObjectStore, ledgerKeys: [String], device: String) throws -> LawArchiveState? {
        var manifests: [LawArchiveManifest] = []
        for ledgerKey in Set(ledgerKeys).sorted() {
            manifests += try LawSessionChunks.manifests(store: store, ledgerKey: ledgerKey, device: device)
        }
        manifests += try LawSessionChunks.unassignedManifests(store: store, device: device)
        guard !manifests.isEmpty else { return nil }
        let ordered = manifests.sorted { $0.run < $1.run }
        let enabled = ordered.compactMap { LawTime.parse($0.enabledAt) }.min() ?? Date()
        var state = LawArchiveState(enabledAt: enabled, lastRun: ordered.last?.run)
        for manifest in ordered {
            for chunk in manifest.chunks {
                let key = sessionKey(runtime: chunk.runtime, sessionID: chunk.session)
                if let present = state.sessions[key], present.uploaded >= chunk.to { continue }
                state.sessions[key] = LawArchivePosition(ledgerKey: manifest.ledgerKey, uploaded: chunk.to, lastRun: manifest.run)
            }
        }
        return state
    }
}

/// 상태 파일 `<상태 폴더>/<기기 키>.json`. 기본 폴더는 상태 루트 `~/.agent-wiki/archive`.
public struct LawArchiveStateStore: Sendable {
    public let directory: URL
    public let device: String

    public init(directory: URL, device: String) {
        self.directory = directory
        self.device = device
    }

    public static var standardDirectory: URL { StateRootKit.url(".agent-wiki/archive") }

    public var url: URL { directory.appendingPathComponent("\(device).json") }

    public func load() -> LawArchiveState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LawArchiveState.self, from: data)
    }

    public func save(_ state: LawArchiveState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(state).write(to: url, options: .atomic)
    }
}

// MARK: - 조각 읽기(소환이 쓴다)

/// 요약에 실린 조각 하나와 그 실행.
public struct LawArchiveChunkRef: Sendable, Equatable {
    public let ledgerKey: String
    public let device: String
    public let run: String
    public let chunk: LawArchiveManifest.Chunk
}

public enum LawSessionChunks {
    /// 조각 바이트(gzip JSON Lines) 만들기.
    public static func encode(_ lines: [LawArchivedUtterance]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var text = Data()
        for line in lines {
            text.append(try encoder.encode(line))
            text.append(0x0A)
        }
        return try LawGzip.compress(text)
    }

    /// 조각 바이트 → 발화들.
    public static func decode(_ gz: Data) throws -> [LawArchivedUtterance] {
        let text = try LawGzip.decompress(gz)
        let decoder = JSONDecoder()
        return try text.split(separator: 0x0A).map { try decoder.decode(LawArchivedUtterance.self, from: Data($0)) }
    }

    /// R2 의 조각 하나를 읽는다. 가린 조각이면 `LawObjectStoreError.notFound`.
    public static func read(store: any LawObjectStore, key: String) throws -> [LawArchivedUtterance] {
        try decode(store.get(key: key))
    }

    /// 원장 키의 완료된 적재 실행 요약들(실행 순). `device` 가 nil 이면 모든 기기.
    public static func manifests(store: any LawObjectStore, ledgerKey: String, device: String? = nil) throws
        -> [LawArchiveManifest]
    {
        let keys = try store.list(prefix: LawArchiveKeys.manifestPrefix(ledgerKey: ledgerKey, device: device))
            .filter { $0.hasSuffix("/manifest.json") }
        return try keys.map { try JSONDecoder().decode(LawArchiveManifest.self, from: store.get(key: $0)) }
            .sorted { $0.run < $1.run }
    }

    /// `unassigned/` 아래의 이 기기 요약들.
    static func unassignedManifests(store: any LawObjectStore, device: String) throws -> [LawArchiveManifest] {
        let keys = try store.list(prefix: LawArchiveKeys.unassignedPrefix + "/")
            .filter { $0.contains("/runs/archive/\(device)/") && $0.hasSuffix("/manifest.json") }
        return try keys.map { try JSONDecoder().decode(LawArchiveManifest.self, from: store.get(key: $0)) }
    }

    /// 완료된 실행에 실린 조각들(세션별 시각 순). 요약 없는 실행의 조각은 빠진다.
    public static func chunks(store: any LawObjectStore, ledgerKey: String, device: String? = nil) throws
        -> [LawArchiveChunkRef]
    {
        try manifests(store: store, ledgerKey: ledgerKey, device: device).flatMap { manifest in
            manifest.chunks.map { LawArchiveChunkRef(ledgerKey: manifest.ledgerKey, device: manifest.device, run: manifest.run, chunk: $0) }
        }
        .sorted { ($0.device, $0.chunk.runtime, $0.chunk.session, $0.chunk.from) < ($1.device, $1.chunk.runtime, $1.chunk.session, $1.chunk.from) }
    }
}

// MARK: - 적재 실행

/// 시계(시험 주입). `sleep` 은 다음 초까지 기다릴 때 쓴다.
public struct LawArchiveClock: Sendable {
    public var now: @Sendable () -> Date
    public var sleep: @Sendable (TimeInterval) -> Void

    public init(now: @escaping @Sendable () -> Date, sleep: @escaping @Sendable (TimeInterval) -> Void) {
        self.now = now
        self.sleep = sleep
    }

    public static let system = LawArchiveClock(now: { Date() }, sleep: { Thread.sleep(forTimeInterval: $0) })
}

public enum LawArchiveError: Error, Equatable, Sendable, CustomStringConvertible {
    case deviceMissing
    /// 같은 주소에 다른 내용 — 실행 실패, 요약을 쓰지 않는다.
    case conflict(String)
    case clockBehind(last: String, now: String)
    case store(String)
    case state(String)

    public var description: String {
        switch self {
        case .deviceMissing: return "이 기기의 기기 키가 없음 — 세션 적재 거부 (world device register <키>)"
        case .conflict(let key): return "같은 R2 주소에 다른 내용이 있음: \(key) — 실행 요약을 쓰지 않고 실패"
        case .clockBehind(let last, let now): return "시계가 마지막 실행(\(last))보다 앞섬: \(now)"
        case .store(let detail): return "R2: \(detail)"
        case .state(let detail): return "적재 상태: \(detail)"
        }
    }
}

/// 올릴(또는 올린) 조각 한 건.
public struct LawArchivePlanItem: Codable, Sendable, Equatable {
    public var key: String
    public var ledgerKey: String
    public var tenant: String
    public var unassigned: Bool
    public var runtime: String
    public var session: String
    public var from: Int
    public var to: Int
}

public struct LawArchiveOutcome: Codable, Sendable, Equatable {
    public var run: String
    public var dryRun: Bool
    /// 이번 실행에서 적재를 처음 켰다(켠 시각 기록).
    public var firstRun: Bool
    public var enabledAt: String
    public var chunks: [LawArchivePlanItem]
    /// 켠 시각 전에 시작해 뺀 세션 수.
    public var skippedBeforeEnabled: Int
    public var unassigned: [String: Int]
    public var manifests: [String]
    public var failures: [LawArchiveFailure]
    /// 전체 발화 수(이번에 올린).
    public var utterances: Int
}

/// 적재 실행 하나. 드리밍도 이 함수로 먼저 적재한다.
public struct LawArchiveRunner: Sendable {
    public let device: String
    public let file: BoundLedgerFile
    public let source: any LawSessionSource
    public let registry: LawSessionRegistry
    public let stateDirectory: URL
    /// dry-run 이면 nil 이어도 된다.
    public let store: (any LawObjectStore)?
    public let clock: LawArchiveClock

    public init(
        device: String, file: BoundLedgerFile, source: any LawSessionSource, registry: LawSessionRegistry,
        stateDirectory: URL, store: (any LawObjectStore)?, clock: LawArchiveClock = .system
    ) {
        self.device = device
        self.file = file
        self.source = source
        self.registry = registry
        self.stateDirectory = stateDirectory
        self.store = store
        self.clock = clock
    }

    var catalog: WorldBindingCatalog { WorldBindingCatalog(worlds: file.effectiveWorlds) }

    /// 원장 키가 있는 원장들(요약 재구성 범위).
    var ledgerKeys: [String] { catalog.worlds.compactMap(\.key) }

    struct Route: Equatable {
        let ledgerKey: String
        let tenant: String
        let unassigned: Bool
    }

    /// 세션 등록의 테넌트 → 원장 키. 무표시 → `personal`, 표에 없으면 `unassigned/<테넌트 또는 none>`.
    func route(tenant raw: String?) -> Route {
        let resolution = TenantLedgerRouting.resolve(tenant: raw, file: file)
        if let world = resolution.worldName, let key = catalog.world(named: world)?.key, LedgerKeyFormat.isValid(key) {
            return Route(ledgerKey: key, tenant: resolution.tenant, unassigned: false)
        }
        let label = LawArchiveKeys.unassignedLabel(raw)
        return Route(ledgerKey: LawArchiveKeys.unassigned(tenant: raw), tenant: label, unassigned: true)
    }

    static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let date = LawTime.parse(raw) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)
    }

    struct Pending {
        let item: LawArchivePlanItem
        let data: Data
    }

    public func run(dryRun: Bool) throws -> LawArchiveOutcome {
        guard LedgerKeyFormat.isValid(device) else { throw LawArchiveError.deviceMissing }
        let stateStore = LawArchiveStateStore(directory: stateDirectory, device: device)
        var firstRun = false
        var state: LawArchiveState
        if let loaded = stateStore.load() {
            state = loaded
        } else if !dryRun, let store, let rebuilt = try rebuild(store) {
            state = rebuilt
        } else {
            state = LawArchiveState(enabledAt: clock.now())
            firstRun = true
        }

        let started = try startTime(after: state.lastRun, wait: !dryRun)
        let run = LawArchiveKeys.runVersion(started)
        if !dryRun {
            state.lastRun = run
            try save(state, to: stateStore)
        }

        // 1. 늘어난 발화를 가려서 조각으로.
        let enabledAt = state.enabledDate
        var failures: [LawArchiveFailure] = []
        var skipped = 0
        var pending: [Pending] = []
        let candidates = source.sessions(activeSince: enabledAt)
            .sorted { ($0.runtime.rawValue, $0.sessionID) < ($1.runtime.rawValue, $1.sessionID) }
        for candidate in candidates {
            let runtime = candidate.runtime.rawValue
            guard LawSessionRegistry.isValidSessionID(candidate.sessionID) else {
                failures.append(LawArchiveFailure(target: "\(runtime)/\(candidate.sessionID)", reason: "주소에 쓸 수 없는 세션 id"))
                continue
            }
            let registration = registry.registration(sessionID: candidate.sessionID)
            guard let startedAt = Self.parseTimestamp(registration?.startedAt) ?? candidate.startedAt,
                  startedAt >= enabledAt
            else {
                skipped += 1
                continue
            }
            let sessionKey = LawArchiveState.sessionKey(runtime: runtime, sessionID: candidate.sessionID)
            let from = state.sessions[sessionKey]?.uploaded ?? 0
            let utterances = source.utterances(of: candidate)
            guard utterances.count >= from else {
                failures.append(LawArchiveFailure(
                    target: sessionKey, reason: "세션 발화 수가 줄어듦(올린 \(from) > 지금 \(utterances.count))"))
                continue
            }
            guard utterances.count > from else { continue }
            let lines = (from..<utterances.count).map { index in
                LawArchivedUtterance(
                    index: index, role: utterances[index].role, text: LawRedaction.redact(utterances[index].text))
            }
            let route = route(tenant: registration?.tenant)
            let key = LawArchiveKeys.chunk(
                ledgerKey: route.ledgerKey, device: device, runtime: runtime, sessionID: candidate.sessionID, run: run)
            let item = LawArchivePlanItem(
                key: key, ledgerKey: route.ledgerKey, tenant: route.tenant, unassigned: route.unassigned,
                runtime: runtime, session: candidate.sessionID, from: from, to: utterances.count)
            pending.append(Pending(item: item, data: try LawSessionChunks.encode(lines)))
        }

        func outcome(_ items: [LawArchivePlanItem], manifests: [String]) -> LawArchiveOutcome {
            LawArchiveOutcome(
                run: run, dryRun: dryRun, firstRun: firstRun, enabledAt: state.enabledAt, chunks: items,
                skippedBeforeEnabled: skipped, unassigned: Self.unassignedCounts(items), manifests: manifests,
                failures: failures, utterances: items.reduce(0) { $0 + $1.to - $1.from })
        }
        if dryRun { return outcome(pending.map(\.item), manifests: []) }
        guard let store else { throw LawArchiveError.store("R2 저장소 없음") }

        // 2. 조각을 조건부로 올린다. 끊긴 세션은 위치를 앞당기지 않고 다음 실행에서 이어 올린다.
        var uploaded: [Pending] = []
        for entry in pending {
            do {
                try store.putImmutable(key: entry.item.key, data: entry.data, contentType: "application/gzip")
                uploaded.append(entry)
            } catch LawObjectStoreError.conflict(let key) {
                throw LawArchiveError.conflict(key)
            } catch {
                failures.append(LawArchiveFailure(target: entry.item.key, reason: "\(error)"))
            }
        }

        // 3. 맨 마지막에 원장 키마다 실행 요약. 요약을 쓴 원장의 세션만 위치를 앞당긴다.
        var groups = Dictionary(grouping: uploaded, by: \.item.ledgerKey)
        if groups.isEmpty { groups[route(tenant: nil).ledgerKey] = [] }
        let unassignedCounts = Self.unassignedCounts(uploaded.map(\.item))
        let finishedAt = LawArchiveKeys.kstTimestamp(clock.now())
        var manifests: [String] = []
        var written: [LawArchivePlanItem] = []
        for ledgerKey in groups.keys.sorted() {
            let entries = groups[ledgerKey] ?? []
            let manifest = LawArchiveManifest(
                kind: "archive", ledgerKey: ledgerKey, device: device, run: run,
                startedAt: LawArchiveKeys.kstTimestamp(started), finishedAt: finishedAt, enabledAt: state.enabledAt,
                chunks: entries.map { entry in
                    LawArchiveManifest.Chunk(
                        key: entry.item.key, runtime: entry.item.runtime, session: entry.item.session,
                        tenant: entry.item.tenant, from: entry.item.from, to: entry.item.to,
                        sha256: LawHash.sha256Hex(entry.data), bytes: entry.data.count)
                },
                unassigned: unassignedCounts, failures: failures)
            let key = LawArchiveKeys.manifest(ledgerKey: ledgerKey, device: device, run: run)
            do {
                try store.putImmutable(key: key, data: try Self.encodeManifest(manifest), contentType: "application/json")
                manifests.append(key)
                written += entries.map(\.item)
            } catch LawObjectStoreError.conflict(let key) {
                throw LawArchiveError.conflict(key)
            } catch {
                failures.append(LawArchiveFailure(target: key, reason: "\(error)"))
            }
        }
        for item in written {
            state.sessions[LawArchiveState.sessionKey(runtime: item.runtime, sessionID: item.session)] =
                LawArchivePosition(ledgerKey: item.ledgerKey, uploaded: item.to, lastRun: run)
        }
        try save(state, to: stateStore)
        return outcome(written, manifests: manifests)
    }

    static func unassignedCounts(_ items: [LawArchivePlanItem]) -> [String: Int] {
        items.filter(\.unassigned).reduce(into: [:]) { $0[$1.tenant, default: 0] += 1 }
    }

    static func encodeManifest(_ manifest: LawArchiveManifest) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(manifest)
    }

    private func rebuild(_ store: any LawObjectStore) throws -> LawArchiveState? {
        do {
            return try LawArchiveState.rebuild(store: store, ledgerKeys: ledgerKeys, device: device)
        } catch {
            throw LawArchiveError.store("적재 상태 재구성 실패: \(error)")
        }
    }

    private func save(_ state: LawArchiveState, to stateStore: LawArchiveStateStore) throws {
        do {
            try stateStore.save(state)
        } catch {
            throw LawArchiveError.state("\(stateStore.url.path): \(error.localizedDescription)")
        }
    }

    /// 실행 시작 시각. 마지막 실행과 같은 초면 다음 초까지 기다린다.
    private func startTime(after last: String?, wait: Bool) throws -> Date {
        var now = clock.now()
        guard wait, let last else { return now }
        var attempts = 0
        while LawArchiveKeys.runVersion(now) <= last {
            attempts += 1
            guard attempts <= 3 else {
                throw LawArchiveError.clockBehind(last: last, now: LawArchiveKeys.runVersion(now))
            }
            let seconds = now.timeIntervalSince1970
            clock.sleep(floor(seconds) + 1 - seconds + 0.001)
            now = clock.now()
        }
        return now
    }
}
