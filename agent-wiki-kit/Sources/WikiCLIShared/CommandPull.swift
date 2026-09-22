import Foundation
import LocalizationKit
import KnowledgeBaseWikiCore

public func runPull(arguments: [String]) {
    func opt(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), arguments.count > i + 1 else { return nil }
        return arguments[i + 1]
    }
    let asJSON = arguments.contains("--json")
    let agentID = opt("--agent") ?? defaultAgentID()
    let store = AgentProfileStore()
    let profile: AgentProfile
    do { profile = try store.load(id: agentID) } catch { fail("\(error)") }
    let fleet: FleetRegistry
    do { fleet = try FleetStore().load() } catch { fleet = FleetRegistry() }
    let pull = FleetPull(registry: fleet, profile: profile)

    if let q = opt("--query") {
        emitPull(pull.byQuery(q), asJSON: asJSON)
        return
    }
    if let run = opt("--event") {
        guard let world = opt("--world") else { fail("pull --event requires --world <name>") }
        emitPull(pull.byEvent(world: world, runID: run), asJSON: asJSON)
        return
    }
    if let sha = opt("--blob") {
        runPullBlob(
            pull: pull, sha: sha, world: opt("--world"),
            agentID: agentID, maxObjects: profile.pull.maxObjects, asJSON: asJSON)
        return
    }
    if arguments.contains("--ids") {
        runPullIDs(arguments: arguments, opt: opt, pull: pull, asJSON: asJSON)
        return
    }

    fail("""
    usage: agent-wiki pull --agent <id> …
      pull --agent <id> --query <q> [--json]
      pull --agent <id> --ids <id>… [--world <w>] [--json]
      pull --agent <id> --event <run-id> --world <w> [--json]
      pull --agent <id> --blob <sha> --world <w> [--json]
    """)
}

private func runPullBlob(
    pull: FleetPull,
    sha: String,
    world: String?,
    agentID: String,
    maxObjects: Int,
    asJSON: Bool
) {
    guard let world else { fail("pull --blob requires --world <name>") }
    let (data, denied, path) = pull.blobData(world: world, sha: sha)
    if denied {
        if asJSON {
            printJSON(FleetPullResult(
                agent: agentID, maxObjects: FleetPull.clampedMaxObjects(maxObjects),
                truncated: false, items: [], blobShas: [sha], blobDenied: true))
        } else {
            fail("blob pull denied — set profile.pull.includeBlobs=true", code: 2)
        }
        return
    }
    guard let data else { fail("blob not found: \(sha)", code: 1) }
    if asJSON {
        struct BlobOut: Encodable {
            let agent: String; let world: String; let sha: String
            let path: String?; let size: Int; let blobDenied: Bool
        }
        printJSON(BlobOut(
            agent: agentID, world: world, sha: sha, path: path,
            size: data.count, blobDenied: false))
    } else {
        FileHandle.standardOutput.write(data)
    }
}

private func runPullIDs(
    arguments: [String],
    opt: (String) -> String?,
    pull: FleetPull,
    asJSON: Bool
) {
    guard let idsIdx = arguments.firstIndex(of: "--ids") else { fail("pull --ids <id>…") }
    let world = opt("--world")
    var ids: [String] = []
    var i = idsIdx + 1
    while i < arguments.count {
        let a = arguments[i]
        if a.hasPrefix("--") { break }
        ids.append(a)
        i += 1
    }
    guard !ids.isEmpty else { fail("pull --ids <id>…") }
    emitPull(pull.byIDs(ids.map { (world: world, id: $0) }), asJSON: asJSON)
}

private func emitPull(_ result: FleetPullResult, asJSON: Bool) {
    if asJSON {
        printJSON(result)
        return
    }
    print("agent=\(result.agent) max=\(result.maxObjects) truncated=\(result.truncated)")
    if let q = result.query { print("query: \(q)") }
    for it in result.items {
        print("\(it.world)  \(it.id.prefix(8))  \(it.title ?? CLILocalization.string("CommandPull.untitled"))  score=\(it.score.map { String(format: "%.3f", $0) } ?? "-")")
        if !it.snippet.isEmpty { print("  \(it.snippet.prefix(120))") }
    }
    if let events = result.events, !events.isEmpty {
        print("events (\(events.count)):") // allow:debug CLI pull 결과 면
        for e in events {
            // allow:debug CLI pull 결과 면
            print("  event=\(e.id) subject=\(e.subject.prefix(8)) rel=\(e.rel) level=\(e.level) parent=\(e.parent ?? "-")") // allow:debug CLI pull 결과 면
        }
    }
    if let shas = result.blobShas, !shas.isEmpty {
        print("blobShas: \(shas.joined(separator: ", "))")
    }
    if result.blobDenied ?? false {
        print("blobDenied: true")
    }
}
