import Foundation

/// 다중 world 검색 facade — search --fleet / pull --query 공유.
public struct FleetQuery: Sendable {
    public var registry: FleetRegistry
    public var profile: AgentProfile

    public init(registry: FleetRegistry, profile: AgentProfile) {
        self.registry = registry
        self.profile = profile
    }

    public func search(
        query: String,
        domain: String? = nil,
        kind: String? = nil,
        knowledge: String? = nil,
        limit: Int = 20
    ) -> [FleetHit] {
        var collected: [FleetHit] = []
        let byName = Dictionary(uniqueKeysWithValues: registry.worlds.map { ($0.name, $0) })

        for entry in registry.enabledWorlds {
            let root = URL(fileURLWithPath: entry.rootPath)
            guard FileManager.default.fileExists(atPath: root.path) else { continue }
            let store = LedgerStore(root: root)
            let objects = store.scan()
            guard !objects.isEmpty else { continue }
            let search = LedgerSearch(
                store: store, objects: objects, query: query,
                domain: domain, kind: kind, knowledge: knowledge)
            for hit in search.hits {
                let strength = hit.strength.score
                let type = hit.object.effectiveType
                let rank = FleetRanker.score(
                    strength: strength,
                    lexical: hit.score,
                    world: entry.name,
                    type: type,
                    domain: hit.domain,
                    profile: profile,
                    fleetEntry: byName[entry.name] ?? entry
                )
                let snippet = snippetLine(hit.object.body)
                collected.append(FleetHit(
                    world: entry.name,
                    id: hit.object.id,
                    title: hit.object.title,
                    author: hit.object.author,
                    type: type,
                    domain: hit.domain,
                    kind: hit.kind,
                    knowledge: hit.knowledge,
                    lexicalScore: hit.score,
                    strength: strength,
                    score: rank,
                    snippet: snippet,
                    body: nil
                ))
            }
        }
        return Array(FleetRanker.rank(collected).prefix(max(0, limit)))
    }

    /// context 용 — 랭킹 hit + 본문 일부 채움.
    public func contextHits(query: String, limit: Int = 8) -> [FleetHit] {
        let ranked = search(query: query, limit: max(limit * 3, 12))
        var out: [FleetHit] = []
        for var hit in ranked.prefix(limit) {
            if let obj = loadObject(world: hit.world, id: hit.id) {
                hit.body = obj.body
                hit.snippet = snippetLine(obj.body)
            }
            out.append(hit)
        }
        return out
    }

    public func loadObject(world: String, id: String) -> LedgerObject? {
        guard let entry = registry.worlds.first(where: { $0.name == world }) else { return nil }
        let store = LedgerStore(root: URL(fileURLWithPath: entry.rootPath))
        if let o = store.find(store.scan(), idPrefix: id) { return o }
        return store.scan().first { $0.id == id || $0.id.hasPrefix(id) }
    }

    private func snippetLine(_ body: String) -> String {
        let line = body.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        if line.count <= 160 { return line }
        return String(line.prefix(157)) + "…"
    }
}

// LedgerStore.find is already used elsewhere — check if exists
