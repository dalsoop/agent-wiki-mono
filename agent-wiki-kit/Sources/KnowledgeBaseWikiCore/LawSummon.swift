import Foundation
import StateRootKit
import WikiLedgerKit

// 소환(`summon`)과 증언 확인 — 적재된 세션 조각(R2)과 아직 적재 전인 로컬 세션에서 발화를 불러온다.
// 근거: docs/business-rules.md "화자"·"본문 머리 칸"(evidence)·"관계", docs/security.md "agent-law" 격리 표
// (소환 범위: 같은 테넌트 원장과 공유 원장 `law`, 다른 테넌트·`unassigned` 거부), docs/contracts.md `summon`,
// docs/architecture.md "agent-law"(소환 색인은 로컬 파생, R2 에서 재생성), 결정 0007.
//
// - 범위: 호출한 원장의 원장 키와 그 상위 사슬(공유 원장 `law`)의 원장 키. 테넌트 원장 키는 적재가
//   테넌트 대응표(`tenantMap`)로 고른 자리라, 원장 키 = 그 테넌트다. 기기는 가리지 않는다.
// - 색인: 완료된 적재 실행 요약에 실린 조각만 읽어 로컬 상태 폴더에 사본으로 둔다. 지워도 R2 에서 다시 만든다.
//   가린 조각(R2 에 없음, 또는 가림 기록의 대상)은 건너뛰고 로컬 사본도 지운다.
// - 증언 확인(`LawSessionTestimony`)은 같은 색인·로컬 세션을 읽어, 가린 인용 구절이 같은 가림 규칙을
//   적용한 발화 하나의 연속 부분 문자열과 글자 단위로 같은지 본다.

// MARK: - 범위

public struct LawSummonScope: Sendable, Equatable {
    /// 호출한 원장(world 이름).
    public let world: String
    /// 호출한 원장의 원장 키.
    public let ledgerKey: String
    /// 소환할 수 있는 원장 키(호출 원장 → 상위 사슬 순).
    public let ledgerKeys: [String]
    public let catalog: WorldBindingCatalog

    /// 원장 키가 없는 원장이면 nil.
    public init?(world: String, catalog: WorldBindingCatalog) {
        guard let key = catalog.world(named: world)?.key, LedgerKeyFormat.isValid(key) else { return nil }
        self.world = world
        self.ledgerKey = key
        self.catalog = catalog
        var keys = [key]
        for ancestor in catalog.ancestorNames(of: world) {
            if let parentKey = catalog.world(named: ancestor)?.key, !keys.contains(parentKey) { keys.append(parentKey) }
        }
        self.ledgerKeys = keys
    }

    public func contains(ledgerKey: String) -> Bool { ledgerKeys.contains(ledgerKey) }

    /// 같은 설정의 범위 밖 원장 키(다른 테넌트 원장).
    public var otherLedgerKeys: [String] {
        catalog.worlds.compactMap(\.key).filter { !ledgerKeys.contains($0) }
    }

    /// 범위 안 원장들의 로컬 원장 저장소(가림 기록 읽기).
    var ledgerStores: [LawStore] {
        ledgerKeys.compactMap { key in
            catalog.worlds.first { $0.key == key }.map { LawStore(root: URL(fileURLWithPath: $0.rootPath)) }
        }
    }
}

// MARK: - 원천

/// 소환·증언 확인이 세션을 찾는 원천. 실제는 `standard`(R2·키체인·공용 세션 리더·상태 루트), 시험은 주입한다.
public struct LawSummonSources: Sendable {
    /// R2 저장소. 부를 때 만든다(키체인은 이때 읽는다). 없거나 실패하면 로컬 색인 사본만 쓴다.
    public var objectStore: @Sendable () throws -> (any LawObjectStore)?
    /// 아직 적재 전인 로컬 세션.
    public var local: (any LawSessionSource)?
    /// 로컬 세션의 테넌트 판정에 쓰는 세션 등록.
    public var registry: LawSessionRegistry?
    /// 테넌트 → 원장(world) 대응표.
    public var tenantMap: [String: String]?
    /// 이 기기의 기기 키(로컬 세션 발화의 기기).
    public var currentDevice: String?
    /// 소환 색인 사본 폴더. nil 이면 사본을 두지 않는다.
    public var indexDirectory: URL?

    public init(
        objectStore: @escaping @Sendable () throws -> (any LawObjectStore)?,
        local: (any LawSessionSource)? = nil, registry: LawSessionRegistry? = nil,
        tenantMap: [String: String]? = nil, currentDevice: String? = nil, indexDirectory: URL? = nil
    ) {
        self.objectStore = objectStore
        self.local = local
        self.registry = registry
        self.tenantMap = tenantMap
        self.currentDevice = currentDevice
        self.indexDirectory = indexDirectory
    }

    /// 상태 루트 `~/.agent-wiki/summon`.
    public static var standardIndexDirectory: URL { StateRootKit.url(".agent-wiki/summon") }

    /// 호스트 설정 + 키체인 R2 + 공용 세션 리더 + 세션 등록 + 상태 루트 색인. 만들 때는 아무것도 읽지 않는다.
    public static func standard(file: BoundLedgerFile?) -> LawSummonSources {
        let resolved = file ?? BoundLedgerFile()
        return LawSummonSources(
            objectStore: { try LawR2Client.standard(file: resolved) },
            local: LawAgentSessionSource(), registry: .standard, tenantMap: file?.tenantMap,
            currentDevice: file?.currentDevice, indexDirectory: standardIndexDirectory)
    }
}

// MARK: - 발화·조건·결과

/// 소환한 발화 하나(가린 뒤).
public struct LawSummonUtterance: Codable, Sendable, Equatable {
    public var ledgerKey: String
    public var device: String
    public var runtime: String
    public var session: String
    /// 세션 안의 발화 번호(0부터). `--record` 가 받는 번호.
    public var index: Int
    /// `user` · `assistant`.
    public var role: String
    public var text: String
    /// 시각(한국 시간). 적재된 발화는 그 조각을 올린 적재 실행의 시작 시각, 적재 전 로컬 발화는 세션 시작 시각.
    public var at: String?
    /// 조각 주소(R2 키). 적재 전 로컬 발화는 nil.
    public var chunk: String?

    public init(
        ledgerKey: String, device: String, runtime: String, session: String, index: Int, role: String,
        text: String, at: String?, chunk: String?
    ) {
        self.ledgerKey = ledgerKey
        self.device = device
        self.runtime = runtime
        self.session = session
        self.index = index
        self.role = role
        self.text = text
        self.at = at
        self.chunk = chunk
    }

    /// 발화 역할 → 화자. 공용 리더는 `user`·`assistant` 둘만 준다(다른 에이전트 발화를 가르지 못한다).
    public var speaker: LawSpeaker? { LawSummonUtterance.speaker(role: role) }

    public static func speaker(role: String) -> LawSpeaker? {
        switch role {
        case "user": return .user
        case "assistant": return .agent
        default: return nil
        }
    }

    var atDate: Date? { at.flatMap(LawSummonQuery.parseTime) }
}

/// 소환 조건. 모든 칸은 그리고(AND)로 묶인다.
public struct LawSummonQuery: Sendable, Equatable {
    public var session: String?
    public var since: Date?
    public var until: Date?
    public var device: String?
    public var runtime: String?
    /// `user` · `assistant`.
    public var role: String?
    /// 낱말 검색 — 공백으로 나눈 낱말이 모두 들어 있는 발화(대소문자 무시).
    public var query: String?

    public init(
        session: String? = nil, since: Date? = nil, until: Date? = nil, device: String? = nil,
        runtime: String? = nil, role: String? = nil, query: String? = nil
    ) {
        self.session = session
        self.since = since
        self.until = until
        self.device = device
        self.runtime = runtime
        self.role = role
        self.query = query
    }

    func matches(_ utterance: LawSummonUtterance) -> Bool {
        if let session, utterance.session != session { return false }
        if let device, utterance.device != device { return false }
        if let runtime, utterance.runtime != runtime { return false }
        if let role, utterance.role != role { return false }
        if since != nil || until != nil {
            guard let at = utterance.atDate else { return false }
            if let since, at < since { return false }
            if let until, at > until { return false }
        }
        if let query {
            let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
            for word in words where utterance.text.range(of: word, options: [.caseInsensitive]) == nil { return false }
        }
        return true
    }

    /// 시각 인자: `LawTime`(ms UTC), ISO 8601(초·소수 초), `yyyy-MM-dd`(한국 시간 자정).
    public static func parseTime(_ raw: String) -> Date? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        if let date = LawTime.parse(value) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(identifier: "Asia/Seoul")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: value)
    }
}

public struct LawSummonResult: Codable, Sendable, Equatable {
    public var ledgerKeys: [String]
    public var utterances: [LawSummonUtterance]
    /// 가려서 건너뛴 조각 수.
    public var redactedChunks: Int
    /// R2 를 못 읽어 로컬 색인 사본만 쓴 이유.
    public var offline: String?

    public init(ledgerKeys: [String], utterances: [LawSummonUtterance], redactedChunks: Int, offline: String?) {
        self.ledgerKeys = ledgerKeys
        self.utterances = utterances
        self.redactedChunks = redactedChunks
        self.offline = offline
    }
}

public enum LawSummonError: Error, Equatable, Sendable, CustomStringConvertible {
    case noLedgerKey(String)
    case outOfScope(session: String, ledger: String)
    case sessionNotFound(String)
    case ambiguousSession([String])
    case utteranceNotFound(session: String, index: Int)
    case emptyUtterance(session: String, index: Int)

    public var description: String {
        switch self {
        case .noLedgerKey(let world): return "원장 키가 없는 원장에서는 소환할 수 없음: \(world)"
        case .outOfScope(let session, let ledger):
            return "소환 범위 밖 세션: \(session) (\(ledger)) — 같은 테넌트 원장과 공유 원장(law)의 세션만 소환한다"
        case .sessionNotFound(let session): return "세션을 찾을 수 없음: \(session)"
        case .ambiguousSession(let sessions):
            return "--record 는 세션 하나에서만 — --session 으로 고르세요: " + sessions.prefix(5).joined(separator: ", ")
        case .utteranceNotFound(let session, let index): return "발화를 찾을 수 없음: \(session) #\(index)"
        case .emptyUtterance(let session, let index): return "빈 발화는 증거로 저장하지 않음: \(session) #\(index)"
        }
    }
}

// MARK: - 색인(로컬 파생 사본)

/// 소환 색인. 조각 사본을 `<폴더>/<원장 키>/chunks/<sha256(조각 주소)>.json` 에, 실행 요약 사본을
/// `<폴더>/<원장 키>/manifests/…` 에 둔다. R2 에서 언제든 다시 만들 수 있다.
public struct LawSummonIndex: Sendable {
    public let directory: URL?

    public init(directory: URL?) {
        self.directory = directory
    }

    struct CachedChunk: Codable, Equatable {
        var key: String
        var ledgerKey: String
        var device: String
        var run: String
        var startedAt: String
        var runtime: String
        var session: String
        var from: Int
        var to: Int
        var utterances: [LawArchivedUtterance]
    }

    struct Loaded {
        var utterances: [LawSummonUtterance]
        var redactedChunks: Int
        var offline: String?
    }

    func chunksDirectory(_ ledgerKey: String) -> URL? {
        directory?.appendingPathComponent(ledgerKey, isDirectory: true).appendingPathComponent("chunks", isDirectory: true)
    }

    func manifestsDirectory(_ ledgerKey: String) -> URL? {
        directory?.appendingPathComponent(ledgerKey, isDirectory: true).appendingPathComponent("manifests", isDirectory: true)
    }

    static func fileName(_ key: String) -> String { LawHash.sha256Hex(key) + ".json" }

    /// 범위의 원장 키들을 읽는다. R2 가 있으면 새 조각을 사본으로 받고, 없으면 사본만 쓴다.
    /// - Parameter redacted: 가림 기록의 대상 주소들. 이 조각은 건너뛰고 사본도 지운다.
    func load(ledgerKeys: [String], store: (any LawObjectStore)?, offline initialOffline: String?, redacted: Set<String>)
        -> Loaded
    {
        var loaded = Loaded(utterances: [], redactedChunks: 0, offline: initialOffline)
        var skipped: Set<String> = []
        for ledgerKey in ledgerKeys {
            var chunks = cachedChunks(ledgerKey)
            if let store, loaded.offline == nil {
                do {
                    for manifest in try manifests(ledgerKey: ledgerKey, store: store) {
                        for chunk in manifest.chunks where chunks[chunk.key] == nil {
                            guard !redacted.contains(chunk.key) else {
                                skipped.insert(chunk.key)
                                continue
                            }
                            do {
                                let lines = try LawSessionChunks.read(store: store, key: chunk.key)
                                let cached = CachedChunk(
                                    key: chunk.key, ledgerKey: manifest.ledgerKey, device: manifest.device,
                                    run: manifest.run, startedAt: manifest.startedAt, runtime: chunk.runtime,
                                    session: chunk.session, from: chunk.from, to: chunk.to, utterances: lines)
                                chunks[chunk.key] = cached
                                save(cached)
                            } catch LawObjectStoreError.notFound {
                                skipped.insert(chunk.key)  // 가린 조각
                            }
                        }
                    }
                } catch {
                    loaded.offline = "\(error)"
                }
            }
            for (key, chunk) in chunks.sorted(by: { $0.key < $1.key }) {
                if redacted.contains(key) {
                    remove(key: key, ledgerKey: ledgerKey)
                    skipped.insert(key)
                    continue
                }
                let at = LawRunTime.kst(chunk.startedAt)
                loaded.utterances += chunk.utterances.map { line in
                    LawSummonUtterance(
                        ledgerKey: chunk.ledgerKey, device: chunk.device, runtime: chunk.runtime, session: chunk.session,
                        index: line.index, role: line.role, text: line.text, at: at, chunk: chunk.key)
                }
            }
        }
        loaded.redactedChunks = skipped.count
        return loaded
    }

    /// 완료된 실행 요약(사본 우선). 실행 요약은 바뀌지 않으므로 한 번 받으면 다시 받지 않는다.
    func manifests(ledgerKey: String, store: any LawObjectStore) throws -> [LawArchiveManifest] {
        let keys = try store.list(prefix: LawArchiveKeys.manifestPrefix(ledgerKey: ledgerKey))
            .filter { $0.hasSuffix("/manifest.json") }
        var result: [LawArchiveManifest] = []
        let decoder = JSONDecoder()
        for key in keys {
            let cacheURL = manifestsDirectory(ledgerKey)?.appendingPathComponent(Self.fileName(key))
            if let cacheURL, let data = try? Data(contentsOf: cacheURL),
               let manifest = try? decoder.decode(LawArchiveManifest.self, from: data) {
                result.append(manifest)
                continue
            }
            let data = try store.get(key: key)
            let manifest = try decoder.decode(LawArchiveManifest.self, from: data)
            if let cacheURL { write(data, to: cacheURL) }
            result.append(manifest)
        }
        return result.sorted { $0.run < $1.run }
    }

    func cachedChunks(_ ledgerKey: String) -> [String: CachedChunk] {
        guard let dir = chunksDirectory(ledgerKey),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [:] }
        var map: [String: CachedChunk] = [:]
        let decoder = JSONDecoder()
        for name in names where name.hasSuffix(".json") {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)),
                  let chunk = try? decoder.decode(CachedChunk.self, from: data), chunk.ledgerKey == ledgerKey
            else { continue }
            map[chunk.key] = chunk
        }
        return map
    }

    func save(_ chunk: CachedChunk) {
        guard let dir = chunksDirectory(chunk.ledgerKey) else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(chunk) else { return }
        write(data, to: dir.appendingPathComponent(Self.fileName(chunk.key)))
    }

    func remove(key: String, ledgerKey: String) {
        guard let dir = chunksDirectory(ledgerKey) else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.fileName(key)))
    }

    /// 사본 쓰기 실패는 소환 실패가 아니다(다음 소환이 다시 받는다).
    func write(_ data: Data, to url: URL) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }
}

enum LawRunTime {
    /// 실행 요약의 시작 시각(한국 시간 ISO 8601)을 그대로 쓰되, 읽을 수 없으면 nil.
    static func kst(_ raw: String) -> String? {
        LawSummonQuery.parseTime(raw).map(LawArchiveKeys.kstTimestamp)
    }
}

// MARK: - 증거물

/// `summon --record` 가 저장하는 증거물(UTF-8 JSON). 인용 구절은 가린 발화 전체다.
public struct LawSummonExhibit: Codable, Sendable, Equatable {
    public static let kindValue = "agent-law-utterance"

    public var kind: String
    public var quote: String
    public var speaker: String
    public var role: String
    public var at: String?
    public var session: String
    public var runtime: String
    public var device: String
    public var ledgerKey: String
    public var index: Int
    /// 조각 주소(R2 키). 적재 전 로컬 발화는 nil.
    public var chunk: String?

    public init(utterance: LawSummonUtterance, speaker: LawSpeaker) {
        kind = Self.kindValue
        quote = utterance.text
        self.speaker = speaker.rawValue
        role = utterance.role
        at = utterance.at
        session = utterance.session
        runtime = utterance.runtime
        device = utterance.device
        ledgerKey = utterance.ledgerKey
        index = utterance.index
        chunk = utterance.chunk
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    /// 이 형식의 증거물이면 읽는다. 다른 증거물(손으로 넣은 인용 구절 등)은 nil.
    public static func decode(_ text: String) -> LawSummonExhibit? {
        guard let exhibit = try? JSONDecoder().decode(LawSummonExhibit.self, from: Data(text.utf8)),
              exhibit.kind == kindValue else { return nil }
        return exhibit
    }
}

public struct LawSummonRecordOutcome: Sendable, Equatable {
    public let record: LawStoredRecord
    public let exhibit: String
    public let utterance: LawSummonUtterance
    /// 증거물을 R2 에 올렸는가. 못 올렸으면 이유(다음 동기화가 올린다).
    public let uploaded: Bool
    public let uploadError: String?
}

// MARK: - 소환

/// 소환 검색·증거 저장. 드리밍과 심급도 이 함수들로 세션 발화를 읽는다.
public enum LawSummonService {
    public static func scope(of target: LawLedgerTarget) throws -> LawSummonScope {
        guard let scope = LawSummonScope(world: target.worldName, catalog: target.catalog) else {
            throw LawSummonError.noLedgerKey(target.worldName)
        }
        return scope
    }

    /// 조건에 맞는 발화(범위 안). `--session` 이 있으면 아직 적재 전인 로컬 발화도 붙인다.
    /// 범위 밖 세션을 `--session` 으로 지목하면 `outOfScope`.
    public static func search(_ query: LawSummonQuery, target: LawLedgerTarget) throws -> LawSummonResult {
        try search(query, scope: scope(of: target), sources: target.summonSources)
    }

    public static func search(_ query: LawSummonQuery, scope: LawSummonScope, sources: LawSummonSources) throws
        -> LawSummonResult
    {
        let (store, offline) = openStore(sources)
        let loaded = LawSummonIndex(directory: sources.indexDirectory).load(
            ledgerKeys: scope.ledgerKeys, store: store, offline: offline, redacted: redactedTargets(scope))
        var utterances = loaded.utterances
        if let session = query.session {
            utterances = utterances.filter { $0.session == session }
            let local = try localUtterances(session: session, scope: scope, sources: sources, archived: utterances)
            utterances += local
            if utterances.isEmpty, let ledger = outOfScopeLedger(session: session, scope: scope, store: store) {
                throw LawSummonError.outOfScope(session: session, ledger: ledger)
            }
        }
        let matched = utterances.filter(query.matches).sorted(by: order)
        return LawSummonResult(
            ledgerKeys: scope.ledgerKeys, utterances: matched, redactedChunks: loaded.redactedChunks,
            offline: loaded.offline)
    }

    /// 세션 하나의 범위 안 발화 전체(적재본 + 적재 전 로컬 발화, 발화 번호 순). 증언 확인이 쓴다.
    public static func sessionUtterances(
        session: String, runtime: String? = nil, device: String? = nil, scope: LawSummonScope,
        sources: LawSummonSources
    ) -> [LawSummonUtterance] {
        let query = LawSummonQuery(session: session, device: device, runtime: runtime)
        return (try? search(query, scope: scope, sources: sources).utterances) ?? []
    }

    /// `summon --record <발화 번호>` — 증거물(가린 발화 전체·화자·시각·세션 id·조각 주소)을 저장하고
    /// 그것을 가리키는 `evidence` 기록을 공포한다. 화자는 공포 경로의 증언 확인이 정한다.
    public static func record(
        index: Int, query: LawSummonQuery, target: LawLedgerTarget, actor: LawActor, now: Date = Date()
    ) throws -> LawSummonRecordOutcome {
        let summonScope = try scope(of: target)
        let sources = target.summonSources
        let result = try search(query, scope: summonScope, sources: sources)
        let sessions = Set(result.utterances.map { "\($0.runtime)/\($0.session)" })
        guard sessions.count <= 1 else { throw LawSummonError.ambiguousSession(sessions.sorted()) }
        guard let utterance = result.utterances.first(where: { $0.index == index }) else {
            throw LawSummonError.utteranceNotFound(session: query.session ?? sessions.first ?? "-", index: index)
        }
        guard !utterance.text.isEmpty, let speaker = utterance.speaker else {
            throw LawSummonError.emptyUtterance(session: utterance.session, index: index)
        }
        let data = try LawSummonExhibit(utterance: utterance, speaker: speaker).encoded()
        let sha = try target.store.putExhibit(data)
        let body = [
            "session: \(utterance.session)",
            "utterance-at: \(utterance.at ?? LawArchiveKeys.kstTimestamp(now))",
            "runtime: \(utterance.runtime)",
            "device: \(utterance.device)",
            "",
            utterance.text,
        ].joined(separator: "\n") + "\n"
        let draft = LawDraft(
            actor: actor, title: "증언: \(utterance.runtime)/\(utterance.session) #\(utterance.index)",
            type: LawRecordType.evidence.rawValue, exhibits: [sha], body: body)
        let stored = try LawEnactService.enact(draft, target: target, now: now)

        var uploaded = false
        var uploadError: String?
        do {
            if let store = try sources.objectStore() {
                try store.putImmutable(
                    key: LawArchiveKeys.exhibit(ledgerKey: summonScope.ledgerKey, sha256: sha), data: data,
                    contentType: "application/json")
                uploaded = true
            } else {
                uploadError = "R2 저장소 없음"
            }
        } catch {
            uploadError = "\(error)"
        }
        return LawSummonRecordOutcome(
            record: stored, exhibit: sha, utterance: utterance, uploaded: uploaded, uploadError: uploadError)
    }

    // MARK: 내부

    static func order(_ lhs: LawSummonUtterance, _ rhs: LawSummonUtterance) -> Bool {
        (lhs.atDate ?? .distantPast, lhs.ledgerKey, lhs.device, lhs.runtime, lhs.session, lhs.index)
            < (rhs.atDate ?? .distantPast, rhs.ledgerKey, rhs.device, rhs.runtime, rhs.session, rhs.index)
    }

    static func openStore(_ sources: LawSummonSources) -> ((any LawObjectStore)?, String?) {
        do {
            guard let store = try sources.objectStore() else { return (nil, "R2 저장소 없음") }
            return (store, nil)
        } catch {
            return (nil, "\(error)")
        }
    }

    /// 범위 안 원장들의 가림 기록 대상(R2 키).
    static func redactedTargets(_ scope: LawSummonScope) -> Set<String> {
        var targets: Set<String> = []
        for store in scope.ledgerStores {
            for entry in LawRedactionSweep.redactionRecords(store) { targets.formUnion(entry.targets) }
        }
        return targets
    }

    /// 로컬 세션의 원장 키(세션 등록의 테넌트 → 대응표 → 원장 키). 표에 없으면 `unassigned/<테넌트>`.
    static func localLedger(session: String, scope: LawSummonScope, sources: LawSummonSources) -> String {
        let tenant = sources.registry?.registration(sessionID: session)?.tenant
        let resolution = TenantLedgerRouting.resolve(tenant: tenant, tenantMap: sources.tenantMap)
        if let world = resolution.worldName, let key = scope.catalog.world(named: world)?.key { return key }
        return LawArchiveKeys.unassigned(tenant: tenant)
    }

    /// 아직 적재 전인 로컬 발화(적재본에 없는 발화 번호만). 범위 밖 테넌트의 로컬 세션이면 `outOfScope`.
    static func localUtterances(
        session: String, scope: LawSummonScope, sources: LawSummonSources, archived: [LawSummonUtterance]
    ) throws -> [LawSummonUtterance] {
        guard let local = sources.local, LawSessionRegistry.isValidSessionID(session),
              let candidate = local.session(id: session) else { return [] }
        let runtime = candidate.runtime.rawValue
        let known = Set(archived.filter { $0.runtime == runtime }.map(\.index))
        let lines = local.utterances(of: candidate)
        guard lines.indices.contains(where: { !known.contains($0) }) else { return [] }
        // 이미 범위 안에 적재된 세션이면 그 원장 키, 아니면 세션 등록의 테넌트로 판정한다.
        let ledgerKey = archived.first?.ledgerKey ?? localLedger(session: session, scope: scope, sources: sources)
        guard scope.contains(ledgerKey: ledgerKey) else {
            throw LawSummonError.outOfScope(session: session, ledger: ledgerKey)
        }
        let registered = sources.registry?.registration(sessionID: session)?.startedAt
            .flatMap(LawSummonQuery.parseTime)
        let at = (registered ?? candidate.startedAt).map(LawArchiveKeys.kstTimestamp)
        return lines.enumerated().compactMap { index, line in
            guard !known.contains(index) else { return nil }
            return LawSummonUtterance(
                ledgerKey: ledgerKey, device: sources.currentDevice ?? "local", runtime: runtime, session: session,
                index: index, role: line.role, text: LawRedaction.redact(line.text), at: at, chunk: nil)
        }
    }

    /// 범위 밖(다른 테넌트 원장·`unassigned`)에 적재된 세션이면 그 자리. 실행 요약만 읽는다(조각 내용은 읽지 않는다).
    static func outOfScopeLedger(session: String, scope: LawSummonScope, store: (any LawObjectStore)?) -> String? {
        guard let store else { return nil }
        let decoder = JSONDecoder()
        var prefixes = scope.otherLedgerKeys.map { LawArchiveKeys.manifestPrefix(ledgerKey: $0) }
        prefixes.append(LawArchiveKeys.unassignedPrefix + "/")
        for prefix in prefixes {
            guard let keys = try? store.list(prefix: prefix) else { continue }
            for key in keys where key.hasSuffix("/manifest.json") && key.contains("/runs/archive/") {
                guard let data = try? store.get(key: key),
                      let manifest = try? decoder.decode(LawArchiveManifest.self, from: data) else { continue }
                if manifest.chunks.contains(where: { $0.session == session }) { return manifest.ledgerKey }
            }
        }
        return nil
    }
}

// MARK: - 증언 확인

/// 증언 확인자 — 공포 경로의 기본 확인자. 증거 기록의 세션(범위 안 적재본 또는 로컬 세션)의 발화에
/// 같은 가림 규칙(`LawRedaction.redact`, 적재본은 이미 가린 것)을 적용한 뒤, 인용 구절이 발화 하나의 연속
/// 부분 문자열과 글자 단위로 같으면 그 발화 역할(user → `user`, assistant → `agent`)을 화자로 돌려준다.
/// 세션 없음·불일치·역할이 갈리는 모호한 인용이면 nil(공포 거부).
public struct LawSessionTestimony: LawTestimonyVerifying {
    public let scope: LawSummonScope?
    /// 원천은 확인할 때 만든다(공포 경로가 확인자를 만들기만 해서는 세션·R2·상태 루트를 읽지 않는다).
    let resolveSources: @Sendable () -> LawSummonSources

    public init(scope: LawSummonScope?, sources: LawSummonSources) {
        self.scope = scope
        resolveSources = { sources }
    }

    public init(scope: LawSummonScope?, sources: @escaping @Sendable () -> LawSummonSources) {
        self.scope = scope
        resolveSources = sources
    }

    public init(target: LawLedgerTarget) {
        let file = target.file
        let override = target.summonOverride
        self.init(scope: LawSummonScope(world: target.worldName, catalog: target.catalog)) {
            override ?? .standard(file: file)
        }
    }

    public func speaker(for request: LawTestimonyRequest) throws -> LawSpeaker? {
        guard let scope, let session = request.session, !session.isEmpty, !request.quotes.isEmpty else { return nil }
        let sources = resolveSources()
        let utterances = LawSummonService.sessionUtterances(
            session: session, runtime: request.runtime, device: request.device, scope: scope, sources: sources)
        guard !utterances.isEmpty else { return nil }
        var speakers: Set<LawSpeaker> = []
        for quote in request.quotes {
            guard let text = quoteText(quote, scope: scope, sources: sources) else { return nil }
            var candidates = utterances
            var needle = text
            if let exhibit = LawSummonExhibit.decode(text) {
                guard exhibit.session == session else { return nil }
                candidates = candidates.filter { $0.index == exhibit.index && $0.runtime == exhibit.runtime }
                needle = exhibit.quote
            }
            guard !needle.isEmpty else { return nil }
            let roles = Set(candidates.filter { $0.text.range(of: needle, options: .literal) != nil }.compactMap(\.speaker))
            guard roles.count == 1 else { return nil }
            speakers.formUnion(roles)
        }
        return speakers.count == 1 ? speakers.first : nil
    }

    /// 증거물 내용. 로컬 내용이 없으면 범위 안 R2 증거물에서 읽는다. 내용의 sha256 이 이름과 다르면 nil.
    func quoteText(_ quote: LawExhibitQuote, scope: LawSummonScope, sources: LawSummonSources) -> String? {
        if let text = quote.text {
            return LawHash.sha256Hex(Data(text.utf8)) == quote.sha256 ? text : nil
        }
        guard let store = try? sources.objectStore() else { return nil }
        for ledgerKey in scope.ledgerKeys {
            guard let data = try? store.get(key: LawArchiveKeys.exhibit(ledgerKey: ledgerKey, sha256: quote.sha256)),
                  LawHash.sha256Hex(data) == quote.sha256 else { continue }
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
}
