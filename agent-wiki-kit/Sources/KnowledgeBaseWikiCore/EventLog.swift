import Foundation

/// 사건층 — "무엇이 언제 일어났나"의 사실 로그. 에이전트무관·불변·고volume.
/// 튜플 {occurred, subject, rel, object, source}. 해석(md)은 이 사건을 observes 로 가리킨다.
/// 이중시간(bitemporal): occurred=발생시각(이벤트타임) ≠ recorded=기록시각(기록타임).
public struct Event: Sendable, Codable, Equatable {
    /// 뎁스 층 — 기록은 다 하되 보기는 층별로 접는다. run>step>detail.
    public enum Level: String, Sendable, Codable { case run, step, detail }
    /// 결말 — 성공/실패 빠른 필터. 진행 중이면 pending, 사실 관측이면 nil.
    public enum Outcome: String, Sendable, Codable { case ok, fail, pending }

    public let id: String            // UUIDv7 — 정렬 = 생성순
    public let occurred: Date        // 사건 발생 시각 (이벤트 타임)
    public let recorded: Date        // 기록 시각 (기록 타임) — 사후 기록 사건도 제자리에 꽂힘
    public let writer: String        // 생산자(에이전트/틱)
    public let subject: String       // 주어 — md 객체 id / 사건 id / 외부 식별자
    public let rel: String           // 관계 — 편집·실행·실패·관측 …
    public let object: String?       // 대상(선택) — md 객체 id 등
    public let source: String?       // provenance — 원본 blob sha (선택)
    public let level: Level          // 뎁스 — run(작업)/step(단계)/detail(세부)
    public let parent: String?       // 상위 사건 id — step→run, detail→step (트리)
    public let outcome: Outcome?     // 결말 — ok/fail/pending (완료·진행 사건에만)
    public let attrs: [String: String]  // 부가 속성(선택)

    /// 선택 필드 — 필수 인자와 분리한다.
    public struct Extras: Sendable, Equatable {
        public var id: String? = nil
        public var recorded: Date = Date()
        public var object: String? = nil
        public var source: String? = nil
        public var parent: String? = nil
        public var outcome: Outcome? = nil
        public var attrs: [String: String] = [:]

        public init(
            id: String? = nil,
            recorded: Date = Date(),
            object: String? = nil,
            source: String? = nil,
            parent: String? = nil,
            outcome: Outcome? = nil,
            attrs: [String: String] = [:]
        ) {
            self.id = id
            self.recorded = recorded
            self.object = object
            self.source = source
            self.parent = parent
            self.outcome = outcome
            self.attrs = attrs
        }
    }

    public init(
        writer: String,
        subject: String,
        rel: String,
        occurred: Date = Date(),
        level: Level = .step,
        extras: Extras = Extras()
    ) {
        self.id = extras.id ?? LedgerID.generate(now: occurred)
        self.occurred = occurred
        self.recorded = extras.recorded
        self.writer = writer
        self.subject = subject
        self.rel = rel
        self.object = extras.object
        self.source = extras.source
        self.level = level
        self.parent = extras.parent
        self.outcome = extras.outcome
        self.attrs = extras.attrs
    }

    // 구 이벤트(level/parent/outcome 없음) 하위호환 — 없으면 기본값.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        occurred = try c.decode(Date.self, forKey: .occurred)
        recorded = try c.decode(Date.self, forKey: .recorded)
        writer = try c.decode(String.self, forKey: .writer)
        subject = try c.decode(String.self, forKey: .subject)
        rel = try c.decode(String.self, forKey: .rel)
        object = try c.decodeIfPresent(String.self, forKey: .object)
        source = try c.decodeIfPresent(String.self, forKey: .source)
        level = try c.decodeIfPresent(Level.self, forKey: .level) ?? .step
        parent = try c.decodeIfPresent(String.self, forKey: .parent)
        outcome = try c.decodeIfPresent(Outcome.self, forKey: .outcome)
        attrs = try c.decodeIfPresent([String: String].self, forKey: .attrs) ?? [:]
    }
}

/// append-only 사건 로그 저장소. <root>/events/YYYY-MM/<writer>.<pid>.ndjson.
/// 생산자·프로세스별 세그먼트라 다중 생산자 동시 append 가 서로의 줄을 깨지 않는다
/// (.runs/status 가 pid 별로 나뉜 것과 같은 규율). 굴러간 달 세그먼트는 사실상 불변.
public struct EventLog: Sendable {
    public let root: URL
    private var eventsDir: URL { root.appendingPathComponent("events") }

    public init(root: URL) { self.root = root }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func monthKey(_ date: Date) -> String {
        let cal = Calendar(identifier: .gregorian)
        let c = cal.dateComponents(in: TimeZone(identifier: "UTC")!, from: date)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }

    // MARK: - 쓰기 (유일한 변경 연산 = append)

    /// 사건 한 개를 발생월 세그먼트에 append. 생산자별 pid 세그먼트라 경합 없음.
    public func append(_ event: Event) throws {
        let dir = eventsDir.appendingPathComponent(monthKey(event.occurred))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        let safeWriter = event.writer.replacingOccurrences(of: "/", with: "_")
        let file = dir.appendingPathComponent("\(safeWriter).\(pid).ndjson")
        var data = try Self.encoder.encode(event)
        data.append(0x0A)  // 개행 — NDJSON 한 줄
        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: file, options: [.withoutOverwriting])
        }
    }

    // MARK: - 읽기 (전부 파생·재현 가능)

    /// 모든 세그먼트 파일(events/YYYY-MM/*.ndjson).
    public func segments() -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: eventsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "ndjson" { out.append(url) }
        return out.sorted { $0.path < $1.path }
    }

    /// 전 사건 — occurred 순 정렬. (고volume 시엔 graph.db 로 질의; 여기선 스캔)
    public func all() -> [Event] {
        var events: [Event] = []
        for seg in segments() {
            guard let text = try? String(contentsOf: seg, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where !line.isEmpty {
                if let e = try? Self.decoder.decode(Event.self, from: Data(line.utf8)) { events.append(e) }
            }
        }
        return events.sorted { $0.occurred < $1.occurred }
    }

    /// 최근 N개(occurred 기준).
    public func tail(_ n: Int) -> [Event] { Array(all().suffix(n)) }

    public func count() -> Int {
        var total = 0
        for seg in segments() {
            guard let text = try? String(contentsOf: seg, encoding: .utf8) else { continue }
            total += text.split(separator: "\n").filter { !$0.isEmpty }.count
        }
        return total
    }

    /// 사건이 참조하는 모든 원본 blob sha — BlobStore.prune 의 reachable 집합.
    public func reachableBlobSHAs() -> Set<String> {
        Set(all().compactMap(\.source))
    }

    /// 한 원본 blob 을 참조(source)하는 사건들 — "이 원본에 연결된 게 뭔가"(역참조). occurred 순.
    public func eventsReferencing(blob sha: String) -> [Event] {
        all().filter { $0.source == sha }.sorted { $0.occurred < $1.occurred }
    }

    /// 특정 rel 사건의 subject 집합 — since 이후 발생분. "이미 선정/시도한 것" 조회에 쓴다.
    /// md 는 성공한 결과만 알지만 사건은 "선정·시도"까지 알아서, 못 끝낸 것도 순환에서 뺄 수 있다.
    public func subjectsWithEvent(rel: String, since: Date) -> Set<String> {
        Set(all().filter { $0.rel == rel && $0.occurred >= since }.map(\.subject))
    }

    /// 순환 선정 — 최근 선정된 것(recentlySelected)을 뒤로 미룬다. 후보가 다 최근이면(한 바퀴
    /// 다 돌았으면) 리셋해 ranked 그대로 반환. 매주 같은 것만 다시 뽑히는 걸 막아 커버리지를 넓힌다.
    public static func rotatedTargets(ranked: [String], recentlySelected: Set<String>, limit: Int) -> [String] {
        let fresh = ranked.filter { !recentlySelected.contains($0) }
        let pool = fresh.isEmpty ? ranked : fresh
        return Array(pool.prefix(limit))
    }

    /// 한 사건의 직계 자식들(parent==id) — 트리 펼치기용. occurred 순.
    public func children(of id: String, in events: [Event]? = nil) -> [Event] {
        (events ?? all()).filter { $0.parent == id }.sorted { $0.occurred < $1.occurred }
    }

    /// 좌초 작업 — level=run·outcome=pending 인 시작 사건 중, 완료(ok/fail) 자식이 없고
    /// cutoff 이전에 발생한 것. run-reaper 가 파일 뒤짐 대신 이 질의로 판정한다.
    public func openRuns(olderThan cutoff: Date) -> [Event] {
        let events = all()
        let closedParents = Set(events
            .filter { $0.level == .run && ($0.outcome == .ok || $0.outcome == .fail) }
            .compactMap(\.parent))
        return events.filter {
            $0.level == .run && $0.outcome == .pending
                && !closedParents.contains($0.id) && $0.occurred < cutoff
        }
    }
}
