import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// 기존 원문에 3축 선별을 붙인다. 원문은 수정하지 않고, 이전 선별이 있으면 그 선별만
/// supersede해 분류 투영이 항상 하나의 최신 판단을 사용하게 한다.
func runClassify(store: LedgerStore, author: String, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    var rest = Array(arguments.dropFirst())
    guard let targetQuery = rest.first, !targetQuery.hasPrefix("--") else { fail(usage) }
    rest.removeFirst()

    var domain: String?
    var kind: String?
    var knowledge: String?
    var reason: String?
    while !rest.isEmpty {
        guard rest.count >= 2 else { fail(usage) }
        let flag = rest.removeFirst()
        let value = rest.removeFirst()
        switch flag {
        case "--domain": domain = value
        case "--kind": kind = value
        case "--knowledge": knowledge = value
        case "--reason": reason = value
        default: fail(CLILocalization.format("CommandClassify.string", flag))
        }
    }
    guard let domain, let kind, let knowledge, let reason,
          let classification = LedgerClassificationInput(
            domain: domain, kind: kind, knowledge: knowledge, reason: reason)
    else {
        fail(CLILocalization.string("CommandClassify.string-2"))
    }

    let target = resolve(store, targetQuery)
    let objects = store.scan()
    let lineageIDs = Set(store.lineage(objects, of: target.id).map(\.id))
    let prior = LedgerClassification.activeScreenings(objects: objects)
        .filter { stamp in stamp.cites.contains { $0.rel == "screens" && lineageIDs.contains($0.id) } }
        .sorted { ($0.published, $0.id) > ($1.published, $1.id) }
    guard prior.count <= 1 else {
        fail(CLILocalization.string("CommandClassify.string-3"))
    }

    do {
        let screening = try store.publishScreening(
            author: author,
            target: target,
            classification: classification,
            batch: ProcessInfo.processInfo.environment["MEMO_LEDGER_BATCH"],
            supersedes: prior.first?.id)
        // 선별은 objects 행의 domain/kind/knowledge 투영을 바꾸므로 인덱스를 따라오게 한다.
        syncIndexAfterWrite(store)
        print(screening.id)
    } catch {
            fail(CLILocalization.format("CommandClassify.string-4", "\(error)"))
    }
}
