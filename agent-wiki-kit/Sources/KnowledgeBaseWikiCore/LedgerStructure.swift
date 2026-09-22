import Foundation

/// 원장의 **저장 구조와 층 사이 배선 완성도**를 실측한다.
///
/// 원장은 3층이다 — 봉인(blobs, 원문 바이트) · 해석(objects·events, 인용 그래프) ·
/// 파생(state, 언제든 재구성 가능한 캐시). 각 층은 있는데 **층을 잇는 배선이 빠져도
/// 아무 명령이 실패하지 않는다**: 원문은 봉인됐고 객체는 발행됐는데 아무도 못 찾거나,
/// gc 가 살아있는 원본을 회수 대상으로 보는 식으로 조용히 어긋난다.
///
/// 그래서 여기서는 **간선을 센다.** 수치는 전부 실측(디스크·인덱스·객체 본문)이고,
/// "무엇이 이어져 있어야 하는가"라는 기준선만 `Edge.contract` 로 한 번 선언한다.
/// 그 선언이 이 파일의 유일한 사람 판단이며, 나머지는 원장이 답한다.
public struct LedgerStructure: Sendable, Codable {

    /// 간선이 기준선을 만족하는가. 비율이 아니라 판정 — 화면·CI 가 같은 걸 본다.
    public enum Status: String, Sendable, Codable {
        case satisfied   // 기준선 충족
        case partial     // 일부만 이어짐
        case missing     // 배선 자체가 없음
    }

    /// 기준선의 성격. 같은 미달이라도 무게가 다르다.
    public enum Contract: String, Sendable, Codable {
        case invariant      // 깨지면 결함 — 데이터 유실이나 조용한 오답이 난다
        case goal           // 설계 의도 — 미달은 미완성이지 고장은 아니다
        case informational  // 판정하지 않는다 — 관측만
    }

    public struct Layer: Sendable, Codable {
        public let id: String
        public let name: String
        public let role: String
        public let files: Int
        public let bytes: Int
        public let notes: [String]
    }

    public struct Edge: Sendable, Codable {
        public let id: String
        public let from: String
        public let to: String
        public let label: String
        public let actual: Int
        public let total: Int
        public let contract: Contract
        public let note: String

        public var ratio: Double { total == 0 ? 1 : Double(actual) / Double(total) }

        public var status: Status {
            if total == 0 { return .satisfied }       // 셀 게 없으면 어긋날 수도 없다
            if actual == total { return .satisfied }
            return actual == 0 ? .missing : .partial
        }
    }

    /// 백로그 한 줄 — 화면이 숫자만 보여주면 손댈 수가 없다. 어떤 객체인지, 그리고
    /// 눌러서 갈 수 있어야 처리로 이어진다.
    public struct Pending: Sendable, Codable {
        /// 무엇이 모자란가 — 처리 방법이 달라서 구분한다.
        public enum Lack: String, Sendable, Codable {
            case classification   // 3축 분류 없음
            case citation         // 인용 그래프에서 고립
        }
        public let id: String
        public let title: String
        public let author: String
        public let published: Date
        /// 기준선 이후 = 게이트 위반, 이전 = 부채.
        public let gated: Bool
        public let lack: Lack
    }

    public let layers: [Layer]
    public let edges: [Edge]

    /// 미분류 지식 — 게이트 위반 먼저, 그다음 부채(최근 것부터).
    /// 화면이 다 그리지 못할 만큼 많을 수 있어 상한을 둔다(숫자는 간선이 정확히 센다).
    public let pending: [Pending]
    public static let pendingLimit = 200

    /// 기준선이 걸린 간선(invariant·goal) 중 충족된 수 — 화면 상단 한 줄.
    public var completion: (satisfied: Int, required: Int) {
        let required = edges.filter { $0.contract != .informational }
        return (required.filter { $0.status == .satisfied }.count, required.count)
    }

    /// 지금 손대야 하는 것 — invariant 위반 먼저, 그다음 goal 미달.
    public var breaches: [Edge] {
        edges
            .filter { $0.contract != .informational && $0.status != .satisfied }
            .sorted { lhs, rhs in
                if (lhs.contract == .invariant) != (rhs.contract == .invariant) {
                    return lhs.contract == .invariant
                }
                return lhs.ratio < rhs.ratio
            }
    }

    // MARK: - 실측

    public init(root: URL) {
        let store = LedgerStore(root: root)
        let blobs = BlobStore(root: root)
        let objectsDir = root.appendingPathComponent("objects")

        let objects = store.scan()
        let events = EventLog(root: root).all()
        let blobSHAs = Set(blobs.allSHAs())

        // --- 봉인층: 누가 이 원본을 가리키는가 ---------------------------------
        // typed  — `source.blob` 필드. 기계가 따라갈 수 있는 유일한 경로.
        // 본문   — 본문 아무 데나 적힌 sha. 사람은 읽지만 gc·역참조는 못 본다.
        let typedRefs = Set(objects.compactMap { $0.source?.blob }).intersection(blobSHAs)
        let eventRefs = Set(events.compactMap(\.source)).intersection(blobSHAs)
        let bodyRefs = Self.shasMentioned(in: objects, among: blobSHAs)
        // gc 가 실제로 살려두는 집합 — `blob gc` 와 **같은 정의여야 한다**(다르면 이 화면이
        // 거짓말을 한다). 사건 source ∪ 객체 source.blob ∪ 객체 본문의 sha.
        let gcReachable = typedRefs.union(eventRefs).union(bodyRefs)

        let textBlobs = blobSHAs.filter { blobs.kind($0)?.label == "텍스트" }
        let blobBytes = blobSHAs.reduce(0) { $0 + (blobs.size($1) ?? 0) }

        // --- 파생층 ------------------------------------------------------------
        let indexPath = root.appendingPathComponent("state/index.db")
        let hasIndex = FileManager.default.fileExists(atPath: indexPath.path)
        let index = hasIndex ? LedgerIndex(root: root) : nil
        let ftsRows = index?.ftsObjectRowCount() ?? 0
        let stale = index?.isStale(objectsDir: objectsDir) ?? false
        // 원문이 검색에 닿는지 — blob sha 가 fts 행 id 로 있는가. 지금은 색인 경로가
        // 없어 0 이지만, 생기면 이 수치가 저절로 올라간다(선언이 아니라 측정이다).
        let ftsBlobRows = index.map { idx in textBlobs.filter { idx.ftsContains(id: $0) }.count } ?? 0
        let graphCounts = LedgerGraph(root: root).counts()

        // --- 분류 백로그 ------------------------------------------------------
        let policy = LedgerClassificationPolicy.current(objects: objects, store: store)
        let classified = Set(LedgerClassification(objects: objects).domain.keys)
        let superseded = Set(objects.compactMap(\.supersedes))
        let retracted = Set(objects.compactMap(\.retracts))
        let knowledge = objects.filter {
            !$0.isProcess && $0.retracts == nil
                && !superseded.contains($0.id) && !retracted.contains($0.id)
        }
        let gated = policy.since.map { since in knowledge.filter { $0.published > since } } ?? []
        let legacy = policy.since.map { since in knowledge.filter { $0.published <= since } } ?? knowledge
        // --- 인용 고립 --------------------------------------------------------
        // 아무도 안 가리키고 아무것도 안 가리키는 지식은 원장 안에 있어도 **길이 없다.**
        // 검색으로 이름을 정확히 알 때만 닿고, 관련 근거를 따라 걷다가는 절대 못 만난다.
        // 기준선 평가(ee696d03)가 355개(24.4%)로 지적한 그 축이다.
        // **처리 객체의 인용은 세지 않는다.** 선별 스탬프는 대상을 `screens` 로 가리키므로,
        // 그걸 연결로 치면 분류만 해도 전부 이어진 것처럼 보인다(테스트가 잡은 결함).
        // 걸어서 닿는다는 건 지식에서 지식으로 이어진다는 뜻이다.
        var connected: Set<String> = []
        for object in objects where !object.isProcess {
            for cite in object.cites {
                connected.insert(object.id)
                connected.insert(cite.id)
            }
        }
        let isolatedObjects = knowledge.filter { !connected.contains($0.id) }

        let gatedTotal = gated.count
        let gatedPending = gated.filter { !classified.contains($0.id) }.count
        let legacyTotal = legacy.count
        let legacyPending = legacy.filter { !classified.contains($0.id) }.count
        let baselineNote = policy.since.map {
            "기준선 \(LedgerObject.iso.string(from: $0)) 이후 발행 지식은 3축 분류를 갖춰야 한다. "
                + "`verify` 가 게이트로 집행한다."
        } ?? "기준선 미선언 — 분류가 요구되지 않는다."

        self.layers = [
            Layer(
                id: "blobs", name: "blobs/<앞2자>/<sha256>", role: "봉인 — 원문 바이트",
                files: blobSHAs.count, bytes: blobBytes,
                notes: [
                    "write-once · sha256 이 곧 이름이라 위조가 드러난다",
                    "정본 — 지우면 복구 불가",
                    "텍스트 \(textBlobs.count)개",
                ]),
            Layer(
                id: "objects", name: "objects/YYYY/MM/<sha>.md", role: "해석 — 인용 그래프",
                files: objects.count, bytes: Self.bytes(of: objectsDir),
                notes: [
                    "append-only · 고침은 supersede, 철회는 retract",
                    "인용 \(objects.reduce(0) { $0 + $1.cites.count })간선",
                ]),
            Layer(
                id: "events", name: "events/YYYY-MM/*.ndjson", role: "해석 — 사건 로그",
                files: Self.fileCount(of: root.appendingPathComponent("events")),
                bytes: Self.bytes(of: root.appendingPathComponent("events")),
                notes: ["사건 \(events.count)건", "source 필드로 blob 을 가리킨다"]),
            Layer(
                id: "state", name: "state/*.db", role: "파생 — 캐시",
                files: Self.fileCount(of: root.appendingPathComponent("state")),
                bytes: Self.bytes(of: root.appendingPathComponent("state")),
                notes: [
                    "index.db: objects·cites·files·fts5",
                    "graph.db: 노드 \(graphCounts.nodes) · 간선 \(graphCounts.edges)",
                    "md 에서 언제든 재구성 가능 — 정본 아님",
                ]),
        ]

        let pendingGated = gated.filter { !classified.contains($0.id) }
        let pendingLegacy = legacy.filter { !classified.contains($0.id) }
        self.pending = (
            pendingGated.sorted { $0.published > $1.published }.map {
                Pending(id: $0.id, title: $0.title ?? "(무제)", author: $0.author,
                        published: $0.published, gated: true, lack: .classification)
            }
            + pendingLegacy.sorted { $0.published > $1.published }.map {
                Pending(id: $0.id, title: $0.title ?? "(무제)", author: $0.author,
                        published: $0.published, gated: false, lack: .classification)
            }
            // 고립은 분류와 별개 부채다 — 분류가 돼 있어도 길이 없을 수 있다.
            + isolatedObjects.sorted { $0.published > $1.published }.map {
                Pending(id: $0.id, title: $0.title ?? "(무제)", author: $0.author,
                        published: $0.published, gated: false, lack: .citation)
            }
        ).prefix(Self.pendingLimit).map { $0 }

        self.edges = [
            Edge(id: "blob-reachable", from: "blobs", to: "objects+events",
                 label: "gc 가 살려두는 원본",
                 actual: gcReachable.count, total: blobSHAs.count,
                 contract: .invariant,
                 note: "`blob gc` 와 같은 정의 — 사건 source ∪ 객체 source.blob ∪ 본문의 sha. "
                     + "여기 없는 blob 은 회수 대상이고, blob 은 정본이라 복구할 수 없다."),

            // 이 둘은 **판정하지 않는다.** 한때 "typed 로 옮겨야 할 미완성"으로 셌는데,
            // 실제 결함은 데이터가 아니라 읽는 쪽이었다 — 색인이 본문의 sha 를 안 읽어서
            // 참조가 없는 것처럼 보였을 뿐이다. 이제 둘 다 색인돼 gc·역참조가 따라간다.
            // 게다가 `source.blob` 은 단수라 그림 여러 장을 안은 문서(실측 13건)를
            // 애초에 담지 못한다 — 전부 typed 로 모는 건 스키마상 불가능하다.
            // 남는 구분은 성격이다: typed 는 "이 객체는 이 원본의 수집물", 본문은
            // "이 문서가 이 원본들을 인용".
            Edge(id: "blob-typed", from: "blobs", to: "objects",
                 label: "수집 provenance (source.blob)",
                 actual: typedRefs.count, total: blobSHAs.count,
                 contract: .informational,
                 note: "capture 로 들어온 수집물의 정식 provenance. 객체당 하나만 담긴다."),

            Edge(id: "blob-body", from: "blobs", to: "objects",
                 label: "문서 인용 (본문 sha)",
                 actual: bodyRefs.count, total: blobSHAs.count,
                 contract: .informational,
                 note: "문서가 원본을 인용하는 형태. 색인이 파싱해 역참조·gc 가 따라간다."),

            Edge(id: "blob-event", from: "blobs", to: "events",
                 label: "사건 참조 (source)",
                 actual: eventRefs.count, total: blobSHAs.count,
                 contract: .informational,
                 note: "모든 원본이 사건에서 나오지는 않는다 — 판정하지 않는다."),

            Edge(id: "blob-fts", from: "blobs", to: "state/fts5",
                 label: "원문 검색 도달",
                 actual: ftsBlobRows, total: textBlobs.count,
                 contract: .goal,
                 note: "텍스트 원본이 FTS 에 색인되지 않으면, 봉인은 됐어도 검색으로는 "
                     + "찾을 수 없다. 지금은 색인 경로 자체가 없다."),

            Edge(Edge(id: "object-fts", from: "objects", to: "state/fts5",
                 label: "객체 검색 도달",
                 actual: min(ftsRows, objects.count), total: objects.count,
                 contract: .invariant,
                 note: "md 객체는 전부 색인돼야 한다. 모자라면 발행한 지식을 못 찾는다."),
                 // 인덱스가 없는 원장은 스캔 폴백이라 결함이 아니다 — 검사에서 뺀다.
                 // (실행해보고 알았다: repo `.wiki` 처럼 인덱스를 안 만든 원장에서
                 //  "0/35 미달"이라는 거짓 경보가 떴다.)
                 skipWhen: !hasIndex),

            Edge(Edge(id: "index-fresh", from: "objects", to: "state/index.db",
                 label: "인덱스 신선도",
                 actual: stale ? 0 : 1, total: 1,
                 contract: .invariant,
                 note: stale
                     ? "인덱스가 디스크보다 뒤처졌다 — `index sync` 로 맞춘다."
                     : "디스크와 일치."),
                 // 인덱스가 아예 없으면 스캔 폴백이라 결함은 아니다.
                 skipWhen: !hasIndex),

            Edge(Edge(id: "classification-baseline", from: "objects", to: "선별",
                 label: "기준선 이후 분류",
                 actual: gatedTotal - gatedPending, total: gatedTotal,
                 contract: .invariant,
                 note: baselineNote),
                 // 기준선이 없으면 요구 자체가 없다 — 해당 없는 검사를 위반으로 세지 않는다.
                 skipWhen: policy.since == nil),

            Edge(id: "classification-legacy", from: "objects", to: "선별",
                 label: "기준선 이전 분류(부채)",
                 actual: legacyTotal - legacyPending, total: legacyTotal,
                 contract: .informational,
                 note: "기준선 이전 발행분. 갚으면 검색 정밀도가 오르지만 도달률과는 "
                     + "무관하다 — 미분류도 FTS 에는 잡힌다."),

            Edge(id: "citation-reach", from: "objects", to: "objects",
                 label: "인용 그래프 연결",
                 actual: knowledge.count - isolatedObjects.count, total: knowledge.count,
                 contract: .goal,
                 note: "인용이 하나도 없는 지식은 원장 안에 있어도 걸어서 닿을 수 없다 — "
                     + "이름을 정확히 알 때만 검색으로 나온다. 상위 개념이나 근거에 "
                     + "최소 1개로 이어 준다."),

            Edge(Edge(id: "graph-objects", from: "objects", to: "state/graph.db",
                 label: "그래프 노드",
                 actual: min(graphCounts.nodes, objects.count), total: objects.count,
                 contract: .goal,
                 note: "graph rebuild 를 돌리지 않으면 관계도가 옛 상태로 남는다."),
                 // 그래프를 한 번도 안 만든 원장에 "미달"을 씌우지 않는다.
                 skipWhen: graphCounts.nodes == 0 && objects.isEmpty),
        ].compactMap { $0 }
    }

    // MARK: - 도우미

    /// 본문 어딘가에 등장하는 blob sha — 64자 소문자 hex 만 후보로 본다.
    private static func shasMentioned(in objects: [LedgerObject], among known: Set<String>) -> Set<String> {
        guard !known.isEmpty else { return [] }
        var found: Set<String> = []
        for object in objects {
            let body = object.body
            guard body.count >= 64 else { continue }
            for sha in known where !found.contains(sha) {
                if body.contains(sha) { found.insert(sha) }
            }
            if found.count == known.count { break }
        }
        return found
    }

    private static func fileCount(of dir: URL) -> Int {
        guard let en = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return 0 }
        var n = 0
        for case let url as URL in en where !url.hasDirectoryPath { n += 1 }
        return n
    }

    private static func bytes(of dir: URL) -> Int {
        guard let en = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total = 0
        for case let url as URL in en {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return total
    }
}

extension LedgerStructure.Edge {
    /// `skipWhen` 이 참이면 간선을 아예 만들지 않는다 — 해당 없는 검사를 위반으로
    /// 세지 않기 위해서다(인덱스 없는 원장에서 "신선도 미달"은 거짓 경보).
    init?(_ edge: LedgerStructure.Edge, skipWhen skip: Bool) {
        guard !skip else { return nil }
        self = edge
    }
}
