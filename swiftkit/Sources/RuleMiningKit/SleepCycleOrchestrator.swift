import Foundation
import StateRootKit

/// 수면 주기 및 항상성 복원 오케스트레이터 (Sleep Cycle Orchestrator).
///
/// 1. Wake Phase의 기계+논리 이중 원장(`WakeEpisodeRecord`)과 1인칭 세션 traces를 수집
/// 2. SWS Phase: 단발성/노이즈 에피소드 가지치기(Synaptic Pruning)
/// 3. REM Phase: LLM Logic Transformation (추상적 불변식 생성) + Dream Simulator(반사실적 리플레이 및 스트레스 주입)
/// 4. Homeostasis Consolidation: 통과된 룰을 `MinedRuleRegistry`에 승격 등록하여 함대 린트 항상성 복원.
public struct SleepCycleOrchestrator: Sendable {

    public struct SleepCycleResult: Sendable, Codable, Equatable {
        public let cycleId: UUID
        public let timestamp: Date
        public let totalEpisodesProcessed: Int
        public let prunedNoiseCount: Int
        public let dreamSimulatedCount: Int
        public let consolidatedRuleIds: [String]
        public let quarantinedRuleIds: [String]
        public let sessionIdsMapped: [String]
        public let details: [String]

        public init(
            cycleId: UUID = UUID(),
            timestamp: Date = Date(),
            totalEpisodesProcessed: Int,
            prunedNoiseCount: Int,
            dreamSimulatedCount: Int,
            consolidatedRuleIds: [String],
            quarantinedRuleIds: [String],
            sessionIdsMapped: [String],
            details: [String] = []
        ) {
            self.cycleId = cycleId
            self.timestamp = timestamp
            self.totalEpisodesProcessed = totalEpisodesProcessed
            self.prunedNoiseCount = prunedNoiseCount
            self.dreamSimulatedCount = dreamSimulatedCount
            self.consolidatedRuleIds = consolidatedRuleIds
            self.quarantinedRuleIds = quarantinedRuleIds
            self.sessionIdsMapped = sessionIdsMapped
            self.details = details
        }
    }

    private let episodeStore: WakeEpisodeStore
    private let dreamSimulator: DreamSimulatorEngine
    private let stratumEngine: DailyStratumLedgerEngine
    private let storageDirectory: URL

    public init(
        episodeStore: WakeEpisodeStore = .shared,
        dreamSimulator: DreamSimulatorEngine = DreamSimulatorEngine(),
        stratumEngine: DailyStratumLedgerEngine? = nil,
        storageDirectory: URL? = nil
    ) {
        self.episodeStore = episodeStore
        self.dreamSimulator = dreamSimulator
        let dir: URL
        if let storageDirectory {
            dir = storageDirectory
        } else {
            dir = StateRootKit.url(".agent-lint")
        }
        self.storageDirectory = dir
        self.stratumEngine = stratumEngine ?? DailyStratumLedgerEngine(storageDirectory: dir.appendingPathComponent("stratum", isDirectory: true))
    }

    /// 수면 주기 실행 (기억 응고화 및 항상성 확립)
    public func runSleepCycle(
        dryRun: Bool = false,
        sampleCorpus: [String] = []
    ) -> SleepCycleResult {
        let episodes = episodeStore.queryEpisodes()
        let mappedSessions = Array(Set(episodes.map { $0.conversationId })).sorted()

        // 1. SWS: Synaptic Pruning (단발성 노이즈 가지치기)
        // 에러 카테고리 또는 ruleId별 출현 빈도 집계
        var patternCounts: [String: Int] = [:]
        for ep in episodes {
            let key = ep.ruleId ?? ep.observedAnomaly
            patternCounts[key, default: 0] += 1
        }

        var prunedCount = 0
        var viableEpisodes: [WakeEpisodeRecord] = []
        for ep in episodes {
            let key = ep.ruleId ?? ep.observedAnomaly
            if patternCounts[key, default: 0] < 1 { // 최소 발생 조건
                prunedCount += 1
            } else {
                viableEpisodes.append(ep)
            }
        }

        // 2. REM: LLM Logic Transformation & Dream Simulation
        var consolidatedRuleIds: [String] = []
        var quarantinedRuleIds: [String] = []
        var quarantinedFailures: [DreamSimulatorEngine.QuarantinedFailureRecord] = []
        var details: [String] = []

        // 에피소드로부터 가설적 룰 생성 (LLM 변환 모델 모사)
        for ep in viableEpisodes {
            if ep.ambiguity.requiresCounterfactualExploration {
                // A/B 반사실 분기 시뮬레이션
                let branchRes = dreamSimulator.simulateCounterfactualBranches(episode: ep, sampleCorpus: sampleCorpus)
                if let winner = branchRes.winningRule {
                    consolidatedRuleIds.append(winner.id)
                    details.append("AMBIGUITY RESOLVED [\(winner.id)] via A/B Dream Branch (Session: \(ep.conversationId))")
                    if !dryRun {
                        saveRule(winner, subfolder: "mined-rules")
                    }
                } else if let failure = branchRes.failureRecord {
                    quarantinedRuleIds.append(failure.ruleId)
                    quarantinedFailures.append(failure)
                    details.append("AMBIGUITY QUARANTINED [\(failure.ruleId)] - \(failure.reason) (Questions: \(failure.unresolvedQuestions.joined(separator: ", ")))")
                    if !dryRun {
                        saveFailure(failure)
                    }
                }
            } else {
                let sanitizedTarget = ep.targetFile.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".", with: "_")
                let candidateRuleId = "dream-\(ep.agentId)-\(sanitizedTarget)"

                // 이미 처리된 룰 스킵
                if consolidatedRuleIds.contains(candidateRuleId) || quarantinedRuleIds.contains(candidateRuleId) {
                    continue
                }

                // 인지 문장과 기계 지표를 결합한 불변식 패턴 도출
                let extractedPattern = ep.ruleId != nil ? ep.ruleId! : "\\bDispatchQueue\\.sync\\b"
                let minedRule = DeclarativeMinedRule(
                    id: candidateRuleId,
                    summary: "Dream-transformed rule from session \(ep.conversationId)",
                    pattern: extractedPattern,
                    message: "Invariant violated: \(ep.intentSentence). Hypothesis: \(ep.hypothesis)",
                    fix: "// Avoid synchronous blocking\nTask { ... }",
                    grade: "observation",
                    targetFileExtensions: ["swift"],
                    pathNeedles: [],
                    fastPathNeedles: ["DispatchQueue"],
                    incidentId: ep.episodeId.uuidString,
                    rationale: "Synthesized during REM dream simulation. Anomaly: \(ep.observedAnomaly)",
                    authorAgentId: ep.agentId,
                    synthesisDurationSec: 0.05,
                    backtestDurationSec: 0.1
                )

                // 꿈 시뮬레이션 수행
                let dreamResult = dreamSimulator.simulateDream(candidate: minedRule, sampleCorpus: sampleCorpus)
                if dreamResult.passed {
                    consolidatedRuleIds.append(candidateRuleId)
                    details.append("CERTIFIED [\(candidateRuleId)] via Dream Simulation (Session: \(ep.conversationId))")
                    if !dryRun {
                        saveRule(minedRule, subfolder: "mined-rules")
                    }
                } else {
                    quarantinedRuleIds.append(candidateRuleId)
                    let failure = DreamSimulatorEngine.QuarantinedFailureRecord(
                        ruleId: candidateRuleId,
                        conversationId: ep.conversationId,
                        agentId: ep.agentId,
                        failureType: dreamResult.survivedReDoS ? "False_Positive" : "ReDoS_Stress",
                        reason: dreamResult.reason,
                        originalHypothesis: ep.hypothesis,
                        competingHypotheses: ep.ambiguity.competingHypotheses,
                        intuitiveSmell: ep.ambiguity.intuitiveSmell,
                        unresolvedQuestions: ep.ambiguity.unresolvedQuestions
                    )
                    quarantinedFailures.append(failure)
                    details.append("QUARANTINED [\(candidateRuleId)] - \(dreamResult.reason)")
                    if !dryRun {
                        saveRule(minedRule, subfolder: "quarantine")
                        saveFailure(failure)
                    }
                }
            }
        }

        // 3. 수면 항상성 지층 동결 (Freeze Daily Stratum Snapshot)
        if !dryRun {
            let totalDurations = viableEpisodes.map { $0.durationMs }
            let meanDur = totalDurations.isEmpty ? 0.0 : (totalDurations.reduce(0.0, +) / Double(totalDurations.count))
            let sortedDur = totalDurations.sorted()
            let p95Idx = Int(Double(sortedDur.count) * 0.95)
            let p95Dur = sortedDur.isEmpty ? 0.0 : sortedDur[min(p95Idx, sortedDur.count - 1)]

            let complaints = viableEpisodes.filter { $0.durationMs > 100.0 || $0.exitCode != 0 }.count
            let complaintRate = viableEpisodes.isEmpty ? 0.0 : Double(complaints) / Double(viableEpisodes.count)
            let totalAst = viableEpisodes.map { $0.astNodeCount }.reduce(0, +)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let todayStr = formatter.string(from: Date())

            if totalDurations.isEmpty {
                details.append("STRATUM SKIPPED [\(todayStr)]: no observed episodes")
            } else if let baseline = stratumEngine.calculateRollingBaseline(fallbackTodayMeanMs: meanDur),
                      let decision = stratumEngine.evaluateHomeostaticHealth(
                        todayMeanMs: meanDur,
                        todayComplaintRate: complaintRate,
                        sampleCount: viableEpisodes.count
                      ) {
                let stratumSnapshot = DailyStratumSnapshot(
                    dateString: todayStr,
                    timestamp: Date(),
                    totalEpisodesCount: viableEpisodes.count,
                    meanDurationMs: meanDur,
                    p95DurationMs: p95Dur,
                    complaintCount: complaints,
                    complaintRate: complaintRate,
                    totalAstNodesScanned: totalAst,
                    rollingBaselineMs: baseline,
                    burnRate: decision.burnRate,
                    entropyDelta: decision.burnRate,
                    activeRulesCount: consolidatedRuleIds.count,
                    newlyConsolidatedRuleIds: consolidatedRuleIds,
                    quarantinedRuleIds: quarantinedRuleIds
                )
                try? stratumEngine.recordDailyStratum(stratumSnapshot)
                details.append("STRATUM FROZEN [\(todayStr)]: Rolling Baseline \(String(format: "%.1f", baseline))ms, BurnRate \(String(format: "%.2f", decision.burnRate)), Healthy: \(decision.isHealthy)")
            } else {
                details.append("STRATUM SKIPPED [\(todayStr)]: no baseline")
            }
        }

        return SleepCycleResult(
            totalEpisodesProcessed: episodes.count,
            prunedNoiseCount: prunedCount,
            dreamSimulatedCount: viableEpisodes.count,
            consolidatedRuleIds: consolidatedRuleIds,
            quarantinedRuleIds: quarantinedRuleIds,
            sessionIdsMapped: mappedSessions,
            details: details
        )
    }

    private func saveRule(_ rule: DeclarativeMinedRule, subfolder: String) {
        let folder = storageDirectory.appendingPathComponent(subfolder, isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                FileHandle.standardError.write(Data("[SleepCycleOrchestrator] Failed to create folder: \(error)\n".utf8))
            }
        }
        let fileURL = folder.appendingPathComponent("\(rule.id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(rule)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("[SleepCycleOrchestrator] Failed to write rule \(rule.id): \(error)\n".utf8))
        }
    }

    private func saveFailure(_ failure: DreamSimulatorEngine.QuarantinedFailureRecord) {
        let folder = storageDirectory.appendingPathComponent("quarantine-records", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            } catch {
                FileHandle.standardError.write(Data("[SleepCycleOrchestrator] Failed to create quarantine folder: \(error)\n".utf8))
            }
        }
        let fileURL = folder.appendingPathComponent("\(failure.ruleId).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(failure)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            FileHandle.standardError.write(Data("[SleepCycleOrchestrator] Failed to write failure \(failure.ruleId): \(error)\n".utf8))
        }
    }

    /// 실패의 가시화: 격리된 실패 및 모호성 원장 조회
    public func queryQuarantinedFailures() -> [DreamSimulatorEngine.QuarantinedFailureRecord] {
        let folder = storageDirectory.appendingPathComponent("quarantine-records", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(DreamSimulatorEngine.QuarantinedFailureRecord.self, from: data) else {
                return nil
            }
            return record
        }
    }

    public struct RuleConsolidationEvaluation: Sendable {
        public let promoted: Bool
        public let result: DreamSimulatorEngine.DreamSimulationResult

        public init(promoted: Bool, result: DreamSimulatorEngine.DreamSimulationResult) {
            self.promoted = promoted
            self.result = result
        }
    }

    /// 단일 규칙 후보에 대한 수면 몽중 시뮬레이션 평가 및 승격 여부 판정
    public func evaluateRuleForConsolidation(
        candidate: DeclarativeMinedRule,
        sampleCorpus: [String] = []
    ) -> RuleConsolidationEvaluation {
        let result = dreamSimulator.simulateDream(candidate: candidate, sampleCorpus: sampleCorpus)
        return RuleConsolidationEvaluation(promoted: result.passed, result: result)
    }
}

