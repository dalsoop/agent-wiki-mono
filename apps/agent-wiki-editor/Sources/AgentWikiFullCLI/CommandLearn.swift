import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// 학습 지표 — 일자별 작업 성공률·개정·철회·경험칙(회고). 카르파시식 경험학습의 측정 신호.
func runLearn(store: LedgerStore, root: URL, arguments: [String]) {
    let events = EventLog(root: root).all()
    let metrics = LearningMetrics.byDay(objects: store.scan(), events: events)
    func pct(_ d: Double) -> String { String(format: "%.0f%%", d * 100) }
    let s = LearningMetrics.summary(metrics)
    print(CLILocalization.format("CommandLearn.print", metrics.count, pct(s.successRate), s.rules, s.retractions))
    for m in metrics {
        print(CLILocalization.format("CommandLearn.print-2", m.day, m.runsOk, m.runsTotal, pct(m.successRate), m.revisions, m.retractions, m.newRules))
    }
}
