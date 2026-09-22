import Foundation

/// 학습 지표 — 카르파시식 "경험에서 학습"의 측정 신호(AutoResearch metric). 일자별 시계열로,
/// 시간이 갈수록 나아지는가를 본다: 작업 성공률↑·되돌림/철회↓·경험칙(회고) 누적↑.
/// md·사건 로그에서 파생.
public struct PeriodMetrics: Sendable, Equatable {
    public let day: String        // yyyy-MM-dd
    public let runsOk: Int        // 작업 성공(사건 outcome=ok)
    public let runsFail: Int      // 작업 실패
    public let revisions: Int     // 지식 개정(supersedes)
    public let retractions: Int   // 철회
    public let newRules: Int      // 회고(경험칙) 발행 — 학습 산출
    public var runsTotal: Int { runsOk + runsFail }
    public var successRate: Double { runsTotal == 0 ? 0 : Double(runsOk) / Double(runsTotal) }
}

public enum LearningMetrics {
    nonisolated(unsafe) private static let dayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC"); return f
    }()
    private static func day(_ date: Date) -> String { dayFmt.string(from: date) }

    /// 최근 `days`일 일자별 학습 지표(최신일 먼저). 데이터 없는 날은 생략.
    public static func byDay(objects: [LedgerObject], events: [Event], days: Int = 21) -> [PeriodMetrics] {
        var ok: [String: Int] = [:], fail: [String: Int] = [:]
        for e in events where e.level == .run {
            switch e.outcome {
            case .ok: ok[day(e.occurred), default: 0] += 1
            case .fail: fail[day(e.occurred), default: 0] += 1
            default: break
            }
        }
        var rev: [String: Int] = [:], ret: [String: Int] = [:], rules: [String: Int] = [:]
        for o in objects {
            let d = day(o.published)
            if o.retracts != nil { ret[d, default: 0] += 1; continue }
            if o.effectiveType == "retrospective" { rules[d, default: 0] += 1 }
            if o.supersedes != nil && !o.isProcess { rev[d, default: 0] += 1 }
        }
        let allDays = Set(ok.keys).union(fail.keys).union(rev.keys).union(ret.keys).union(rules.keys)
        let cutoff = day(Date().addingTimeInterval(-Double(days) * 86400))
        return allDays.filter { $0 >= cutoff }.sorted(by: >).map { d in
            PeriodMetrics(day: d, runsOk: ok[d] ?? 0, runsFail: fail[d] ?? 0,
                          revisions: rev[d] ?? 0, retractions: ret[d] ?? 0, newRules: rules[d] ?? 0)
        }
    }

    /// 최근 N일 합산 요약(추세 판단용).
    public static func summary(_ metrics: [PeriodMetrics]) -> (successRate: Double, rules: Int, retractions: Int) {
        let ok = metrics.reduce(0) { $0 + $1.runsOk }
        let total = metrics.reduce(0) { $0 + $1.runsTotal }
        return (total == 0 ? 0 : Double(ok) / Double(total),
                metrics.reduce(0) { $0 + $1.newRules },
                metrics.reduce(0) { $0 + $1.retractions })
    }
}
