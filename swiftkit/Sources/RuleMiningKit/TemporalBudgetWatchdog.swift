import Foundation

/// 단일 린트 규칙 실행 타임아웃(50ms) 초과 감시 및 마이크로 프로파일링 워치독.
///
/// 특정 정규식의 ReDoS나 디스크 I/O 악화로 인해 단일 규칙이 개발자 및 워커의
/// 실행 시간 예산(50ms)을 침범하는 즉시 감지하여 텔레메트리를 수집하고 경고를 발행한다.
public final class TemporalBudgetWatchdog: @unchecked Sendable {
    public static let shared = TemporalBudgetWatchdog()

    /// 단일 규칙 실행 당 허용되는 최대 시간 예산 (기본 50ms = 0.05초)
    public static let defaultPerRuleBudgetSeconds: TimeInterval = 0.050
    public static let watchdogRuleID = "temporal-budget-watchdog"

    public struct OverrunRecord: Sendable, Equatable {
        public let ruleID: String
        public let path: String
        public let durationSeconds: TimeInterval
        public let budgetSeconds: TimeInterval
        public let timestamp: Date
    }

    private let lock = NSLock()
    private var perRuleBudgetSeconds: TimeInterval = defaultPerRuleBudgetSeconds
    private var overruns: [OverrunRecord] = []
    private var maxDurations: [String: TimeInterval] = [:]
    private var totalExecutions: [String: Int] = [:]

    public init() {}

    public func setPerRuleBudget(milliseconds: Double) {
        lock.lock()
        perRuleBudgetSeconds = milliseconds / 1000.0
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        overruns.removeAll()
        maxDurations.removeAll()
        totalExecutions.removeAll()
        lock.unlock()
    }

    /// 고정밀 모노토닉 시계 기반 규칙 실행 감시 래퍼
    public func execute<T>(
        ruleID: String,
        path: String,
        block: () throws -> T
    ) rethrows -> T {
        let budget = perRuleBudgetSeconds
        let start = DispatchTime.now()

        defer {
            let end = DispatchTime.now()
            let nanos = end.uptimeNanoseconds - start.uptimeNanoseconds
            let elapsed = TimeInterval(nanos) / 1_000_000_000.0
            record(ruleID: ruleID, path: path, elapsed: elapsed, budget: budget)
        }

        return try block()
    }

    private func record(ruleID: String, path: String, elapsed: TimeInterval, budget: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        totalExecutions[ruleID, default: 0] += 1
        let currentMax = maxDurations[ruleID] ?? 0
        if elapsed > currentMax {
            maxDurations[ruleID] = elapsed
        }

        if elapsed > budget {
            let record = OverrunRecord(
                ruleID: ruleID,
                path: path,
                durationSeconds: elapsed,
                budgetSeconds: budget,
                timestamp: Date()
            )
            overruns.append(record)
        }
    }

    /// 발생한 예산 초과 기록 목록 반환
    public func allOverruns() -> [OverrunRecord] {
        lock.lock()
        defer { lock.unlock() }
        return overruns
    }

}
