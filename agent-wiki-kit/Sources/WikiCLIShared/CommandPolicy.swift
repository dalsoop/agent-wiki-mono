import Foundation
import KnowledgeBaseWikiCore

/// policy classification-baseline [--since now|<ISO>] [--reason <근거>]
/// policy show
///
/// 분류 기준선을 원장 안에 선언한다. 호스트 설정이 아니라 원장 객체라 원장을 따라
/// 다니고, 옮길 때는 supersede 발행이라 "언제 왜 옮겼는지"가 남는다.
private func showPolicy(
    _ current: LedgerClassificationPolicy, objects: [LedgerObject]
) {
    guard let since = current.since else {
        print("분류 기준선: 없음 — 분류가 요구되지 않는다") // allow:debug
        print("선언: \(cliToolName()) policy classification-baseline --since now --reason \"<근거>\"") // allow:debug
        return
    }
    let classification = LedgerClassification(objects: objects)
    let classified = Set(classification.domain.keys)
    let pending = current.unclassified(objects: objects, classified: classified)
    print("분류 기준선: \(LedgerObject.iso.string(from: since))") // allow:debug
    if let by = current.declaredBy { print("선언 객체: \(by.prefix(8))") } // allow:debug
    print("기준선 이후 미분류: \(pending.count)건") // allow:debug
    for object in pending.prefix(10) {
        print("  \(object.id.prefix(8))  \(object.title ?? "(무제)")") // allow:debug
    }
    if pending.count > 10 { print("  … \(pending.count - 10)건 더") } // allow:debug
}

private func setBaseline(
    store: LedgerStore, author: String, arguments: [String],
    current: LedgerClassificationPolicy
) {
    var sinceText = "now"
    var reason = ""
    var rest = Array(arguments.dropFirst(2))
    while !rest.isEmpty {
        let flag = rest.removeFirst()
        guard !rest.isEmpty else { fail("\(flag) 에 값이 없습니다") }
        let value = rest.removeFirst()
        switch flag {
        case "--since": sinceText = value
        case "--reason": reason = value
        default: fail("모르는 옵션: \(flag)")
        }
    }
    guard !reason.isEmpty else {
        fail("--reason 은 필수입니다 — 기준선을 왜 여기 두는지가 남아야 합니다")
    }
    let since: Date
    if sinceText == "now" {
        since = Date()
    } else if let parsed = LedgerObject.iso.date(from: sinceText)
        ?? ISO8601DateFormatter().date(from: sinceText) {
        since = parsed
    } else {
        fail("--since 는 now 또는 ISO8601 이어야 합니다: \(sinceText)")
    }
    do {
        let policyBody = LedgerClassificationPolicy.body(since: since, reason: reason)
        let policyExtras = LedgerPublishExtras(supersedes: current.declaredBy)
        let object = try store.publish(
            author: author, title: "정책: 분류 기준선",
            type: LedgerClassificationPolicy.objectType,
            body: policyBody, extras: policyExtras)
        syncIndexAfterWrite(store)
        print(object.id) // allow:debug
        FileHandle.standardError.write(Data(
            "분류 기준선 \(LedgerObject.iso.string(from: since)) 이후 발행분에 적용\n".utf8))
    } catch {
        fail("\(error)")
    }
}

public func runPolicy(store: LedgerStore, author: String, arguments: [String]) {
    let sub = arguments.count >= 2 ? arguments[1] : "show"
    let objects = store.scan()
    let current = LedgerClassificationPolicy.current(objects: objects, store: store)

    switch sub {
    case "show":
        showPolicy(current, objects: objects)
    case LedgerClassificationPolicy.policyKind:
        setBaseline(store: store, author: author, arguments: arguments, current: current)
    default:
        fail("policy show | policy \(LedgerClassificationPolicy.policyKind) --since now --reason <근거>")
    }
}
