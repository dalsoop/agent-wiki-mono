import AgentWikiLocalCore
import Foundation
import KnowledgeBaseWikiCore
import WikiCLIShared
import LocalizationKit

func runPromotion(
    store: LedgerStore,
    repository: RepositoryIdentity?,
    world: LedgerWorld,
    config: LedgerConfig,
    author: String,
    arguments: [String],
    worldOverride: String?
) {
    // repo world 는 git commit 에 봉인해 증명하고, repo가 아닌 world(개인·실험 등)는
    // content-addressed 원장이라는 사실 자체로 증명한다 — repository 가 없다고 거부하지
    // 않고 현재 world 이름을 출처로 건넨다. PromotionService가 둘 다 받아 판별한다.
    let worldName = world.name
    let sourceWorldName: String? = repository == nil ? worldName : nil
    guard arguments.count >= 3 else {
        fail("사용법: promotion preview|publish <객체> --to gujo [--confirm] [--json]")
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
    let targetWorld = resolvePromotionTarget(world: world, config: config, arguments: arguments)
    performPromotionAction(
        action: action,
        store: store,
        source: source,
        repository: repository,
        sourceWorldName: sourceWorldName,
        targetWorld: targetWorld,
        author: author,
        arguments: arguments)
}

private func performPromotionAction(
    action: String,
    store: LedgerStore,
    source: LedgerObject,
    repository: RepositoryIdentity?,
    sourceWorldName: String?,
    targetWorld: LedgerWorld,
    author: String,
    arguments: [String]
) {
    do {
        switch action {
        case "preview":
            try runPromotionPreview(
                store: store, source: source, repository: repository,
                sourceWorldName: sourceWorldName, targetWorld: targetWorld,
                author: author, arguments: arguments)
        case "publish":
            if arguments.contains("--help") || arguments.contains("-h") {
                print(CLILocalization.string("CommandPromotion.print"))
                return
            }
            try runPromotionPublish(
                store: store, source: source, repository: repository,
                sourceWorldName: sourceWorldName, targetWorld: targetWorld,
                author: author, arguments: arguments)
        default:
            fail("promotion 하위명령: preview | publish")
        }
    } catch {
        fail("프로모션 실패: \(error)")
    }
}

private func resolvePromotionTarget(
    world: LedgerWorld,
    config: LedgerConfig,
    arguments: [String]
) -> LedgerWorld {
    let requestedTarget = valueAfter("--to", arguments)
        ?? valueAfter("--target-world", arguments)
        ?? "gujo"
    let catalog = loadWorldCatalog(current: world)
    if let denial = WorldPromotionGate.denial(
        currentWorld: world.name,
        targetWorld: requestedTarget,
        catalog: catalog,
        skipChainWhenUnbound: true)
    {
        fail(denial)
    }
    let targetName = WorldPromotionGate.canonicalTargetName(requestedTarget)
    guard let targetWorld = config.effectiveWorlds.first(where: { $0.name == targetName })
            ?? catalog.world(named: targetName).map({
                LedgerWorld(name: $0.name, rootPath: $0.rootPath)
            })
    else {
        fail("대상 world를 찾을 수 없음: \(targetName)")
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
    print(CLILocalization.format("CommandPromotion.print-2", preview.publishRequires))
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
        fail("publish에는 명시적 --confirm이 필요합니다")
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
