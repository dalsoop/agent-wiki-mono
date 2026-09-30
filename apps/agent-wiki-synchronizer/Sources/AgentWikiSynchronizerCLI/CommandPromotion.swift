import AgentWikiSynchronizerCore
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
    worldOverride: String?,
    cwd: String = FileManager.default.currentDirectoryPath
) {
    if arguments.contains("--help") || arguments.contains("-h") {
        print(CLILocalization.string("CommandPromotion.usage"))
        return
    }
    guard arguments.count >= 2 else {
        fail(CLILocalization.string("CommandPromotion.usage"))
    }
    let action = arguments[1]
    if action == "repair-receipts" {
        runPromotionRepairReceipts(
            store: store,
            worldName: worldName,
            config: config,
            author: author,
            arguments: arguments,
            worldOverride: worldOverride,
            cwd: cwd)
        return
    }
    let runContext = PromotionRunContext(
        action: action,
        store: store,
        repository: repository,
        worldName: worldName,
        config: config,
        author: author,
        arguments: arguments,
        worldOverride: worldOverride,
        cwd: cwd)
    runPreviewOrPublish(context: runContext)
}

private struct PromotionRunContext {
    let action: String
    let store: LedgerStore
    let repository: RepositoryIdentity?
    let worldName: String
    let config: LedgerConfig
    let author: String
    let arguments: [String]
    let worldOverride: String?
    let cwd: String
}

private func runPreviewOrPublish(context: PromotionRunContext) {
    let arguments = context.arguments
    guard arguments.count >= 3 else {
        fail(CLILocalization.string("CommandPromotion.usage"))
    }
    let sourceWorldName: String? = context.repository == nil ? context.worldName : nil
    if context.action == "publish" {
        if let denial = WorldEnvLock.denial(
            environment: ProcessInfo.processInfo.environment,
            explicitWorld: context.worldOverride,
            isWrite: true)
        {
            fail(denial)
        }
        let targetWorld = resolvePromotionTarget(
            worldName: context.worldName, config: context.config, arguments: arguments)
        if let denial = RepositoryWorldResolution.checkWriteDenial(world: targetWorld, cwd: context.cwd) {
            fail(denial)
        }
        if let denial = RepositoryWorldResolution.checkWriteDenial(rootPath: context.store.root.path, cwd: context.cwd) {
            fail(denial)
        }
    }
    let source = resolve(context.store, arguments[2])
    let targetWorld = resolvePromotionTarget(
        worldName: context.worldName, config: context.config, arguments: arguments)
    do {
        switch context.action {
        case "preview":
            try runPromotionPreview(
                store: context.store, source: source, repository: context.repository,
                sourceWorldName: sourceWorldName, targetWorld: targetWorld,
                author: context.author, arguments: arguments)
        case "publish":
            try runPromotionPublish(
                store: context.store, source: source, repository: context.repository,
                sourceWorldName: sourceWorldName, targetWorld: targetWorld,
                author: context.author, arguments: arguments)
        default:
            fail(CLILocalization.string("CommandPromotion.subcommands"))
        }
    } catch {
        fail(CLILocalization.format("CommandPromotion.failed", "\(error)"))
    }
}

private func runPromotionRepairReceipts(
    store: LedgerStore,
    worldName: String,
    config: LedgerConfig,
    author: String,
    arguments: [String],
    worldOverride: String?,
    cwd: String = FileManager.default.currentDirectoryPath
) {
    if arguments.contains("--help") || arguments.contains("-h") {
        print(CLILocalization.string("CommandPromotion.usageRepairReceipts"))
        return
    }
    let apply = arguments.contains("--apply")
    if apply,
       let denial = WorldEnvLock.denial(
        environment: ProcessInfo.processInfo.environment,
        explicitWorld: worldOverride,
        isWrite: true)
    {
        fail(denial)
    }
    do {
        let report = try PromotionReceiptRepairService.repair(
            store: store,
            worldName: worldName,
            peerWorlds: config.effectiveWorlds,
            apply: apply,
            author: author,
            cwd: cwd)
        printPromotionRepairReport(report, asJSON: arguments.contains("--json"))
    } catch {
        fail(CLILocalization.format("CommandPromotion.failed", "\(error)"))
    }
}

private func printPromotionRepairReport(_ report: PromotionReceiptRepairReport, asJSON: Bool) {
    if asJSON {
        printJSON(report)
        return
    }
    if report.items.isEmpty {
        print(CLILocalization.string("CommandPromotion.repairEmpty"))
        return
    }
    let appliedStr = report.isApplied ? "true" : "false"
    print(CLILocalization.format("CommandPromotion.repairHeader", report.world, appliedStr))
    for item in report.items {
        let dest = item.destinationWorld ?? "-"
        let statusStr: String
        switch item.status {
        case .dryRun: statusStr = "[dry-run]"
        case .repaired: statusStr = "[repaired]"
        case .unrepairable: statusStr = "[unrepairable]"
        }
        print("\(statusStr) \(item.sourceObjectId) -> \(dest): \(item.detail)")
    }
    if !report.isApplied {
        print(CLILocalization.string("CommandPromotion.repairDryRunNotice"))
    } else if !report.filesToCommit.isEmpty {
        print(CLILocalization.string("CommandPromotion.repairFilesToCommit"))
        for file in report.filesToCommit {
            print("  \(file)")
        }
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
