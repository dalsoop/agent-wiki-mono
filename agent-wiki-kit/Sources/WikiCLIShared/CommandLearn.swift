import Foundation
import KnowledgeBaseWikiCore

/// 학습 지표 — 일자별 작업 성공률·개정·철회·경험칙(회고). 카르파시식 경험학습의 측정 신호.
public func runLearn(store: LedgerStore, root: URL, arguments: [String]) {
    let events = EventLog(root: root).all()
    let metrics = LearningMetrics.byDay(objects: store.scan(), events: events)
    func pct(_ d: Double) -> String { String(format: "%.0f%%", d * 100) }
    let s = LearningMetrics.summary(metrics)
    print("학습 지표 \(metrics.count)일 · 성공률 \(pct(s.successRate)) · 경험칙 \(s.rules) · 철회 \(s.retractions)") // allow:debug
    for m in metrics {
        print("\(m.day)  작업 \(m.runsOk)/\(m.runsTotal) (\(pct(m.successRate)))  개정 \(m.revisions)  철회 \(m.retractions)  회고 \(m.newRules)") // allow:debug
    }
}
