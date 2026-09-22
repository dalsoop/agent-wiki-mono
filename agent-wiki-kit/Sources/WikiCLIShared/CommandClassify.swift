import Foundation
import KnowledgeBaseWikiCore

/// 기존 원문에 3축 선별을 붙인다. 원문은 수정하지 않고, 이전 선별이 있으면 그 선별만
/// supersede해 분류 투영이 항상 하나의 최신 판단을 사용하게 한다.
private func parseClassifyFlags(_ rest: inout [String]) -> LedgerClassificationInput {
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
        default: fail("모르는 옵션: \(flag)")
        }
    }
    guard let domain, let kind, let knowledge, let reason,
          let input = LedgerClassificationInput(
            domain: domain, kind: kind, knowledge: knowledge, reason: reason)
    else {
        fail("classify는 --domain --kind --knowledge --reason 을 모두 받아야 합니다")
    }
    return input
}

private func findPriorScreening(store: LedgerStore, objects: [LedgerObject], targetID: String) -> LedgerObject? {
    let lineageIDs = Set(store.lineage(objects, of: targetID).map(\.id))
    let prior = LedgerClassification.activeScreenings(objects: objects)
        .filter { stamp in stamp.cites.contains { $0.rel == "screens" && lineageIDs.contains($0.id) } }
        .sorted { ($0.published, $0.id) > ($1.published, $1.id) }
    guard prior.count <= 1 else {
        fail("활성 선별이 여러 개입니다 — 먼저 선별 충돌을 해소하세요")
    }
    return prior.first
}

public func runClassify(store: LedgerStore, author: String, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    var rest = Array(arguments.dropFirst())
    guard let targetQuery = rest.first, !targetQuery.hasPrefix("--") else { fail(usage) }
    rest.removeFirst()

    let classification = parseClassifyFlags(&rest)
    let target = resolve(store, targetQuery)
    let objects = store.scan()
    let prior = findPriorScreening(store: store, objects: objects, targetID: target.id)

    do {
        let screening = try store.publishScreening(
            author: author,
            target: target,
            classification: classification,
            batch: ProcessInfo.processInfo.environment["MEMO_LEDGER_BATCH"],
            supersedes: prior?.id)
        syncIndexAfterWrite(store)
        print(screening.id) // allow:debug
    } catch {
        fail("선별 발행 실패: \(error)")
    }
}
