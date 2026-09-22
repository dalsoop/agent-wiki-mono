import Foundation
import KnowledgeBaseWikiCore

/// review accept|reject <digest-id> [--score 축=N]... [--comment "<사유>"]
/// 심사대 정제본에 사람 판정을 붙인다. 수락 → 위키 개념 확립. 반려 → 세대 진화 학습 신호.
public func runReview(store: LedgerStore, author: String, arguments: [String]) {
    guard arguments.count >= 3 else {
        fail("review accept|reject <digest-id> [--score 축=N]... [--comment \"<사유>\"]\n축: \(ReviewVerdict.axes.joined(separator: ", "))")
    }
    let decisionArg = arguments[1]
    guard let decision = ReviewVerdict.Decision(rawValue: decisionArg == "수락" ? "accept" : decisionArg == "반려" ? "reject" : decisionArg) else {
        fail("판정은 accept 또는 reject")
    }
    let target = arguments[2]
    let objects = store.scan()
    guard let digest = objects.first(where: { $0.id == target || $0.id.hasPrefix(target) }) else {
        fail("정제본을 찾을 수 없음: \(target)")
    }
    var scores: [String: Int] = [:]
    var comment = ""
    var i = 3
    while i < arguments.count {
        switch arguments[i] {
        case "--score" where i + 1 < arguments.count:
            let kv = arguments[i + 1].split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2, ReviewVerdict.axes.contains(kv[0]), let n = Int(kv[1]) { scores[kv[0]] = n }
            i += 2
        case "--comment" where i + 1 < arguments.count:
            comment = arguments[i + 1]; i += 2
        default: i += 1
        }
    }
    let verdict = ReviewVerdict(decision: decision, scores: scores, comment: comment)
    let title = (digest.title ?? "").replacingOccurrences(of: "정제: ", with: "")
    do {
        let label = decision == .accept ? "수락" : "반려"
        let review = try store.publish(author: author, title: "심사: \(label) — \(title)", type: "review", body: verdict.body(), extras: LedgerPublishExtras(cites: [.init(id: digest.id, rel: ReviewVerdict.rel)]))
        print("심사 \(label): \(review.id.prefix(8))  (정제본 \(digest.id.prefix(8)))") // allow:debug
        if decision == .accept {
            let concept = try store.publish(author: author, title: "개념: \(title)", type: "concept", body: digest.body, extras: LedgerPublishExtras(cites: [.init(id: digest.id, rel: "establishes")]))
            print("위키 확립: \(concept.id.prefix(8))  개념: \(title)") // allow:debug
        } else {
            print("반려 사유가 distiller 세대 진화의 학습 신호가 됩니다 — `agent evolve distiller`") // allow:debug
        }
    } catch { fail("\(error)") }
}
