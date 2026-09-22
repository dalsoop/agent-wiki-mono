import AgentWikiLocalCore
import Foundation
import KnowledgeBaseWikiCore
import WikiCLIShared
import LocalizationKit

func runWorld(arguments: [String]) {
    var file = loadBoundFile()
    switch arguments.count >= 2 ? arguments[1] : "list" {
    case "list":
        runWorldList(
            file: file,
            asJSON: arguments.contains("--json"),
            emptyMessage: CLILocalization.string("CommandWorld.empty"))
    case "add":
        let added = applyWorldAdd(
            file: &file,
            rawFlags: Array(arguments.dropFirst(2)),
            usageMessage: worldUsage,
            unknownOptionMessage: { "모르는 옵션: \($0)" })
        WorldBoundIO.save(file)
        print(CLILocalization.format("CommandWorld.added", added.name, added.path))
    case "set-layer":
        let updated = applyWorldSetLayer(
            file: &file,
            rawFlags: Array(arguments.dropFirst(2)),
            usageMessage: "사용법: world set-layer <이름> tenant --parent <공유world>",
            unknownOptionMessage: { "모르는 옵션: \($0)" })
        WorldBoundIO.save(file)
        print("world \(updated.name) layer=\(updated.layer) parent=\(updated.parent ?? "-")")
    default:
        fail(worldUsage)
    }
}

let worldUsage = """
사용법: world list [--json]
       world add <이름> <경로> [--layer tenant --parent <공유world>]
       world set-layer <이름> tenant --parent <공유world>
"""

func loadBoundFile() -> BoundLedgerFile {
    WorldBoundIO.load(from: LedgerConfig.configURL, overlay: LedgerConfig.load())
}

func loadWorldCatalog(current: LedgerWorld? = nil) -> WorldBindingCatalog {
    let file = loadBoundFile()
    var catalog = WorldCatalogLoader.merging(file: file, config: LedgerConfig.load())
    if let current {
        catalog = WorldCatalogLoader.overlayingCurrent(current, onto: catalog, file: file)
    }
    return catalog
}
