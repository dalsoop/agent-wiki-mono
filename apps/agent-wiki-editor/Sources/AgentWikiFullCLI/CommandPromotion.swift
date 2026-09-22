import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

func runPromotion(
    store: LedgerStore,
    repository: RepositoryIdentity?,
    worldName: String,
    config: LedgerConfig,
    author: String,
    arguments: [String]
) {
    // repo world 는 git commit 에 봉인해 증명하고, repo가 아닌 world(개인·실험 등)는
    // content-addressed 원장이라는 사실 자체로 증명한다 — repository 가 없다고 거부하지
    // 않고 현재 world 이름을 출처로 건넨다. PromotionService가 둘 다 받아 판별한다.
    let sourceWorldName: String? = repository == nil ? worldName : nil
    guard arguments.count >= 3 else {
        fail("사용법: promotion preview|publish <객체> --to gujo [--confirm] [--json]")
    }
    let action = arguments[1]
    let source = resolve(store, arguments[2])
    let requestedTarget = valueAfter("--to", arguments)
        ?? valueAfter("--target-world", arguments)
        ?? "gujo"
    let targetName = requestedTarget == "gujo" ? "gujo-wiki" : requestedTarget
    guard let targetWorld = config.effectiveWorlds.first(where: { $0.name == targetName }) else {
        fail("대상 world를 찾을 수 없음: \(targetName)")
    }

    do {
        switch action {
        case "preview":
            let preview = try PromotionService.preview(
                sourceStore: store,
                source: source,
                repository: repository,
                sourceWorldName: sourceWorldName,
                targetWorld: targetWorld,
                promotedBy: author)
            if arguments.contains("--json") {
                printJSON(preview)
            } else {
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
                print(CLILocalization.format("CommandPromotion.print", preview.publishRequires))
            }
        case "publish":
            guard arguments.contains("--confirm") else {
                fail("publish에는 명시적 --confirm이 필요합니다")
            }
            let preview = try PromotionService.preview(
                sourceStore: store, source: source, repository: repository,
                sourceWorldName: sourceWorldName,
                targetWorld: targetWorld, promotedBy: author)
            let supplied = valueAfter("--confirm", arguments)
            let token = supplied?.hasPrefix("--") == false
                ? supplied!
                : preview.confirmationToken
            let result = try PromotionService.publish(
                sourceStore: store,
                targetStore: LedgerStore(root: URL(fileURLWithPath: targetWorld.rootPath)),
                source: source,
                repository: repository,
                sourceWorldName: sourceWorldName,
                targetWorld: targetWorld,
                promotedBy: author,
                confirmationToken: token)
            if arguments.contains("--json") {
                printJSON(result)
            } else {
                print("promoted: \(result.promotedObjectId)")
                print("target receipt: \(result.targetReceiptObjectId)")
                print("source receipt: \(result.sourceReceiptObjectId)")
                if result.receipt.sourceKind == "repository" {
                    print("provenance: \(result.receipt.sourceRepoId ?? "-") / \(result.receipt.sourceObjectId) / \(result.receipt.sourceCommit ?? "-")")
                } else {
                    print("provenance: world:\(result.receipt.sourceWorldName ?? "-") / \(result.receipt.sourceObjectId)")
                }
            }
        default:
            fail("promotion 하위명령: preview | publish")
        }
    } catch {
        fail("프로모션 실패: \(error)")
    }
}

private func valueAfter(_ flag: String, _ arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}
