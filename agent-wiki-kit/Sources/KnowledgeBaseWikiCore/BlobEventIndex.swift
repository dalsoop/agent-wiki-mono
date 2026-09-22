import Foundation

/// 파생 blob↔event 인덱스 — world `state/blob-event-index.json` (재구성 가능).
/// sha → 참조 event id 목록, event 필터(subject/rel/source).
public struct BlobEventIndex: Sendable {
    public struct Record: Codable, Sendable, Equatable {
        public var sha: String
        public var eventIDs: [String]
        public var size: Int?
        public var kindLabel: String?

        public init(sha: String, eventIDs: [String], size: Int? = nil, kindLabel: String? = nil) {
            self.sha = sha
            self.eventIDs = eventIDs
            self.size = size
            self.kindLabel = kindLabel
        }
    }

    public struct Snapshot: Codable, Sendable, Equatable {
        public var version: Int
        public var records: [Record]
        public var events: [EventRow]

        public init(version: Int = 1, records: [Record] = [], events: [EventRow] = []) {
            self.version = version
            self.records = records
            self.events = events
        }
    }

    public struct EventRow: Codable, Sendable, Equatable {
        public var id: String
        public var subject: String
        public var rel: String
        public var source: String?
        public var level: String
        public var outcome: String?

        public init(from e: Event) {
            self.id = e.id
            self.subject = e.subject
            self.rel = e.rel
            self.source = e.source
            self.level = e.level.rawValue
            self.outcome = e.outcome?.rawValue
        }
    }

    public let root: URL
    private var indexURL: URL {
        root.appendingPathComponent("state/blob-event-index.json")
    }

    public init(root: URL) { self.root = root }

    public func rebuild() throws -> Snapshot {
        let log = EventLog(root: root)
        let blobs = BlobStore(root: root)
        let events = log.all()
        var bySHA: [String: [String]] = [:]
        for e in events {
            guard let sha = e.source else { continue }
            bySHA[sha, default: []].append(e.id)
        }
        // also include unreferenced blobs on disk
        for sha in blobs.allSHAs() where bySHA[sha] == nil {
            bySHA[sha] = []
        }
        let records = bySHA.keys.sorted().map { sha -> Record in
            Record(
                sha: sha,
                eventIDs: bySHA[sha] ?? [],
                size: blobs.size(sha),
                kindLabel: blobs.kind(sha)?.label
            )
        }
        let snap = Snapshot(
            version: 1,
            records: records,
            events: events.map(EventRow.init(from:))
        )
        try FileManager.default.createDirectory(
            at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(snap).write(to: indexURL, options: .atomic)
        return snap
    }

    public func load() throws -> Snapshot {
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            return try rebuild()
        }
        let data = try Data(contentsOf: indexURL)
        return try JSONDecoder().decode(Snapshot.self, from: data)
    }

    public func ensureFresh() throws -> Snapshot {
        // cheap: rebuild if missing; always rebuild is fine for modest event counts
        if !FileManager.default.fileExists(atPath: indexURL.path) {
            return try rebuild()
        }
        return try load()
    }

    public func eventsReferencing(sha: String) throws -> [EventRow] {
        let snap = try ensureFresh()
        guard let rec = snap.records.first(where: { $0.sha == sha }) else { return [] }
        let idSet = Set(rec.eventIDs)
        return snap.events.filter { idSet.contains($0.id) }
    }

    public func filterEvents(
        subject: String? = nil,
        rel: String? = nil,
        source: String? = nil
    ) throws -> [EventRow] {
        let snap = try ensureFresh()
        return snap.events.filter { e in
            if let subject, !e.subject.contains(subject) && !e.subject.hasPrefix(subject) {
                return false
            }
            if let rel, e.rel != rel { return false }
            if let source, e.source != source { return false }
            return true
        }
    }

    public func listBlobs() throws -> [Record] {
        try ensureFresh().records
    }
}
