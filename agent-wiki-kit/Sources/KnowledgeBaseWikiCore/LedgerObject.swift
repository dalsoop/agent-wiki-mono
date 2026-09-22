import CitationLedgerKit
import CryptoKit
import Foundation

/// SPEC.md 제1~3조의 객체. 발행 후 불변 — 이 타입은 값이지 편집 대상이 아니다.
/// content-addressing 의 기계적 뼈대(해시·시간·UUIDv7)는 공유 `CitationLedgerKit` 로 위임
/// (forge ForgeObject 와 같은 코어를 쓴다 — 드리프트 방지).
public struct LedgerObject: Identifiable, Sendable, Equatable {
    public struct Cite: Sendable, Equatable {
        public let id: String
        public let rel: String

        public init(id: String, rel: String) {
            self.id = id
            self.rel = rel
        }
    }

    public let ledger: Int
    public let id: String
    public let published: Date
    public let author: String
    public let sha256: String
    public let title: String?
    public let batch: String?
    /// OKF 정합 — 개념 유형 (확장 필드, 선택). 예: evidence, concept, entity, screening, decision.
    public let type: String?
    /// 출처 — 스크랩·수집 근거의 기원 URL/경로 (확장 필드, 선택).
    public let origin: String?
    /// 태그 (확장 필드, 선택).
    public let tags: [String]
    public let cites: [Cite]
    /// 사건 참조 — 해석 객체가 근거로 삼은 사건 로그(events/*.ndjson) 의 event id 들.
    /// cite 와 달리 md 객체가 아니라 사건을 가리키므로 verify 의 참조 무결성 검사 대상이 아니다.
    /// 사실(fact)→해석(interpretation) 사슬이 여기로 이어진다(사건층은 별도 저장소).
    public let observes: [String]
    public let supersedes: String?
    public let retracts: String?
    /// 출처 provenance — 파일/URL 수집물의 구조화 기원 정보(선택). frontmatter 에 `source: {json}` 한 줄로.
    /// 원본이 어디서 왔고(path/project), 언제 쓰였고(authoredAt), 어떤 형식이며(kind), 원본 바이트를
    /// 어느 blob 에 봉인했는지(blob) 를 담는다. 무결성 sha 는 body 만 해싱하므로 이 블록은 검증에 영향 없다.
    public let source: Provenance?

    /// 저작 provenance — 이 객체를 무엇이 어떤 런타임·비용으로 썼나(`authoring: {json}`).
    /// source(내용의 출처)와 다른 축이다. 무결성 sha 는 body 만 해싱하므로 검증에 영향 없다.
    public let authoring: Authoring?
    /// 제5조 — 모르는 필드는 무시하되 보존한다.
    public let unknownFields: [String]
    public let body: String

    public struct Extras: Sendable, Equatable {
        public var batch: String? = nil
        public var origin: String? = nil
        public var tags: [String] = []
        public var cites: [Cite] = []
        public var observes: [String] = []
        public var supersedes: String? = nil
        public var retracts: String? = nil
        public var source: Provenance? = nil
        public var authoring: Authoring? = nil
        public var unknownFields: [String] = []
        public var ledger: Int = 2

        public init(
            batch: String? = nil,
            origin: String? = nil,
            tags: [String] = [],
            cites: [Cite] = [],
            observes: [String] = [],
            supersedes: String? = nil,
            retracts: String? = nil,
            source: Provenance? = nil,
            authoring: Authoring? = nil,
            unknownFields: [String] = [],
            ledger: Int = 2
        ) {
            self.batch = batch
            self.origin = origin
            self.tags = tags
            self.cites = cites
            self.observes = observes
            self.supersedes = supersedes
            self.retracts = retracts
            self.source = source
            self.authoring = authoring
            self.unknownFields = unknownFields
            self.ledger = ledger
        }
    }

    public init(
        id: String,
        published: Date,
        author: String,
        title: String? = nil,
        type: String? = nil,
        body: String,
        extras: Extras = Extras()
    ) {
        // 기본 2 — 신규 발행물은 content-addressed(제1조 v2). parse 는 저장값을 넘겨 구 v1(1)을 보존.
        self.ledger = extras.ledger
        self.id = id
        self.published = published
        self.author = author
        self.sha256 = Self.hash(body)
        self.title = title
        self.type = type
        self.batch = extras.batch
        self.origin = extras.origin
        self.tags = extras.tags
        self.cites = extras.cites
        self.observes = extras.observes
        self.supersedes = extras.supersedes
        self.retracts = extras.retracts
        self.source = extras.source
        self.authoring = extras.authoring
        self.unknownFields = extras.unknownFields
        self.body = body
    }

    public static func hash(_ body: String) -> String {
        SHA256.hash(data: Data(body.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// id 가 content-addressed(sha256 = 64자리 소문자 hex) 형식인가.
    /// 구 UUIDv7 id(대시 포함, 36자)와 구분해 마이그레이션 중 혼재를 안전히 다룬다.
    public static func isContentID(_ id: String) -> Bool {
        id.count == 64 && id.allSatisfy { $0.isHexDigit && ($0.isNumber || $0.isLowercase) }
    }

    // MARK: - 직렬화 (필드 순서 고정 — 결정적)

    /// 불변 코어 필드 — id·sha256 을 **제외한** 모든 태생 필드(published·author·본문 포함).
    /// content-addressed id = sha256(canonicalCore) 라 이 목록이 정체성의 정본이다.
    /// id 를 넣으면 자기참조 순환이 되고, sha256(본문해시)은 body 에서 파생이라 둘 다 뺀다
    /// (git object·nanopub trusty-URI 방식). 필드 순서는 serialize() 와 동일하게 고정.
    private func coreLines() -> [String] {
        var lines = ["ledger: \(ledger)",
                     "published: \(Self.isoFraction.string(from: published))",
                     "author: \(author)"]
        if let title { lines.append("title: \(title)") }
        if let type { lines.append("type: \(type)") }
        if let batch { lines.append("batch: \(batch)") }
        if let origin { lines.append("origin: \(origin)") }
        if !tags.isEmpty { lines.append("tags: [\(tags.joined(separator: ", "))]") }
        for cite in cites { lines.append("cite: \(cite.id) \(cite.rel)") }
        for eventID in observes { lines.append("observes: \(eventID)") }
        if let supersedes { lines.append("supersedes: \(supersedes)") }
        if let retracts { lines.append("retracts: \(retracts)") }
        if let source, let json = source.jsonLine { lines.append("source: \(json)") }
        // authoring 은 **코어가 아니다.** 토큰 수·세션 id 는 주장에 대한 관찰이지 주장
        // 자체가 아니라서, 같은 지식을 더 비싸게 썼다고 다른 객체가 되면 안 된다.
        // (sha256 줄을 코어에서 빼는 것과 같은 이유 — 파생·부수 정보는 정체성 밖.)
        lines.append(contentsOf: unknownFields)
        return lines
    }

    /// 해시 대상 바이트 — 코어 필드 + 본문. id·sha256 제외(순환 해결).
    public func canonicalCore() -> String {
        coreLines().joined(separator: "\n") + "\n---\n" + body
    }

    /// content-addressed id = sha256(canonicalCore). 정체성 = 주소 = 무결성.
    /// 해시 계산은 공유 코어에 위임(CitationLedgerObject.contentID 와 동일 결과).
    public func contentID() -> String { CitationLedger.sha256Hex(canonicalCore()) }

    public func serialize() -> String {
        var lines = ["---", "ledger: \(ledger)", "id: \(id)",
                     "published: \(Self.isoFraction.string(from: published))",
                     "author: \(author)", "sha256: \(sha256)"]
        var core = coreLines()
        core.removeFirst(3)  // ledger·published·author 는 위에서 이미(id·sha256 사이 순서 유지)
        lines.append(contentsOf: core)
        // 코어 밖 필드 — 저장은 하되 정체성에는 안 넣는다(sha256 줄과 같은 자리).
        if let authoring, let json = authoring.jsonLine { lines.append("authoring: \(json)") }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + body
    }

    public static func parse(_ text: String) -> (object: LedgerObject, storedSHA: String)? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.first == "---",
              let closing = lines.dropFirst().firstIndex(of: "---") else { return nil }

        var fields: [String: String] = [:]
        var cites: [Cite] = []
        var observes: [String] = []
        var unknown: [String] = []
        for line in lines[1..<closing] {
            guard let colon = line.firstIndex(of: ":") else {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty { unknown.append(line) }
                continue
            }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "cite":
                let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
                guard let citeID = parts.first else { continue }
                cites.append(Cite(id: citeID, rel: parts.count > 1 ? parts[1] : "cites"))
            case "observes":
                // 사건 참조 — 값은 event id. 공백 뒤 부가정보가 붙어도 첫 토큰만 취한다.
                if let eventID = value.split(separator: " ", maxSplits: 1).first.map(String.init),
                   !eventID.isEmpty { observes.append(eventID) }
            case "tags":
                var inner = value
                if inner.hasPrefix("[") && inner.hasSuffix("]") { inner = String(inner.dropFirst().dropLast()) }
                fields["tags"] = inner
            case "source":
                fields["source"] = value  // {json} — 아래에서 디코드
            case "authoring":
                fields["authoring"] = value  // {json} — 저작 provenance
            case "ledger", "id", "published", "author", "sha256",
                 "title", "type", "batch", "origin", "supersedes", "retracts":
                fields[key] = value
            default:
                unknown.append(line)  // 제5조 — 보존
            }
        }

        guard let id = fields["id"], !id.isEmpty,
              let publishedRaw = fields["published"],
              let published = iso.date(from: publishedRaw) ?? isoFraction.date(from: publishedRaw),
              let author = fields["author"], !author.isEmpty,
              let storedSHA = fields["sha256"] else { return nil }

        let body = lines[(closing + 1)...].joined(separator: "\n")
        let object = LedgerObject(
            id: id, published: published, author: author,
            title: fields["title"], type: fields["type"], body: body,
            extras: LedgerObject.Extras(
                batch: fields["batch"], origin: fields["origin"],
                tags: (fields["tags"] ?? "").split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }.filter { !$0.isEmpty },
                cites: cites, observes: observes,
                supersedes: fields["supersedes"], retracts: fields["retracts"],
                source: Provenance(jsonLine: fields["source"]),
                authoring: Authoring(jsonLine: fields["authoring"]),
                unknownFields: unknown,
                ledger: fields["ledger"].flatMap(Int.init) ?? 1))  // 구 v1 파일은 1로 남는다
        return (object, storedSHA)
    }

    // 시간 포매터는 공유 코어의 단일 인스턴스를 재사용(정의 중복 제거 — forge 와 동일).
    nonisolated(unsafe) public static let iso = CitationLedger.iso
    nonisolated(unsafe) public static let isoFraction = CitationLedger.isoFraction
}

/// 공유 원장 프로토콜 채택 — canonicalCore() 가 요구사항을 이미 충족한다.
/// 이로써 LedgerObject 는 forge ForgeObject 와 같은 계약을 만족(교차 도구·검증 공유 기반).
extension LedgerObject: CitationLedgerObject {}

/// 출처 provenance — 수집물의 구조화 기원. frontmatter 에 `source: {json}` 한 줄로 직렬화된다.
/// 필드는 전부 선택 — 아는 만큼만 채운다. 키 순서 고정으로 결정적 직렬화.
public struct Provenance: Sendable, Equatable {
    public var kind: String?        // pdf | audio | web | text | image
    public var path: String?        // 원본 위치 — 파일 절대경로 또는 URL
    public var project: String?     // 프로젝트(그룹) — 필터·묶기 단위
    public var authoredAt: String?  // 원문 작성일 (ISO 날짜/일시) — 자동추출 또는 수동
    public var blob: String?        // 원본 바이트를 봉인한 blob sha256

    public init(kind: String? = nil, path: String? = nil, project: String? = nil,
                authoredAt: String? = nil, blob: String? = nil) {
        self.kind = kind; self.path = path; self.project = project
        self.authoredAt = authoredAt; self.blob = blob
    }

    /// 하나라도 값이 있으면 provenance 로 친다(전부 nil 이면 없는 것과 같음).
    public var isEmpty: Bool { kind == nil && path == nil && project == nil && authoredAt == nil && blob == nil }

    /// `{json}` 한 줄로 — 키 순서 고정. 값이 없는 키는 생략.
    public var jsonLine: String? {
        if isEmpty { return nil }
        var parts: [String] = []
        func add(_ k: String, _ v: String?) {
            guard let v, !v.isEmpty else { return }
            let escaped = v.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            parts.append("\"\(k)\":\"\(escaped)\"")
        }
        add("kind", kind); add("path", path); add("project", project)
        add("authoredAt", authoredAt); add("blob", blob)
        return parts.isEmpty ? nil : "{" + parts.joined(separator: ",") + "}"
    }

    /// `source:` 값(JSON) 을 디코드. 실패하면 nil(제5조 — 깨진 provenance 로 객체 로딩을 막지 않는다).
    public init?(jsonLine: String?) {
        guard let jsonLine, let data = jsonLine.data(using: .utf8) else { return nil }
        let obj: [String: String]
        do {
            guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: String] else { return nil }
            obj = parsed
        } catch {
            return nil
        }
        guard !obj.isEmpty else { return nil }
        self.init(kind: obj["kind"], path: obj["path"], project: obj["project"],
                  authoredAt: obj["authoredAt"], blob: obj["blob"])
    }
}

/// UUIDv7 — 앞 48비트가 밀리초 타임스탬프라 정렬 = 시간 정렬. content-addressed 객체
/// id 는 아니고, batch 등 실행 식별자용. 구현은 공유 코어에 위임(forge 와 동일).
public enum LedgerID {
    public static func generate(now: Date = Date()) -> String {
        CitationLedger.uuidV7(now: now)
    }
}

extension LedgerObject {
    /// OKF type — 명시 type 이 없으면 제목 접두어에서 유도(구 객체 호환).
    public var effectiveType: String? {
        if let type { return type }
        guard let title else { return nil }
        let normalized = title.precomposedStringWithCanonicalMapping
        if normalized == "색인" { return "index" }
        let prefixMap: [(String, String)] = [
            ("플레이북:", "playbook"),
            ("근거:", "evidence"), ("개념:", "concept"), ("엔티티:", "entity"),
            ("선별:", "screening"), ("분류:", "classification"), ("결정:", "decision"),
            ("체크포인트:", "checkpoint"), ("run:", "run"), ("중복쌍:", "duplicate"),
            ("재확인:", "reverification"), ("재현:", "reproduction"), ("반박:", "refutation"),
            ("역할정의:", "role-definition"), ("이의:", "objection"), ("질문:", "question"), ("수정요청:", "edit-request"),
            ("회고:", "retrospective"),
            ("scene:", "scene-evidence"), ("현장근거:", "scene-evidence"),
        ]
        for (prefix, type) in prefixMap where normalized.hasPrefix(prefix) { return type }
        return nil
    }
}

extension LedgerObject {
    /// 작업 절차 발행물 — 지식이 아니라 "처리 기록"인 type 들. CLI·앱·인덱스 공용 단일 기준.
    /// ⚠ 이 집합이 유일한 정본이다 — SQL 필터도 processTypesSQL 로 여기서 파생한다(중복 금지).
    public static let processTypes: Set<String> = [
        "screening", "classification", "run", "checkpoint",
        "duplicate", "reverification", "reproduction", "refutation",
        "objection", "question", "edit-request", "role-definition",
        "review",  // 사람 심사 판정(수락/반려) — 사건성 스탬프라 내 기록·근거에 안 샌다.
        "policy",  // 운영 정책 선언(분류 기준선 등) — 지식이 아니라 규칙이라 스스로 분류 대상이 아니다.
        "scene-evidence",  // 결정의 현장 근거 첨부 — 결정을 통해 도달하는 부속 기록이라 스스로 분류 대상이 아니다.
    ]

    /// SQL `IN (...)` 절에 넣을 처리-type 리터럴 목록 — processTypes 에서 기계 생성.
    /// 정렬 고정으로 결정적. LedgerIndex.search 가 하드코딩 대신 이걸 쓴다.
    public static let processTypesSQL: String =
        processTypes.sorted().map { "'\($0)'" }.joined(separator: ",")

    /// 사실(fact) — 기계적·관측 기록. 에이전트 무관하고 재현 가능(사건층의 md 대응물).
    /// processTypes 의 부분집합. 사건 로그(events/*.ndjson) 이전의 거친 요약 스탬프.
    public static let factTypes: Set<String> = ["run", "checkpoint", "screening", "duplicate"]

    /// 해석(interpretation) — 에이전트 판단. 같은 사실에서 author 마다 결과가 갈리고
    /// supersedes·반박으로 경합·버전된다. processTypes 의 부분집합.
    public static let interpretationTypes: Set<String> =
        ["classification", "reverification", "reproduction", "refutation", "objection"]

    /// 지식인가(검색·근거 목록 대상) — 결정(decision)은 지식이다.
    public var isProcess: Bool {
        guard let type = effectiveType else { return false }
        return Self.processTypes.contains(type)
    }

    /// 기계적 사실 기록인가(에이전트 무관·재현 가능).
    public var isFact: Bool {
        guard let type = effectiveType else { return false }
        return Self.factTypes.contains(type)
    }

    /// 에이전트 판단(해석)인가 — 같은 사실에서 author 마다 결과가 다를 수 있다.
    public var isInterpretation: Bool {
        guard let type = effectiveType else { return false }
        return Self.interpretationTypes.contains(type)
    }

    /// screens 분류 스탬프 본문에서 domain/kind/knowledge 를 뽑는다.
    /// in-memory(LedgerClassification)와 SQL(LedgerIndex) 양쪽이 공유하는 단일 파서.
    public static func parseClassification(_ body: String)
        -> (domain: String?, kind: String?, knowledge: String?) {
        var domain: String?, kind: String?, knowledge: String?
        for line in body.split(separator: "\n") {
            if line.hasPrefix("domain: ") { domain = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("kind: ") { kind = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
            if line.hasPrefix("knowledge: ") { knowledge = String(line.dropFirst(11)).trimmingCharacters(in: .whitespaces) }
        }
        return (domain, kind, knowledge)
    }
}

/// 사람이 근거와 함께 부여하는 3축 분류 입력.
/// 원문 객체는 불변이라 이 값은 항상 별도 `선별:` 객체의 본문으로 발행된다.
public struct LedgerClassificationInput: Sendable, Hashable {
    public static let domains = [
        "agent-memory-ssot", "agent-orchestration", "infra-hosting", "secrets-identity",
        "gujo-commerce", "macos-apps", "media-ai-pipeline", "dev-workflow"
    ]
    public static let kinds = ["runbook", "decision", "incident", "overview", "reference", "note", "evaluation"]
    public static let knowledgeKinds = ["tech", "domain", "preference"]

    public let domain: String
    public let kind: String
    public let knowledge: String
    public let reason: String

    public init?(domain: String, kind: String, knowledge: String, reason: String) {
        let normalizedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedKnowledge = knowledge.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.domains.contains(normalizedDomain),
              Self.kinds.contains(normalizedKind),
              Self.knowledgeKinds.contains(normalizedKnowledge),
              !normalizedReason.isEmpty
        else { return nil }
        self.domain = normalizedDomain
        self.kind = normalizedKind
        self.knowledge = normalizedKnowledge
        self.reason = normalizedReason
    }

    public var screeningBody: String {
        """
        domain: \(domain)
        kind: \(kind)
        knowledge: \(knowledge)
        status: 유효
        근거: \(reason)
        """
    }
}

/// 분류 스탬프(rel=screens)의 domain/kind/knowledge 를 계보 head 로 승격한 인덱스.
/// CLI 와 앱이 같은 구현을 쓴다 — 분류 조회가 갈라지지 않게.
public struct LedgerClassification: Sendable {
    public let domain: [String: String]
    public let kind: [String: String]
    public let knowledge: [String: String]

    public init(objects: [LedgerObject]) {
        var successorOf: [String: String] = [:]
        for object in objects {
            if let old = object.supersedes { successorOf[old] = object.id }
        }
        var domains: [String: String] = [:]
        var kinds: [String: String] = [:]
        var knowledges: [String: String] = [:]
        for stamp in Self.activeScreenings(objects: objects) {
            let (domain, kind, knowledge) = LedgerObject.parseClassification(stamp.body)
            guard domain != nil || kind != nil || knowledge != nil else { continue }
            for cite in stamp.cites where cite.rel == "screens" {
                var current = cite.id
                while let next = successorOf[current] { current = next }
                if let domain { domains[current] = domain }
                if let kind { kinds[current] = kind }
                if let knowledge { knowledges[current] = knowledge }
            }
        }
        self.domain = domains
        self.kind = kinds
        self.knowledge = knowledges
    }

    /// 선별 자체도 append-only 개정 대상이다. supersede·retract 된 옛 선별이 최신
    /// 분류를 덮어쓰지 않도록 현재 head 만 분류 투영에 사용한다.
    public static func activeScreenings(objects: [LedgerObject]) -> [LedgerObject] {
        let superseded = Set(objects.compactMap(\.supersedes))
        let retracted = Set(objects.compactMap(\.retracts))
        return objects.filter {
            $0.effectiveType == "screening"
                && !superseded.contains($0.id)
                && !retracted.contains($0.id)
                && $0.retracts == nil
                && $0.cites.contains(where: { $0.rel == "screens" })
        }
    }
}
