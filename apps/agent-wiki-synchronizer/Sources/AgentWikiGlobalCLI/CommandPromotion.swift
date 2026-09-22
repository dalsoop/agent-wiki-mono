import AgentWikiGlobalCore
import Foundation
import KnowledgeBaseWikiCore
import WikiCLIShared
import LocalizationKit

func runPromotion(
    store: LedgerStore,
    repository: RepositoryIdentity?,
    worldName: String,
    config: LedgerConfig,
    author: String,
    arguments: [String],
    worldOverride: String?
) {
    let sourceWorldName: String? = repository == nil ? worldName : nil
    guard arguments.count >= 3 else {
        fail(CLILocalization.string("CommandPromotion.usage"))
    }
    let action = arguments[1]
    if action == "publish",
       let denial = WorldEnvLock.denial(
        environment: ProcessInfo.processInfo.environment,
        explicitWorld: worldOverride,
        isWrite: true)
    {
        fail(denial)
    }
    let source = resolve(store, arguments[2])
    let targetWorld = resolvePromotionTarget(
        worldName: worldName, config: config, arguments: arguments)
    do {
        switch action {
        case "preview":
            try runPromotionPreview(
                store: store, source: source, repository: repository,
                sourceWorldName: sourceWorldName, targetWorld: targetWorld,
                author: author, arguments: arguments)
        case "publish":
            if arguments.contains("--help") || arguments.contains("-h") {
                print(CLILocalization.string("CommandPromotion.usagePublish"))
                return
            }
            try runPromotionPublish(
                store: store, source: source, repository: repository,
                sourceWorldName: sourceWorldName, targetWorld: targetWorld,
                author: author, arguments: arguments)
        default:
            fail(CLILocalization.string("CommandPromotion.subcommands"))
        }
    } catch {
        fail(CLILocalization.format("CommandPromotion.failed", "\(error)"))
    }
}

private func resolvePromotionTarget(
    worldName: String,
    config: LedgerConfig,
    arguments: [String]
) -> LedgerWorld {
    let requestedTarget = valueAfter("--to", arguments)
        ?? valueAfter("--target-world", arguments)
        ?? "gujo"
    let catalog = loadWorldCatalog()
    if let denial = WorldPromotionGate.denial(
        currentWorld: worldName, targetWorld: requestedTarget, catalog: catalog)
    {
        fail(denial)
    }
    let targetName = WorldPromotionGate.canonicalTargetName(requestedTarget)
    guard let targetWorld = config.effectiveWorlds.first(where: { $0.name == targetName }) else {
        fail(CLILocalization.format("CommandPromotion.missingTarget", targetName))
    }
    return targetWorld
}

private func runPromotionPreview(
    store: LedgerStore,
    source: LedgerObject,
    repository: RepositoryIdentity?,
    sourceWorldName: String?,
    targetWorld: LedgerWorld,
    author: String,
    arguments: [String]
) throws {
    let preview = try PromotionService.preview(
        sourceStore: store,
        source: source,
        repository: repository,
        sourceWorldName: sourceWorldName,
        targetWorld: targetWorld,
        promotedBy: author)
    if arguments.contains("--json") {
        printJSON(preview)
        return
    }
    print("source kind: \(preview.sourceKind)")
    if preview.sourceKind == "repository" {
        print("repo: \(preview.sourceRepoId ?? "-")")
        print("source: \(preview.sourceObjectId) @ \(preview.sourceCommit ?? "-")")
    } else {
        print("world: \(preview.sourceWorldName ?? "-")")
        print("source: \(preview.sourceObjectId)")
    }
    print("target: \(preview.targetWorld)  \(preview.targetWorldRoot)")
    print("cite: \(preview.promotesCitation.rel) \(preview.promotesCitation.id)")
    print(CLILocalization.format("CommandPromotion.confirmRun", preview.publishRequires))
}

private func runPromotionPublish(
    store: LedgerStore,
    source: LedgerObject,
    repository: RepositoryIdentity?,
    sourceWorldName: String?,
    targetWorld: LedgerWorld,
    author: String,
    arguments: [String]
) throws {
    guard arguments.contains("--confirm") else {
        fail(CLILocalization.string("CommandPromotion.needConfirm"))
    }
    let preview = try PromotionService.preview(
        sourceStore: store, source: source, repository: repository,
        sourceWorldName: sourceWorldName,
        targetWorld: targetWorld, promotedBy: author)
    let token = confirmationToken(supplied: valueAfter("--confirm", arguments), preview: preview)
    let result = try PromotionService.publish(
        sourceStore: store,
        targetStore: LedgerStore(root: URL(fileURLWithPath: targetWorld.rootPath)),
        source: source,
        repository: repository,
        sourceWorldName: sourceWorldName,
        targetWorld: targetWorld,
        promotedBy: author,
        confirmationToken: token)
    printPromotionResult(result, asJSON: arguments.contains("--json"))
}

private func confirmationToken(supplied: String?, preview: PromotionPreview) -> String {
    if let supplied, !supplied.hasPrefix("--") {
        return supplied
    }
    return preview.confirmationToken
}

private func printPromotionResult(_ result: PromotionResult, asJSON: Bool) {
    if asJSON {
        printJSON(result)
        return
    }
    print("promoted: \(result.promotedObjectId)")
    print("target receipt: \(result.targetReceiptObjectId)")
    print("source receipt: \(result.sourceReceiptObjectId)")
    if result.receipt.sourceKind == "repository" {
        print(
            "provenance: \(result.receipt.sourceRepoId ?? "-") / "
            + "\(result.receipt.sourceObjectId) / \(result.receipt.sourceCommit ?? "-")"
        )
    } else {
        print(
            "provenance: world:\(result.receipt.sourceWorldName ?? "-") / "
            + "\(result.receipt.sourceObjectId)"
        )
    }
}

private func valueAfter(_ flag: String, _ arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
