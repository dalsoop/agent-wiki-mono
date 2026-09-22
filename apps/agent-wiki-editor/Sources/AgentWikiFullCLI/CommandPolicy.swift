import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// policy classification-baseline [--since now|<ISO>] [--reason <근거>]
/// policy show
///
/// 분류 기준선을 원장 안에 선언한다. 호스트 설정이 아니라 원장 객체라 원장을 따라
/// 다니고, 옮길 때는 supersede 발행이라 "언제 왜 옮겼는지"가 남는다.
func runPolicy(store: LedgerStore, author: String, arguments: [String]) {
    let sub = arguments.count >= 2 ? arguments[1] : "show"
    let objects = store.scan()
    let current = LedgerClassificationPolicy.current(objects: objects, store: store)

    switch sub {
    case "show":
        guard let since = current.since else {
            print(CLILocalization.string("CommandPolicy.print"))
            print(CLILocalization.format("CommandPolicy.print-2", cliToolName()))
            return
        }
        let classification = LedgerClassification(objects: objects)
        let classified = Set(classification.domain.keys)
        let pending = current.unclassified(objects: objects, classified: classified)
        print(CLILocalization.format("CommandPolicy.print-3", LedgerObject.iso.string(from: since)))
        if let by = current.declaredBy { print(CLILocalization.format("CommandPolicy.print-4", String(by.prefix(8)))) }
        print(CLILocalization.format("CommandPolicy.print-5", pending.count))
        for object in pending.prefix(10) {
            print(CLILocalization.format("CommandPolicy.print-6", String(object.id.prefix(8)), object.title ?? CLILocalization.string("cli.untitled")))
        }
        if pending.count > 10 { print(CLILocalization.format("CommandPolicy.print-7", String(pending.count - 10))) }

    case LedgerClassificationPolicy.policyKind:
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
            let object = try store.publish(
                author: author,
                title: CLILocalization.string("CommandPolicy.title"),
                type: LedgerClassificationPolicy.objectType,
                body: LedgerClassificationPolicy.body(since: since, reason: reason),
                supersedes: current.declaredBy)   // 옮기는 경우 옛 선언을 개정한다
            syncIndexAfterWrite(store)
            print(object.id)
            FileHandle.standardError.write(Data(
                "분류 기준선 \(LedgerObject.iso.string(from: since)) 이후 발행분에 적용\n".utf8))
        } catch {
            fail("\(error)")
        }

    default:
        fail("policy show | policy \(LedgerClassificationPolicy.policyKind) --since now --reason <근거>")
    }
}
