import Foundation
import KnowledgeBaseWikiCore

public func runWeight(arguments: [String]) {
    let sub = arguments.count >= 2 ? arguments[1] : "show"
    switch sub {
    case "show": runWeightShow(arguments: arguments)
    case "set": runWeightSet(arguments: arguments)
    default:
        fail("""
        usage: agent-wiki weight show|set …
          weight show [--agent <id>] [--json]
          weight set --agent <id> --world <name> --w <N>
          weight set --agent <id> --domain <name> --w <N>
        """)
    }
}

private func agentFlag(_ arguments: [String]) -> String? {
    guard let i = arguments.firstIndex(of: "--agent"), arguments.count > i + 1 else { return nil }
    return arguments[i + 1]
}

private func runWeightShow(arguments: [String]) {
    let asJSON = arguments.contains("--json")
    let id = agentFlag(arguments) ?? defaultAgentID()
    let store = AgentProfileStore()
    let profile: AgentProfile
    do { profile = try store.load(id: id) } catch { fail("\(error)") }
    let fleet: FleetRegistry
    do { fleet = try FleetStore().load() } catch { fleet = FleetRegistry() }

    if asJSON {
        struct Out: Encodable {
            let agent: String
            let worlds: [String: Double]
            let domains: [String: Double]
            let pull: AgentProfile.PullPolicy
            let fleetDefaults: [String: Double]
        }
        let defaults = Dictionary(uniqueKeysWithValues: fleet.worlds.map { ($0.name, $0.defaultWeight) })
        printJSON(Out(
            agent: profile.id, worlds: profile.worlds, domains: profile.domains,
            pull: profile.pull, fleetDefaults: defaults))
        return
    }
    print("agent: \(profile.id)")
    print("pull: maxObjects=\(profile.pull.maxObjects) includeBlobs=\(profile.pull.includeBlobs)")
    if profile.worlds.isEmpty {
        print("worlds: (profile empty — fleet defaultWeight applies)")
        for w in fleet.worlds.sorted(by: { $0.name < $1.name }) {
            print("  \(w.name)  fleetDefault=\(w.defaultWeight)")
        }
    } else {
        print("worlds:")
        for (k, v) in profile.worlds.sorted(by: { $0.key < $1.key }) {
            print("  \(k)  \(v)")
        }
    }
    if !profile.domains.isEmpty {
        print("domains:")
        for (k, v) in profile.domains.sorted(by: { $0.key < $1.key }) {
            print("  \(k)  \(v)")
        }
    }
}

private func runWeightSet(arguments: [String]) {
    guard let agent = agentFlag(arguments) else {
        fail("weight set --agent <id> --world <name> --w <N>")
    }
    func opt(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), arguments.count > i + 1 else { return nil }
        return arguments[i + 1]
    }
    guard let wRaw = opt("--w"), let w = Double(wRaw) else {
        fail("weight set: --w <number> required")
    }
    let store = AgentProfileStore()
    do {
        if let world = opt("--world") {
            let p = try store.setWorldWeight(agentID: agent, world: world, weight: w)
            print("set \(p.id) world \(world) = \(w)")
        } else if let domain = opt("--domain") {
            let p = try store.setDomainWeight(agentID: agent, domain: domain, weight: w)
            print("set \(p.id) domain \(domain) = \(w)")
        } else {
            fail("weight set: --world or --domain required")
        }
    } catch {
        fail("\(error)")
    }
}
