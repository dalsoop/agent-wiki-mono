import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

/// 두 temp world + fleet/profile 로 rank flip · pull truncate · blob-event 역참조.
@Suite struct FleetQueryPullTests {
    private func makeWorld(name: String, title: String, body: String) throws -> (root: URL, store: LedgerStore) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-w-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("objects"), withIntermediateDirectories: true)
        let store = LedgerStore(root: root)
        _ = try store.publish(author: "t", title: title, type: "evidence", body: body)
        return (root, store)
    }

    @Test func weightFlipChangesTopWorld() throws {
        let token = "fleetflip-\(UUID().uuidString.prefix(8))"
        let a = try makeWorld(name: "alpha", title: "Alpha \(token)", body: "shared \(token) content alpha")
        let b = try makeWorld(name: "beta", title: "Beta \(token)", body: "shared \(token) content beta")
        defer {
            try? FileManager.default.removeItem(at: a.root)
            try? FileManager.default.removeItem(at: b.root)
        }

        let fleetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fleetURL) }
        let fleetStore = FleetStore(fileURL: fleetURL)
        _ = try fleetStore.register(name: "alpha", rootPath: a.root.path, kind: .repo, defaultWeight: 1.0)
        _ = try fleetStore.register(name: "beta", rootPath: b.root.path, kind: .repo, defaultWeight: 1.0)
        let registry = try fleetStore.load()

        let agentsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("agents-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: agentsDir) }
        let profiles = AgentProfileStore(directory: agentsDir)

        // Prefer alpha
        var pAlpha = AgentProfile(id: "agent:test", worlds: ["alpha": 5.0, "beta": 0.1])
        try profiles.save(pAlpha)
        let hitsAlpha = FleetQuery(registry: registry, profile: try profiles.load(id: "agent:test"))
            .search(query: token, limit: 5)
        #expect(!hitsAlpha.isEmpty)
        #expect(hitsAlpha[0].world == "alpha")
        #expect(hitsAlpha.contains { $0.world == "alpha" })
        #expect(hitsAlpha.allSatisfy { !$0.world.isEmpty && $0.score > 0 })

        // Prefer beta — top should flip
        pAlpha.worlds = ["alpha": 0.1, "beta": 5.0]
        try profiles.save(pAlpha)
        let hitsBeta = FleetQuery(registry: registry, profile: try profiles.load(id: "agent:test"))
            .search(query: token, limit: 5)
        #expect(!hitsBeta.isEmpty)
        #expect(hitsBeta[0].world == "beta")
    }

    @Test func pullQueryRespectsMaxAndTruncated() throws {
        let token = "pullmax-\(UUID().uuidString.prefix(8))"
        let a = try makeWorld(name: "w1", title: "One \(token)", body: "body \(token) one")
        // second object same world for multi-hit
        _ = try a.store.publish(author: "t", title: "Two \(token)", type: "evidence", body: "body \(token) two")
        let b = try makeWorld(name: "w2", title: "Three \(token)", body: "body \(token) three")
        defer {
            try? FileManager.default.removeItem(at: a.root)
            try? FileManager.default.removeItem(at: b.root)
        }
        let fleetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-p-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fleetURL) }
        let fs = FleetStore(fileURL: fleetURL)
        _ = try fs.register(name: "w1", rootPath: a.root.path)
        _ = try fs.register(name: "w2", rootPath: b.root.path)
        let reg = try fs.load()

        var profile = AgentProfile(id: "agent:pull")
        profile.pull.maxObjects = 1
        profile.pull.bodyChars = 50
        let pull = FleetPull(registry: reg, profile: profile)
        let result = pull.byQuery(token)
        #expect(result.items.count == 1)
        #expect(result.truncated == true)
        #expect(result.maxObjects == 1)
        #expect(result.items[0].body != nil)
        #expect(!result.items[0].world.isEmpty)
    }

    @Test func blobEventIndexReverseRefs() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bei-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("objects"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let blobs = BlobStore(root: root)
        let payload = Data("hello-blob-\(UUID().uuidString)".utf8)
        let sha = try blobs.put(payload)
        let log = EventLog(root: root)
        let ev = Event(writer: "t", subject: "subj-1", rel: "ran", level: .run, extras: Event.Extras(source: sha, outcome: .pending))
        try log.append(ev)

        let idx = BlobEventIndex(root: root)
        let snap = try idx.rebuild()
        #expect(snap.records.contains { $0.sha == sha })
        let refs = try idx.eventsReferencing(sha: sha)
        #expect(refs.contains { $0.id == ev.id })
        let filtered = try idx.filterEvents(source: sha)
        #expect(filtered.count >= 1)
        #expect(filtered[0].source == sha)
    }

    @Test func rankerPureMathWorldWeight() {
        let profile = AgentProfile(id: "x", worlds: ["a": 2.0, "b": 0.5])
        let sA = FleetRanker.score(
            strength: 0.5, lexical: 3, world: "a", type: "evidence",
            domain: nil, profile: profile, fleetEntry: nil)
        let sB = FleetRanker.score(
            strength: 0.5, lexical: 3, world: "b", type: "evidence",
            domain: nil, profile: profile, fleetEntry: nil)
        #expect(sA > sB)
    }

    @Test func agentProfileRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AgentProfileStore(directory: dir)
        let p = try store.setWorldWeight(agentID: "agent:z", world: "gujo-wiki", weight: 0.4)
        #expect(p.worlds["gujo-wiki"] == 0.4)
        let loaded = try store.load(id: "agent:z")
        #expect(loaded.worlds["gujo-wiki"] == 0.4)
    }

    @Test func pullEventReturnsBlobShas() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pev-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("objects"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sha = try BlobStore(root: root).put(Data("x".utf8))
        let start = Event(writer: "t", subject: "job", rel: "start", level: .run, extras: Event.Extras(source: sha, outcome: .pending))
        try EventLog(root: root).append(start)

        let fleetURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-e-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fleetURL) }
        let fs = FleetStore(fileURL: fleetURL)
        _ = try fs.register(name: "w", rootPath: root.path)
        let pull = FleetPull(registry: try fs.load(), profile: AgentProfile(id: "a"))
        let result = pull.byEvent(world: "w", runID: start.id)
        #expect(result.events?.isEmpty == false)
        #expect(result.blobShas?.contains(sha) == true)

        let denied = pull.blobData(world: "w", sha: sha)
        #expect(denied.denied == true)
        var open = AgentProfile(id: "a")
        open.pull.includeBlobs = true
        let pull2 = FleetPull(registry: try fs.load(), profile: open)
        let got = pull2.blobData(world: "w", sha: sha)
        #expect(got.denied == false)
        #expect(got.data == Data("x".utf8))
    }
}
