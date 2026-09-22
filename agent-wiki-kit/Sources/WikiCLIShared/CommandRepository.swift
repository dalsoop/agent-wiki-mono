import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

public func runRepository(
    store: LedgerStore,
    repository: RepositoryIdentity?,
    worlds: [LedgerWorld],
    arguments: [String]
) {
    let subcommand = arguments.count > 1 ? arguments[1] : ""
    guard subcommand == "summary" else {
        fail(CLILocalization.string("CommandRepository.string"))
    }
    runRepositorySummary(
        store: store, repository: repository, worlds: worlds, arguments: arguments)
}

public func runRepositorySummary(
    store: LedgerStore,
    repository: RepositoryIdentity?,
    worlds: [LedgerWorld],
    arguments: [String]
) {
    guard let repository else {
        fail(CLILocalization.string("CommandRepository.string-2"))
    }
    let contract = RepositorySummaryContract(
        identity: repository,
        store: store,
        peerWorlds: worlds)
    if arguments.contains("--json") {
        printJSON(contract)
        return
    }
    print("repository \(contract.repository.id)")
    print("remote \(contract.repository.remote)")
    print("worktree \(contract.repository.worktreePath)")
    print("commit \(contract.repository.sourceCommit)")
    print("tasks open=\(contract.tasks.open) delegated=\(contract.tasks.delegated) completed=\(contract.tasks.completed)")
    print("knowledge total=\(contract.knowledge.total) decisions=\(contract.knowledge.recentDecisions.count)")
    print("promotion candidates=\(contract.promotion.candidates) pending=\(contract.promotion.pending) promoted=\(contract.promotion.promoted)")
    print("integrity \(contract.integrity.status.rawValue) issues=\(contract.integrity.issues.count)")
}
