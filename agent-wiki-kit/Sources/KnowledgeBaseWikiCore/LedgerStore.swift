import Foundation
import StateRootKit

/// append-only 원장 저장소. 연산은 발행(publish)뿐이다(제4조) — 수정·삭제 API 가
/// 아예 없다. 조회는 전 객체 스캔에서 파생한다(제7조 — 인덱스는 나중에 얹어도 됨).
public struct LedgerStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    private var objectsDir: URL { root.appendingPathComponent("objects") }

    // MARK: - 발행 (유일한 쓰기 연산)

    @discardableResult
    public func publish(
        author: String,
        title: String? = nil,
        type: String? = nil,
        body: String,
        now: Date = Date(),
        extras: LedgerPublishExtras = LedgerPublishExtras()
    ) throws -> LedgerObject {
        // 저작 기록은 **정체성 밖**이라 draft(=contentID 계산본)에는 넣지 않는다.
        // 명시 인자가 없으면 환경에서 아는 만큼 채운다(하네스가 심어준 것만).
        let writeAuthoring = extras.authoring ?? {
            let ambient = Authoring.ambient()
            return ambient.isEmpty ? nil : ambient
        }()
        let nfcTitle = title?.precomposedStringWithCanonicalMapping
        let nfcTags = extras.tags.map(\.precomposedStringWithCanonicalMapping)
        let objectExtras = LedgerObject.Extras(
            batch: extras.batch, origin: extras.origin, tags: nfcTags, cites: extras.cites,
            observes: extras.observes, supersedes: extras.supersedes, retracts: extras.retracts,
            source: extras.source)
        // 신규 발행은 제목·태그를 NFC 로 정규화 — NFD 유입(파일계 경유)로 검색이 갈라지지 않게.
        // id 는 content-addressed: sha256(canonicalCore). 코어가 id 를 안 쓰므로 빈 id 로
        // 만들어 contentID 를 구한 뒤 그 값으로 다시 봉인한다(제1조 — 정체성=주소=무결성).
        let draft = LedgerObject(
            id: "", published: now, author: author,
            title: nfcTitle, type: type, body: body, extras: objectExtras)
        var sealed = objectExtras
        sealed.authoring = writeAuthoring
        let object = LedgerObject(
            id: draft.contentID(), published: now, author: author,
            title: nfcTitle, type: type, body: body, extras: sealed)
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: now)
        let dir = objectsDir
            .appendingPathComponent(String(format: "%04d", components.year ?? 0))
            .appendingPathComponent(String(format: "%02d", components.month ?? 0))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(object.id).md")
        let payload = Data(object.serialize().utf8)
        // content-addressed 멱등 — 같은 id 파일이 이미 있으면 내용이 같다는 뜻(주소=내용).
        // 바이트가 동일하면 dedup(그 객체 반환), 다르면 sha256 충돌이므로 실패(제1조).
        if let existing = try? Data(contentsOf: url) {
            guard existing == payload else { throw LedgerError.duplicateID(object.id) }
            return object
        }
        try payload.write(to: url, options: [.withoutOverwriting])
        return object
    }

    /// 하위호환 — 축을 직접 나열하는 옛 호출부(wiki-ui·wiki-reader 등)도 그대로
    /// 컴파일된다. 새 코드는 `extras:` 그룹형으로 쓴다. 둘 다 같은 곳에 쓴다.
    @discardableResult
    public func publish(
        author: String,
        title: String? = nil,
        type: String? = nil,
        body: String,
        cites: [LedgerObject.Cite] = [],
        observes: [String] = [],
        supersedes: String? = nil,
        retracts: String? = nil,
        batch: String? = nil,
        origin: String? = nil,
        tags: [String] = [],
        source: Provenance? = nil,
        authoring: Authoring? = nil,
        now: Date = Date()
    ) throws -> LedgerObject {
        try publish(
            author: author, title: title, type: type, body: body, now: now,
            extras: LedgerPublishExtras(
                cites: cites, observes: observes, supersedes: supersedes, retracts: retracts,
                batch: batch, origin: origin, tags: tags, source: source, authoring: authoring))
    }

    /// 원문을 바꾸지 않고 3축 분류를 덧씌운다. 모든 사용자 표면은 이 API를 통해
    /// `screens` 관계와 근거 문장을 빠뜨리지 않는다.
    @discardableResult
    public func publishScreening(
        author: String,
        target: LedgerObject,
        classification: LedgerClassificationInput,
        batch: String? = nil,
        supersedes: String? = nil,
        now: Date = Date()
    ) throws -> LedgerObject {
        let targetTitle = target.title ?? String(target.id.prefix(12))
        let cleanTargetTitle = targetTitle
            .replacingOccurrences(of: "근거: ", with: "")
            .replacingOccurrences(of: "개념: ", with: "")
            .replacingOccurrences(of: "엔티티: ", with: "")
        let title = "선별: " + cleanTargetTitle
        return try publish(
            author: author,
            title: title,
            type: "screening",
            body: classification.screeningBody,
            now: now,
            extras: LedgerPublishExtras(
                cites: [.init(id: target.id, rel: "screens")],
                supersedes: supersedes,
                batch: batch))
    }

    // MARK: - 조회 (전부 파생)

    public func scan() -> [LedgerObject] {
        guard let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        var objects: [LedgerObject] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = LedgerObject.parse(text) else { continue }
            objects.append(parsed.object)
        }
        return objects.sorted { ($0.published, $0.id) < ($1.published, $1.id) }  // UUIDv7 → 시간순
    }

    /// 증분 스캔 캐시 — 파일 stat(mtime·size)이 같으면 재파싱하지 않는다(파생·폐기 가능, 제7조).
    public struct ScanCache: Sendable {
        public var entries: [String: (mtime: Date, size: Int, object: LedgerObject)] = [:]
        public init() {}
    }

    /// 증분 스캔 — 바뀐 파일만 재파싱. changed=false 면 호출측은 갱신을 건너뛴다.
    public func scan(cache: inout ScanCache) -> (objects: [LedgerObject], changed: Bool) {
        guard let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return ([], !cache.entries.isEmpty) }
        var seen: Set<String> = []
        var changed = false
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let path = url.path
            seen.insert(path)
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mtime = values?.contentModificationDate ?? .distantPast
            let size = values?.fileSize ?? -1
            if let entry = cache.entries[path], entry.mtime == mtime, entry.size == size { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let parsed = LedgerObject.parse(text) else { continue }
            cache.entries[path] = (mtime, size, parsed.object)
            changed = true
        }
        let removed = Set(cache.entries.keys).subtracting(seen)
        if !removed.isEmpty {
            changed = true
            for path in removed { cache.entries.removeValue(forKey: path) }
        }
        return (cache.entries.values.map(\.object).sorted { ($0.published, $0.id) < ($1.published, $1.id) }, changed)
    }

    public func find(_ objects: [LedgerObject], idPrefix: String) -> LedgerObject? {
        let matches = objects.filter { $0.id.hasPrefix(idPrefix.lowercased()) }
        return matches.count == 1 ? matches.first : nil
    }

    /// head = 아무도 supersede 하지 않았고 retract 되지 않았으며, 자신이 철회 발행이 아닌 객체.
    public func heads(_ objects: [LedgerObject]) -> [LedgerObject] {
        let superseded = Set(objects.compactMap(\.supersedes))
        let retracted = Set(objects.compactMap(\.retracts))
        return objects.filter {
            !superseded.contains($0.id) && !retracted.contains($0.id) && $0.retracts == nil
        }
    }

    /// 개정 계보 — head 에서 supersedes 를 따라 과거로.
    public func lineage(_ objects: [LedgerObject], of id: String) -> [LedgerObject] {
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        var chain: [LedgerObject] = []
        var current = byID[id]
        while let object = current, chain.count < 1000 {
            chain.append(object)
            current = object.supersedes.flatMap { byID[$0] }
        }
        return chain
    }

    /// 이 객체를 인용한 것들(역링크).
    public func citedBy(_ objects: [LedgerObject], id: String) -> [LedgerObject] {
        objects.filter { object in object.cites.contains { $0.id == id } }
    }

    // MARK: - 검증 (SPEC verify)

    public struct Violation: Sendable, Equatable {
        public let id: String
        public let problem: String
        public init(id: String, problem: String) {
            self.id = id
            self.problem = problem
        }
    }

    public func verify() -> [Violation] {
        var violations: [Violation] = []
        var seen: Set<String> = []
        var all: [(object: LedgerObject, storedSHA: String)] = []
        guard let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                violations.append(Violation(id: url.lastPathComponent, problem: "읽기 실패"))
                continue
            }
            guard let parsed = LedgerObject.parse(text) else {
                violations.append(Violation(id: url.lastPathComponent, problem: "필수 필드 누락(제2조)"))
                continue
            }
            all.append(parsed)
            if seen.contains(parsed.object.id) {
                violations.append(Violation(id: parsed.object.id, problem: "id 중복(제1조)"))
            }
            seen.insert(parsed.object.id)
            if parsed.storedSHA != LedgerObject.hash(parsed.object.body) {
                violations.append(Violation(id: parsed.object.id, problem: "본문 변조 — sha256 불일치(제1조)"))
            }
            if url.deletingPathExtension().lastPathComponent != parsed.object.id {
                violations.append(Violation(id: parsed.object.id, problem: "파일명-id 불일치"))
            }
            // content-addressed id(64-hex sha256)면 코어 재해시 == id 를 검증한다 — 코어
            // 어느 필드든 변조되면 잡힌다(본문뿐 아니라 메타까지). 구 UUIDv7 id 는 대상 외.
            if LedgerObject.isContentID(parsed.object.id),
               parsed.object.contentID() != parsed.object.id {
                violations.append(Violation(id: parsed.object.id, problem: "코어 변조 — content-id 불일치(제1조)"))
            }
        }
        // 참조 무결성. 프로모션의 두 관계는 의도적으로 다른 world를 가리키며
        // PromotionVerifier가 source/target 원장을 함께 열어 종단점과 receipt를 검증한다.
        let crossWorldRelations: Set<String> = ["promotes", "promoted-as"]
        for (object, _) in all {
            let localCites = object.cites.filter { !crossWorldRelations.contains($0.rel) }.map(\.id)
            for ref in [object.supersedes, object.retracts].compactMap({ $0 }) + localCites
            where !seen.contains(ref) {
                violations.append(Violation(id: object.id, problem: "없는 객체 참조: \(ref)"))
            }
        }
        return violations
    }

    // MARK: - 체크포인트 (그래프-네이티브 무결성 — 삭제 감지)

    /// 현재 전체 객체 집합을 증언하는 체크포인트 객체를 발행한다.
    /// 이전 체크포인트를 cite(checkpoints) 로 물어 체크포인트끼리도 그래프 사슬을 이룬다.
    @discardableResult
    public func publishCheckpoint(author: String, now: Date = Date()) throws -> LedgerObject {
        let objects = scan()
        let ids = objects.map(\.id).sorted()
        let digest = LedgerObject.hash(ids.joined(separator: "\n"))
        let previous = latestCheckpoint(objects)
        var cites: [LedgerObject.Cite] = []
        if let previous { cites.append(.init(id: previous.id, rel: "checkpoints")) }
        let body = """
        objects: \(ids.count)
        set-sha256: \(digest)
        """
        return try publish(
            author: author, title: "체크포인트: 객체 \(ids.count)개",
            body: body, now: now, extras: LedgerPublishExtras(cites: cites))
    }

    public func latestCheckpoint(_ objects: [LedgerObject]) -> LedgerObject? {
        objects.filter { $0.title?.hasPrefix("체크포인트:") == true }.max { ($0.published, $0.id) < ($1.published, $1.id) }
    }

    /// 최신 체크포인트 대비 현재 집합 검사 — 삭제(증발) 감지.
    /// 반환: nil = 체크포인트 없음, 빈 배열 = 이상 없음, 그 외 = 문제 목록.
    public func verifyCheckpoint() -> [Violation]? {
        let objects = scan()
        guard let checkpoint = latestCheckpoint(objects) else { return nil }
        var recorded = 0
        var recordedDigest = ""
        for line in checkpoint.body.split(separator: "\n") {
            if line.hasPrefix("objects: ") { recorded = Int(line.dropFirst(9)) ?? 0 }
            if line.hasPrefix("set-sha256: ") { recordedDigest = String(line.dropFirst(12)) }
        }
        // 체크포인트 시점(id 순서 = 시간 순서) 이전에 발행된 객체만 대상으로 재계산
        let past = objects.filter { ($0.published, $0.id) <= (checkpoint.published, checkpoint.id) && $0.id != checkpoint.id }
        let digest = LedgerObject.hash(past.map(\.id).sorted().joined(separator: "\n"))
        var violations: [Violation] = []
        if past.count < recorded {
            violations.append(Violation(
                id: checkpoint.id,
                problem: "삭제 감지 — 체크포인트 기록 \(recorded)개, 현재 \(past.count)개 (append-only 위반)"))
        } else if digest != recordedDigest {
            violations.append(Violation(
                id: checkpoint.id,
                problem: "집합 불일치 — 체크포인트 이후 과거 객체가 변형됨"))
        }
        return violations
    }

    // MARK: - 롤백 (파생 규칙 — 발행으로만 구현)

    /// batch 의 각 객체를 되돌리는 발행 묶음. 개정이었으면 이전 판 재발행, 신규였으면 철회.
    @discardableResult
    public func rollback(batchID: String, author: String, now: Date = Date()) throws -> [LedgerObject] {
        let objects = scan()
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        let targets = objects.filter { $0.batch == batchID }
        guard !targets.isEmpty else { throw LedgerError.notFound("batch \(batchID)") }
        let rollbackBatch = LedgerID.generate(now: now)
        var published: [LedgerObject] = []
        for target in targets {
            if let previousID = target.supersedes, let previous = byID[previousID] {
                published.append(try publish(
                    author: author, title: previous.title, body: previous.body,
                    now: now,
                    extras: LedgerPublishExtras(
                        cites: [.init(id: target.id, rel: "rolls-back")],
                        supersedes: target.id, batch: rollbackBatch)))
            } else {
                published.append(try publish(
                    author: author, title: target.title.map { "철회: \($0)" },
                    body: "rollback of batch \(batchID)",
                    now: now,
                    extras: LedgerPublishExtras(retracts: target.id, batch: rollbackBatch)))
            }
        }
        return published
    }

}

public struct LedgerPublishExtras: Sendable, Equatable {
    public var cites: [LedgerObject.Cite] = []
    public var observes: [String] = []
    public var supersedes: String? = nil
    public var retracts: String? = nil
    public var batch: String? = nil
    public var origin: String? = nil
    public var tags: [String] = []
    public var source: Provenance? = nil
    public var authoring: Authoring? = nil

    public init(
        cites: [LedgerObject.Cite] = [],
        observes: [String] = [],
        supersedes: String? = nil,
        retracts: String? = nil,
        batch: String? = nil,
        origin: String? = nil,
        tags: [String] = [],
        source: Provenance? = nil,
        authoring: Authoring? = nil
    ) {
        self.cites = cites
        self.observes = observes
        self.supersedes = supersedes
        self.retracts = retracts
        self.batch = batch
        self.origin = origin
        self.tags = tags
        self.source = source
        self.authoring = authoring
    }
}

public enum LedgerError: Error, CustomStringConvertible {
    case duplicateID(String)
    case notFound(String)

    public var description: String {
        switch self {
        case .duplicateID(let id): return "이미 발행된 id: \(id) (제1조 — 재발행 불가)"
        case .notFound(let what): return "찾을 수 없음: \(what)"
        }
    }
}

/// CLI·앱 공용 설정 — 세계관(world) 목록과 현재 선택. 세계관 = 독립 원장 루트.
public struct LedgerWorld: Codable, Sendable, Equatable {
    public var name: String
    public var rootPath: String
    /// 사람용 표시 이름 — 없으면 slug(name) 그대로 보여준다.
    public var display: String?

    /// 사람용 표시 이름 (display 가 있으면 사용, 없으면 표준 기본값 매핑 또는 name).
    public var displayName: String {
        display ?? WorldDisplayNameMapper.defaultDisplayName(for: name)
    }

    public init(name: String, rootPath: String, display: String? = nil) {
        self.name = name
        self.rootPath = rootPath
        self.display = display
    }
}

public struct LedgerConfig: Codable, Sendable {
    public var rootPath: String?          // 구버전 호환
    public var worlds: [LedgerWorld]?
    public var currentWorld: String?

    public init(rootPath: String? = nil, worlds: [LedgerWorld]? = nil, currentWorld: String? = nil) {
        self.rootPath = rootPath
        self.worlds = worlds
        self.currentWorld = currentWorld
    }

    /// 유효 세계관 목록 — 구버전 rootPath 는 첫 세계관으로 승격.
    public var effectiveWorlds: [LedgerWorld] {
        if let worlds, !worlds.isEmpty { return worlds }
        if let rootPath { return [LedgerWorld(name: "gujo-wiki", rootPath: rootPath)] }
        return []
    }

    public var current: LedgerWorld? {
        let all = effectiveWorlds
        if let currentWorld, let world = all.first(where: { $0.name == currentWorld }) { return world }
        return all.first
    }

    /// cwd 에서 상위로 `.wiki/` 를 찾아 그 repo 원장을 반환한다(git 이 `.git` 찾듯).
    /// 권한은 그 repo(GitLab 프로젝트) 멤버십이 집행 — 앱은 접근 검사를 하지 않는다.
    /// - explicitWorld: `--world <name>`. 등록된 이름만. 없으면 nil (current 로 폴백하지 않음).
    /// - tenantWikiWorld: 활성 테넌트 방의 `wikiWorld`. cwd `.wiki` 다음.
    /// - 셋 다 없으면 nil. **gujo-wiki current 폴백 금지** (2026-08-19 원장 3층).
    public func resolveWorld(
        cwd: String,
        explicitWorld: String? = nil,
        tenantWikiWorld: String? = nil
    ) -> LedgerWorld? {
        if let explicitWorld {
            return effectiveWorlds.first { $0.name == explicitWorld }
        }
        let fm = FileManager.default
        var dir = URL(fileURLWithPath: cwd).standardizedFileURL
        while true {
            let wiki = dir.appendingPathComponent(".wiki")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: wiki.path, isDirectory: &isDir), isDir.boolValue {
                // 등록된 world 면 그 등록 정보를 쓰고(GUI 목록·display 일치), 아니면 repo 폴더명으로.
                if let registered = effectiveWorlds.first(where: { $0.rootPath == wiki.path }) {
                    return registered
                }
                return LedgerWorld(name: dir.lastPathComponent, rootPath: wiki.path)
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        if let tenantWikiWorld {
            return effectiveWorlds.first { $0.name == tenantWikiWorld }
        }
        return nil
    }

    /// world 이름→경로 지도. 테넌트 `current-context.json` 을 타면
    /// `~/.tenants/<slug>/.memo-citation-ledger/config.json` 을 읽고(비어 있음)
    /// `--world person-personal` 도 실패한다. 원장 파일은 테넌트 아래, 지도는 호스트.
    public static func configURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> URL {
        URL(fileURLWithPath: StateRootKit.hostPath(
            ".memo-citation-ledger/config.json",
            environment: environment,
            homeDirectory: homeDirectory
        ))
    }

    public static var configURL: URL { configURL() }

    public static func load() -> LedgerConfig {
        guard let data = try? Data(contentsOf: configURL) else {
            return LedgerConfig()
        }
        do {
            return try JSONDecoder().decode(LedgerConfig.self, from: data)
        } catch {
            return LedgerConfig()
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(
            at: Self.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.configURL, options: .atomic)
    }

    public var rootURL: URL? { current.map { URL(fileURLWithPath: $0.rootPath) } }
}
