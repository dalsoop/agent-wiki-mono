import Foundation

public struct FleetPullResult: Codable, Sendable, Equatable {
    public var agent: String
    public var query: String?
    public var maxObjects: Int
    public var truncated: Bool
    public var items: [FleetPullItem]
    public var events: [FleetPullEvent]?
    public var blobShas: [String]?
    public var blobDenied: Bool?

    public init(
        agent: String,
        query: String? = nil,
        maxObjects: Int,
        truncated: Bool,
        items: [FleetPullItem],
        events: [FleetPullEvent]? = nil,
        blobShas: [String]? = nil,
        blobDenied: Bool? = nil
    ) {
        self.agent = agent
        self.query = query
        self.maxObjects = maxObjects
        self.truncated = truncated
        self.items = items
        self.events = events
        self.blobShas = blobShas
        self.blobDenied = blobDenied
    }
}

public struct FleetPullItem: Codable, Sendable, Equatable {
    public var world: String
    public var id: String
    public var title: String?
    public var score: Double?
    public var snippet: String
    public var body: String?

    public init(
        world: String, id: String, title: String?, score: Double?,
        snippet: String, body: String?
    ) {
        self.world = world
        self.id = id
        self.title = title
        self.score = score
        self.snippet = snippet
        self.body = body
    }
}

public struct FleetPullEvent: Codable, Sendable, Equatable {
    public var id: String
    public var subject: String
    public var rel: String
    public var level: String
    public var parent: String?
    public var source: String?
    public var outcome: String?

    public init(from event: Event) {
        self.id = event.id
        self.subject = event.subject
        self.rel = event.rel
        self.level = event.level.rawValue
        self.parent = event.parent
        self.source = event.source
        self.outcome = event.outcome?.rawValue
    }
}

public struct FleetPull: Sendable {
    public static let maxObjectsLimit = 100

    public static func clampedMaxObjects(_ requested: Int) -> Int {
        min(max(1, requested), maxObjectsLimit)
    }

    public var query: FleetQuery
    public var profile: AgentProfile
    public var registry: FleetRegistry

    public init(registry: FleetRegistry, profile: AgentProfile) {
        self.registry = registry
        self.profile = profile
        self.query = FleetQuery(registry: registry, profile: profile)
    }

    public func byQuery(_ text: String, includeBody: Bool = true) -> FleetPullResult {
        let maxN = Self.clampedMaxObjects(profile.pull.maxObjects)
        // fetch one extra to know truncation
        let hits = query.search(query: text, limit: maxN + 1)
        let truncated = hits.count > maxN
        let slice = Array(hits.prefix(maxN))
        let bodyLimit = max(0, profile.pull.bodyChars)
        let items: [FleetPullItem] = slice.map { hit in
            var body: String?
            if includeBody, let obj = query.loadObject(world: hit.world, id: hit.id) {
                body = truncate(obj.body, limit: bodyLimit)
            }
            return FleetPullItem(
                world: hit.world, id: hit.id, title: hit.title,
                score: hit.score, snippet: hit.snippet, body: body)
        }
        return FleetPullResult(
            agent: profile.id, query: text, maxObjects: maxN,
            truncated: truncated, items: items)
    }

    public func byIDs(_ specs: [(world: String?, id: String)]) -> FleetPullResult {
        let maxN = Self.clampedMaxObjects(profile.pull.maxObjects)
        var items: [FleetPullItem] = []
        let bodyLimit = max(0, profile.pull.bodyChars)
        for spec in specs {
            if items.count >= maxN { break }
            if let world = spec.world {
                if let obj = query.loadObject(world: world, id: spec.id) {
                    items.append(item(from: obj, world: world, bodyLimit: bodyLimit))
                }
            } else {
                // search all enabled worlds for id prefix
                for entry in registry.enabledWorlds {
                    if let obj = query.loadObject(world: entry.name, id: spec.id) {
                        items.append(item(from: obj, world: entry.name, bodyLimit: bodyLimit))
                        break
                    }
                }
            }
        }
        return FleetPullResult(
            agent: profile.id, maxObjects: maxN,
            truncated: specs.count > items.count && items.count >= maxN,
            items: items)
    }

    /// event tree + blob shas (bytes not included).
    public func byEvent(world: String, runID: String) -> FleetPullResult {
        let maxN = Self.clampedMaxObjects(profile.pull.maxObjects)
        guard let entry = registry.worlds.first(where: { $0.name == world }) else {
            return FleetPullResult(agent: profile.id, maxObjects: maxN,
                                   truncated: false, items: [])
        }
        let log = EventLog(root: URL(fileURLWithPath: entry.rootPath))
        let all = log.all()
        guard let root = all.first(where: { $0.id == runID || $0.id.hasPrefix(runID) }) else {
            return FleetPullResult(agent: profile.id, maxObjects: maxN,
                                   truncated: false, items: [], events: [], blobShas: [])
        }
        var collected: [Event] = [root]
        func walk(_ id: String) {
            for c in log.children(of: id, in: all) {
                collected.append(c)
                walk(c.id)
            }
        }
        walk(root.id)
        let truncated = collected.count > maxN
        let bounded = Array(collected.prefix(maxN))
        let shas = bounded.compactMap(\.source)
        return FleetPullResult(
            agent: profile.id,
            maxObjects: maxN,
            truncated: truncated,
            items: [],
            events: bounded.map(FleetPullEvent.init(from:)),
            blobShas: shas
        )
    }

    /// blob bytes only if profile.includeBlobs.
    public func blobData(world: String, sha: String) -> (data: Data?, denied: Bool, path: String?) {
        guard profile.pull.includeBlobs else {
            return (nil, true, nil)
        }
        guard let entry = registry.worlds.first(where: { $0.name == world }) else {
            return (nil, false, nil)
        }
        let store = BlobStore(root: URL(fileURLWithPath: entry.rootPath))
        return (store.get(sha), false, store.url(for: sha).path)
    }

    private func item(from obj: LedgerObject, world: String, bodyLimit: Int) -> FleetPullItem {
        let snip = obj.body.split(separator: "\n").map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        return FleetPullItem(
            world: world, id: obj.id, title: obj.title, score: nil,
            snippet: snip, body: truncate(obj.body, limit: bodyLimit))
    }

    private func truncate(_ s: String, limit: Int) -> String {
        if limit <= 0 { return "" }
        if s.count <= limit { return s }
        return String(s.prefix(limit)) + "…"
    }
}
