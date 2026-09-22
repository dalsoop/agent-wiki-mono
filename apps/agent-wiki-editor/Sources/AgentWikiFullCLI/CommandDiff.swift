import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// 개정 diff — 나무위키 '비교'. `diff <id>` 는 그 판 vs 이전 판(supersedes), `diff <a> <b>` 는 두 판.
func runDiff(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail("diff <id접두어> [<id접두어>]") }
    let target = resolve(store, arguments[1])
    let (oldBody, newBody, label): (String, String, String)
    if arguments.count >= 3 {
        let b = resolve(store, arguments[2])
        (oldBody, newBody, label) = (target.body, b.body, "\(target.id.prefix(8)) → \(b.id.prefix(8))")
    } else if let prevID = target.supersedes, let prev = loadObject(store, id: prevID) {
        (oldBody, newBody, label) = (prev.body, target.body, "이전 판 → \(target.id.prefix(8))")
    } else {
        print(CLILocalization.string("CommandDiff.print")); return
    }
    let diff = TextDiff.lines(oldBody, newBody)
    let s = TextDiff.stat(diff)
    print(CLILocalization.format("CommandDiff.print-2", label, s.added, s.removed))
    for line in diff {
        switch line {
        case .same(let t): if !t.isEmpty { print("  \(t)") }
        case .added(let t): print("+ \(t)")
        case .removed(let t): print("- \(t)")
        }
    }
}
