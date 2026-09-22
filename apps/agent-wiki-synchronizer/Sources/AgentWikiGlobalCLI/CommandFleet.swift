import AgentWikiGlobalCore
import Foundation
import KnowledgeBaseWikiCore
import WikiCLIShared
import LocalizationKit

/// fleet — 중앙 관제 레지스트리 (정본 아님). list/doctor/scan/register/remove
func runFleet(arguments: [String]) {
    let sub = arguments.count >= 2 ? arguments[1] : "list"
    switch sub {
    case "list": runFleetList(arguments: arguments)
    case "doctor": runFleetDoctor(arguments: arguments)
    case "scan": runFleetScan(arguments: arguments)
    case "register": runFleetRegister(arguments: arguments)
    case "remove": runFleetRemove(arguments: arguments)
    default:
        fail("""
        usage: agent-wiki fleet list|doctor|scan|register|remove …
          fleet list [--json]
          fleet doctor [--json]
          fleet scan [--workspace <path>]... [--apply] [--json]
          fleet register <name> <path> [--weight N] [--kind personal|repo]
          fleet remove <name>
        """)
    }
}

private func runFleetList(arguments: [String]) {
    let asJSON = arguments.contains("--json")
    let store = FleetStore()
    let reg: FleetRegistry
    do { reg = try store.load() } catch { fail("\(error)") }
    if asJSON {
        printJSON(reg)
        return
    }
    if reg.worlds.isEmpty {
        print(CLILocalization.string("CommandFleet.print"))
        return
    }
    for w in reg.worlds.sorted(by: { $0.name < $1.name }) {
        let mark = w.enabled ? "●" : "○"
        let kind = w.kind.rawValue
        print("\(mark) \(w.name)  w=\(w.defaultWeight)  [\(kind)]  \(w.rootPath)")
    }
    if !reg.workspaceRoots.isEmpty {
        print("workspaceRoots: \(reg.workspaceRoots.joined(separator: ", "))")
    }
}

private func runFleetDoctor(arguments: [String]) {
    let asJSON = arguments.contains("--json")
    let store = FleetStore()
    let reg: FleetRegistry
    do { reg = try store.load() } catch { fail("\(error)") }
    let report = FleetDiagnostics.doctor(registry: reg, ledgerConfig: LedgerConfig.load())
    if asJSON {
        printJSON(report)
        if report.hasErrors { exit(1) }
        return
    }
    print("fleet doctor — worlds \(report.worlds.count) · issues \(report.issues.count)")
    for h in report.worlds {
        let ok = h.exists && h.hasObjectsDir ? "OK" : "BAD"
        let n = h.objectFileCount.map(String.init) ?? "?"
        print("  \(ok)  \(h.name)  objects≈\(n)  \(h.rootPath)")
    }
    if report.issues.isEmpty {
        print(CLILocalization.string("CommandFleet.print-2"))
    } else {
        print("issues:")
        for i in report.issues {
            print("  [\(i.severity.rawValue)] \(i.code)  \(i.message)")
        }
    }
    if report.hasErrors { exit(1) }
}

private func fleetScanWorkspaces(from arguments: [String]) -> [String] {
    var workspaces: [String] = []
    var i = 2
    while i < arguments.count {
        if arguments[i] == "--workspace", i + 1 < arguments.count {
            workspaces.append(arguments[i + 1])
            i += 2
            continue
        }
        i += 1
    }
    return workspaces
}

private func runFleetScan(arguments: [String]) {
    let asJSON = arguments.contains("--json")
    let apply = arguments.contains("--apply")
    var workspaces = fleetScanWorkspaces(from: arguments)
    let store = FleetStore()
    var reg: FleetRegistry
    do { reg = try store.load() } catch { fail("\(error)") }
    if workspaces.isEmpty {
        workspaces = reg.workspaceRoots.isEmpty
            ? FleetDiagnostics.defaultWorkspaceRoots()
            : reg.workspaceRoots
    }
    let candidates = FleetDiagnostics.scan(workspaceRoots: workspaces, registry: reg)
    if asJSON {
        struct Out: Encodable {
            let workspaceRoots: [String]
            let candidates: [FleetScanCandidate]
            let applied: Bool
        }
        if apply {
            do { reg = try applyScan(candidates: candidates, store: store, registry: reg, workspaces: workspaces) }
            catch { fail("\(error)") }
        }
        printJSON(Out(workspaceRoots: workspaces, candidates: candidates, applied: apply))
        return
    }
    if candidates.isEmpty {
        print(CLILocalization.format("CommandFleet.print-3", workspaces.joined(separator: ", ")))
        return
    }
    for c in candidates {
        let mark = c.alreadyRegistered ? "=" : "+"
        print("\(mark) \(c.name)  [\(c.kind.rawValue)]  \(c.rootPath)")
    }
    print("legend: + unregistered · = already in fleet")
    if apply {
        do {
            reg = try applyScan(candidates: candidates, store: store, registry: reg, workspaces: workspaces)
            print("applied — fleet worlds now \(reg.worlds.count)")
        } catch {
            fail("\(error)")
        }
    } else {
        print(CLILocalization.string("CommandFleet.print-4"))
    }
}

private func applyScan(
    candidates: [FleetScanCandidate],
    store: FleetStore,
    registry: FleetRegistry,
    workspaces: [String]
) throws -> FleetRegistry {
    var reg = registry
    if reg.workspaceRoots.isEmpty {
        reg.workspaceRoots = workspaces.map {
            URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL.path
        }
    }
    for c in candidates {
        let weight = c.kind == .personal ? 0.5 : 1.0
        let identity = c.kind == .repo ? GitRepositoryInspector.inspect(worldRoot: c.rootPath) : nil
        if let identity,
           let existingIndex = reg.worlds.firstIndex(where: { $0.repoId == identity.repoId }) {
            var existing = reg.worlds[existingIndex]
            existing.gitRemote = identity.remoteURL
            existing.repoId = identity.repoId
            existing.normalizedGitRemote = identity.normalizedRemote
            existing.worktreePaths = Array(Set(
                (existing.worktreePaths ?? [existing.rootPath]) + [c.rootPath]
            )).sorted()
            reg.worlds[existingIndex] = existing
            continue
        }
        if c.alreadyRegistered,
           let existingIndex = reg.worlds.firstIndex(where: {
               $0.name == c.name || $0.rootPath == c.rootPath
           }) {
            var existing = reg.worlds[existingIndex]
            existing.gitRemote = identity?.remoteURL ?? existing.gitRemote
            existing.repoId = identity?.repoId ?? existing.repoId
            existing.normalizedGitRemote = identity?.normalizedRemote ?? existing.normalizedGitRemote
            if identity != nil {
                existing.worktreePaths = Array(Set(
                    (existing.worktreePaths ?? [existing.rootPath]) + [c.rootPath]
                )).sorted()
            }
            reg.worlds[existingIndex] = existing
            continue
        }
        reg.worlds.removeAll { $0.name == c.name || $0.rootPath == c.rootPath }
        reg.worlds.append(FleetWorldEntry(
            name: c.name,
            rootPath: c.rootPath,
            kind: c.kind,
            defaultWeight: weight,
            enabled: true,
            gitRemote: identity?.remoteURL,
            repoId: identity?.repoId,
            normalizedGitRemote: identity?.normalizedRemote,
            worktreePaths: identity == nil ? nil : [c.rootPath]
        ))
    }
    reg.worlds.sort { $0.name < $1.name }
    try store.save(reg)
    mergeWorldsIntoBoundFile(candidates.map { BoundWorld(name: $0.name, rootPath: $0.rootPath) })
    return reg
}

private func mergeWorldsIntoBoundFile(_ incoming: [BoundWorld]) {
    var file = WorldConfigStore.load(from: LedgerConfig.configURL)
    var worlds = file.effectiveWorlds
    for world in incoming {
        if !worlds.contains(where: { $0.rootPath == world.rootPath || $0.name == world.name }) {
            worlds.append(world)
        }
    }
    file.worlds = worlds
    try? WorldConfigStore.save(file, to: LedgerConfig.configURL)
}

private func runFleetRegister(arguments: [String]) {
    guard arguments.count >= 4 else {
        fail("usage: fleet register <name> <path> [--weight N] [--kind personal|repo]")
    }
    let name = arguments[2]
    let path = arguments[3]
    var weight = 1.0
    var kind: FleetWorldKind = .repo
    var i = 4
    while i < arguments.count {
        switch arguments[i] {
        case "--weight" where i + 1 < arguments.count:
            weight = Double(arguments[i + 1]) ?? 1.0
            i += 2
        case "--kind" where i + 1 < arguments.count:
            kind = FleetWorldKind(rawValue: arguments[i + 1]) ?? .unknown
            i += 2
        default:
            i += 1
        }
    }
    if kind == .personal { weight = weight == 1.0 ? 0.5 : weight }
    do {
        let reg = try FleetStore().register(
            name: name, rootPath: path, kind: kind, defaultWeight: weight)
        print("registered \(name)  w=\(weight)  \(reg.worlds.first { $0.name == name }?.rootPath ?? path)")
        let abs = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
        var file = WorldConfigStore.load(from: LedgerConfig.configURL)
        var worlds = file.effectiveWorlds
        worlds.removeAll { $0.name == name || $0.rootPath == abs }
        worlds.append(BoundWorld(name: name, rootPath: abs))
        file = WorldConfigStore.replacingWorlds(file, with: worlds)
        try? WorldConfigStore.save(file, to: LedgerConfig.configURL)
    } catch {
        fail("\(error)")
    }
}

private func runFleetRemove(arguments: [String]) {
    guard arguments.count >= 3 else { fail("usage: fleet remove <name>") }
    let name = arguments[2]
    do {
        _ = try FleetStore().remove(name: name)
        print("removed \(name)")
    } catch {
        fail("\(error)")
    }
}
