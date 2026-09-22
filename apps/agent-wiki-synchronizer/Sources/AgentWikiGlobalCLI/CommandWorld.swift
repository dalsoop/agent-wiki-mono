import AgentWikiGlobalCore
import CitationLedgerKit
import Foundation
import KnowledgeBaseWikiCore
import SelfTestKit
import WikiCLIShared
import CommandKit
import LocalizationKit

func runWorld(arguments: [String]) {
    var file = loadBoundFile()
    let sub = arguments.count >= 2 && !arguments[1].hasPrefix("-") ? arguments[1] : "list"
    switch sub {
    case "list":
        runWorldList(
            file: file,
            asJSON: arguments.contains("--json") || arguments.contains("-j"),
            emptyMessage: CLILocalization.string("CommandWorld.print"))
    case "use":
        runWorldUse(file: &file, arguments: arguments)
    case "add":
        let added = applyWorldAdd(
            file: &file,
            rawFlags: Array(arguments.dropFirst(2)),
            usageMessage: usage,
            unknownOptionMessage: { CLILocalization.format("CommandWorld.unknownOption", $0) })
        WorldBoundIO.save(file)
        print(CLILocalization.format("CommandWorld.print-3", added.name, added.path))
    case "set-layer":
        let updated = applyWorldSetLayer(
            file: &file,
            rawFlags: Array(arguments.dropFirst(2)),
            usageMessage: CLILocalization.string("CommandWorld.setLayerUsage"),
            unknownOptionMessage: { CLILocalization.format("CommandWorld.unknownOption", $0) })
        WorldBoundIO.save(file)
        print("world \(updated.name) layer=\(updated.layer) parent=\(updated.parent ?? "-")")
    case "rm":
        runWorldRemove(file: &file, arguments: arguments)
    case "init-repo":
        runWorldInitRepo(file: &file, arguments: arguments)
    case "self-test":
        SelfTestRunner.run(WorldSelfTest(), json: arguments.contains("--json") || arguments.contains("-j"))
    default: fail(usage)
    }
}

func loadBoundFile() -> BoundLedgerFile {
    WorldBoundIO.load(from: LedgerConfig.configURL, overlay: LedgerConfig.load())
}

func loadWorldCatalog() -> WorldBindingCatalog {
    WorldCatalogLoader.merging(file: loadBoundFile(), config: LedgerConfig.load())
}

private func runWorldUse(file: inout BoundLedgerFile, arguments: [String]) {
    guard arguments.count >= 3 else { fail(usage) }
    guard file.effectiveWorlds.contains(where: { $0.name == arguments[2] }) else {
        fail("없는 세계관: \(arguments[2])")
    }
    file.worlds = file.effectiveWorlds
    file.currentWorld = arguments[2]
    WorldBoundIO.save(file)
    print(CLILocalization.format("CommandWorld.print-2", arguments[2]))
}

private func runWorldRemove(file: inout BoundLedgerFile, arguments: [String]) {
    guard arguments.count >= 3 else { fail(usage) }
    let name = arguments[2]
    var worlds = file.effectiveWorlds
    let before = worlds.count
    worlds.removeAll { $0.name == name }
    guard worlds.count < before else { fail("없는 세계관: \(name)") }
    file.worlds = worlds
    if file.currentWorld == name {
        file.currentWorld = worlds.first(where: { $0.name == "gujo-wiki" })?.name ?? worlds.first?.name
    }
    WorldBoundIO.save(file)
    let cur = file.currentWorld ?? "없음"
    print(CLILocalization.format("CommandWorld.print-4", name, cur))
}

private func runWorldInitRepo(file: inout BoundLedgerFile, arguments: [String]) {
    let fm = FileManager.default
    let explicitPath = arguments.dropFirst(2).first { !$0.hasPrefix("--") }
    let rawBase: String
    if arguments.contains("--here") {
        rawBase = fm.currentDirectoryPath
    } else if let explicitPath {
        rawBase = (explicitPath as NSString).expandingTildeInPath
    } else {
        rawBase = repoRoot(from: fm.currentDirectoryPath) ?? fm.currentDirectoryPath
    }
    let base = URL(fileURLWithPath: rawBase).standardizedFileURL.path
    let wiki = (base as NSString).appendingPathComponent("." + "wiki")
    do {
        try writeWorldInitScaffold(fm: fm, wiki: wiki, base: base)
    } catch { fail("\(error)") }
    let name = (base as NSString).lastPathComponent
    var worlds = file.effectiveWorlds
    worlds.removeAll { $0.name == name || $0.rootPath == wiki }
    worlds.append(BoundWorld(name: name, rootPath: wiki))
    file.worlds = worlds
    WorldBoundIO.save(file)
    print(CLILocalization.format("CommandWorld.print-5", name, wiki))
    print(CLILocalization.string("CommandWorld.print-6"))
}

private func writeWorldInitScaffold(fm: FileManager, wiki: String, base: String) throws {
    try fm.createDirectory(
        atPath: (wiki as NSString).appendingPathComponent("objects"),
        withIntermediateDirectories: true)
    let gitignore = (wiki as NSString).appendingPathComponent("." + "gitignore")
    if !fm.fileExists(atPath: gitignore) {
        try "# 파생물(재생성 가능) — objects/ 만 커밋한다\nstate/\nblobs/\nindex.db\n"
            .write(toFile: gitignore, atomically: true, encoding: .utf8)
    }
    let authorsPath = (wiki as NSString).appendingPathComponent("authors.json")
    if fm.fileExists(atPath: authorsPath) {
        return
    }
    if AuthorAudit.resolveAuthorsMap(from: URL(fileURLWithPath: wiki)) != nil {
        print(CLILocalization.string("CommandWorld.print-7"))
        return
    }
    let email = gitConfigEmail(cwd: base)
    let actor = CitationActor.resolve()
    let map: [String: String] = email.isEmpty ? [:] : [email: actor]
    let data = try JSONSerialization.data(
        withJSONObject: map, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: URL(fileURLWithPath: authorsPath))
    print(CLILocalization.format("CommandWorld.print-8", WorldAuthorsHint.text(email: email, actor: actor)))
}

private func repoRoot(from start: String) -> String? {
    let fm = FileManager.default
    var dir = URL(fileURLWithPath: start).standardizedFileURL
    while true {
        if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir.path }
        let parent = dir.deletingLastPathComponent()
        if parent.path == dir.path { return nil }
        dir = parent
    }
}

private func gitConfigEmail(cwd: String) -> String {
    let safeResult = SafeProcessRunner.run(
        "/usr/bin/env",
        ["git", "-C", cwd, "config", "user.email"]
    )
    let data = Data(safeResult.stdout.utf8)
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func runOKFExport(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    let outRoot = URL(fileURLWithPath: (arguments[1] as NSString).expandingTildeInPath)
    let objects = store.scan()
    do {
        print(try OKFExporter.export(objects: objects, heads: store.heads(objects), to: outRoot))
    } catch {
        fail("\(error)")
    }
}
