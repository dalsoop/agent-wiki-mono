import Foundation
import KnowledgeBaseWikiCore

public enum WorldBoundIO {
    public static func load(
        from url: URL = LedgerConfig.configURL,
        overlay config: LedgerConfig = LedgerConfig.load(),
        fallbackWorldName: String = "gujo-wiki"
    ) -> BoundLedgerFile {
        WorldBoundBootstrap.load(from: url, overlay: config, fallbackWorldName: fallbackWorldName)
    }

    public static func save(_ file: BoundLedgerFile, to url: URL = LedgerConfig.configURL) {
        do {
            try WorldConfigStore.save(file, to: url)
        } catch {
            FileHandle.standardError.write(
                Data("world 설정 저장 실패: \(error.localizedDescription)\n".utf8))
        }
    }
}

public func runWorldList(file: BoundLedgerFile, asJSON: Bool, emptyMessage: String) {
    let catalog = WorldBindingCatalog(worlds: file.effectiveWorlds)
    let items = WorldListPresentation.items(
        catalog: catalog,
        selectedName: file.currentWorld ?? catalog.worlds.first?.name)
    if asJSON {
        printJSON(items)
    } else if items.isEmpty {
        print(emptyMessage) // allow:debug
    } else {
        print(WorldListPresentation.plainText(items: items)) // allow:debug
    }
}

public func applyWorldAdd(
    file: inout BoundLedgerFile,
    rawFlags: [String],
    usageMessage: String,
    unknownOptionMessage: (String) -> String
) -> (name: String, path: String) {
    let parsed = WorldCLIFlags.parse(rawFlags)
    if let unknown = parsed.unknownOption {
        fail(unknownOptionMessage(unknown))
    }
    guard parsed.positionals.count >= 2 else { fail(usageMessage) }
    let name = parsed.positionals[0]
    let path = (parsed.positionals[1] as NSString).expandingTildeInPath
    do {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).appendingPathComponent("objects"),
            withIntermediateDirectories: true)
    } catch {
        fail("objects 디렉터리 생성 실패: \(error.localizedDescription)")
    }
    switch WorldMutation.adding(
        to: file, name: name, path: path, layer: parsed.layer, parent: parsed.parent,
        display: parsed.display)
    {
    case .success(let next):
        file = next
        return (name, path)
    case .failure(let error):
        fail(error.message)
    }
}

public func applyWorldSetLayer(
    file: inout BoundLedgerFile,
    rawFlags: [String],
    usageMessage: String,
    unknownOptionMessage: (String) -> String
) -> (name: String, layer: String, parent: String?) {
    let parsed = WorldCLIFlags.parse(rawFlags)
    if let unknown = parsed.unknownOption {
        fail(unknownOptionMessage(unknown))
    }
    guard parsed.positionals.count >= 2 else { fail(usageMessage) }
    let name = parsed.positionals[0]
    let layer = parsed.positionals[1]
    switch WorldMutation.settingLayer(
        of: name, in: file, layer: layer, parent: parsed.parent)
    {
    case .success(let next):
        file = next
        return (name, layer, parsed.parent)
    case .failure(let error):
        fail(error.message)
    }
}
