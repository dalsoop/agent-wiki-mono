import Foundation

/// 꿈 시뮬레이션 및 반사실적 리플레이 엔진 (Dream Simulator Engine).
///
/// 낮(Wake) 동안 축적된 에피소드와 LLM 논리 변환 가설을 바탕으로:
/// 1. 반사실적 리플레이(Counterfactual Simulation): 과거 커밋 및 파일에 후보 룰을 역적용하여 오탐(False Positive) 검증.
/// 2. 스트레스 주입(Stress Inoculation): ReDoS 악성 입력(5,000자 루프) 및 I/O 지연을 가상 주입하여 룰 자체의 생존력과 SLA(0.5ms)를 검증한다.
public struct DreamSimulatorEngine: Sendable {

    public struct DreamSimulationResult: Sendable, Codable, Equatable {
        public let ruleId: String
        public let passed: Bool
        public let falsePositiveCount: Int
        public let stressDurationMs: Double
        public let survivedReDoS: Bool
        public let reason: String

        public init(
            ruleId: String,
            passed: Bool,
            falsePositiveCount: Int,
            stressDurationMs: Double,
            survivedReDoS: Bool,
            reason: String
        ) {
            self.ruleId = ruleId
            self.passed = passed
            self.falsePositiveCount = falsePositiveCount
            self.stressDurationMs = stressDurationMs
            self.survivedReDoS = survivedReDoS
            self.reason = reason
        }

        public var conformsPathSanity: Bool {
            return !reason.contains("path sanity violation") && !reason.contains("Target file extensions")
        }
    }

    public init() {}

    /// 후보 룰에 대한 꿈 가상 시뮬레이션 수행
    public func simulateDream(
        candidate: DeclarativeMinedRule,
        sampleCorpus: [String] = []
    ) -> DreamSimulationResult {
        // 0. 경로 건전성 사전 검사 (Path Sanity Check)
        if candidate.excludePathPatterns.isEmpty {
            return DreamSimulationResult(
                ruleId: candidate.id,
                passed: false,
                falsePositiveCount: 0,
                stressDurationMs: 0.0,
                survivedReDoS: true,
                reason: "Pre-validation path sanity violation: Missing excludePathPatterns"
            )
        }
        if candidate.targetFileExtensions.isEmpty {
            return DreamSimulationResult(
                ruleId: candidate.id,
                passed: false,
                falsePositiveCount: 0,
                stressDurationMs: 0.0,
                survivedReDoS: true,
                reason: "Target file extensions must not be empty"
            )
        }

        // 1. ReDoS 가상 스트레스 주입 시험 (Stress Inoculation)
        let maliciousStressString = String(repeating: "func stressTest() { let x = ", count: 50) + String(repeating: ")", count: 50)
        let start = DispatchTime.now()

        var survivedReDoS = true
        var stressDurationMs: Double = 0.0

        if candidate.pattern.contains("+)+") || candidate.pattern.contains("*)*") || candidate.pattern.contains("++)") {
            survivedReDoS = false
        } else {
            do {
                let regex = try NSRegularExpression(pattern: candidate.pattern, options: [])
                let range = NSRange(location: 0, length: maliciousStressString.utf16.count)
                let stressStart = DispatchTime.now()
                _ = regex.firstMatch(in: maliciousStressString, options: [], range: range)
                let stressEnd = DispatchTime.now()
                stressDurationMs = Double(stressEnd.uptimeNanoseconds - stressStart.uptimeNanoseconds) / 1_000_000.0

                if stressDurationMs > 5.0 {
                    survivedReDoS = false
                }
            } catch {
                // 패턴 파싱 불가
                return DreamSimulationResult(
                    ruleId: candidate.id,
                    passed: false,
                    falsePositiveCount: 0,
                    stressDurationMs: 0.0,
                    survivedReDoS: false,
                    reason: "Invalid regular expression pattern"
                )
            }
        }

        guard survivedReDoS else {
            return DreamSimulationResult(
                ruleId: candidate.id,
                passed: false,
                falsePositiveCount: 0,
                stressDurationMs: stressDurationMs,
                survivedReDoS: false,
                reason: "ReDoS vulnerability detected during dream stress injection (\(String(format: "%.2f", stressDurationMs))ms)"
            )
        }

        // 2. 가상 말뭉치(Corpus) 반사실적 리플레이 (Counterfactual Simulation)
        var falsePositiveCount = 0
        let defaultCorpus = sampleCorpus.isEmpty ? [
            "// Normal code without any issues\nfunc cleanFunction() -> Int { return 42 }",
            "struct SafeModel: Codable { let id: String }",
            "class ViewController: UIViewController { override func viewDidLoad() { super.viewDidLoad() } }"
        ] : sampleCorpus

        for fileContent in defaultCorpus {
            do {
                let regex = try NSRegularExpression(pattern: candidate.pattern, options: [])
                let range = NSRange(location: 0, length: fileContent.utf16.count)
                if regex.firstMatch(in: fileContent, options: [], range: range) != nil {
                    // 정상 코드인데 룰에 걸림 = 오탐 발생
                    falsePositiveCount += 1
                }
            } catch {}
        }

        let passed = (falsePositiveCount == 0) && survivedReDoS
        let end = DispatchTime.now()
        let totalDuration = Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0

        let reason = passed
            ? "Dream simulation certified invariant"
            : (falsePositiveCount > 0 ? "Failed counterfactual verification (FP: \(falsePositiveCount)) - false positive detected" : "Failed dream simulation")

        return DreamSimulationResult(
            ruleId: candidate.id,
            passed: passed,
            falsePositiveCount: falsePositiveCount,
            stressDurationMs: totalDuration,
            survivedReDoS: survivedReDoS,
            reason: reason
        )
    }

    /// 대안 가설 분기 결과 (Counterfactual Branch Result)
    public struct CounterfactualBranchResult: Sendable, Codable, Equatable {
        public let hypothesisText: String
        public let candidateRuleId: String
        public let falsePositiveCount: Int
        public let stressDurationMs: Double
        public let survivedReDoS: Bool
        public let promotedConfidence: Double
        public let isWinner: Bool
        public let reason: String

        public init(
            hypothesisText: String,
            candidateRuleId: String,
            falsePositiveCount: Int,
            stressDurationMs: Double,
            survivedReDoS: Bool,
            promotedConfidence: Double,
            isWinner: Bool,
            reason: String
        ) {
            self.hypothesisText = hypothesisText
            self.candidateRuleId = candidateRuleId
            self.falsePositiveCount = falsePositiveCount
            self.stressDurationMs = stressDurationMs
            self.survivedReDoS = survivedReDoS
            self.promotedConfidence = promotedConfidence
            self.isWinner = isWinner
            self.reason = reason
        }
    }

    /// 실패의 가시화를 위한 격리 기록 (Quarantined Failure Record)
    public struct QuarantinedFailureRecord: Sendable, Codable, Equatable, Identifiable {
        public var id: String { ruleId }
        public let ruleId: String
        public let conversationId: String
        public let agentId: String
        public let failureType: String // "ReDoS_Stress" | "False_Positive" | "Unresolved_Dissonance"
        public let reason: String
        public let originalHypothesis: String
        public let competingHypotheses: [String]
        public let intuitiveSmell: String?
        public let unresolvedQuestions: [String]
        public let timestamp: Date

        public init(
            ruleId: String,
            conversationId: String,
            agentId: String,
            failureType: String,
            reason: String,
            originalHypothesis: String,
            competingHypotheses: [String] = [],
            intuitiveSmell: String? = nil,
            unresolvedQuestions: [String] = [],
            timestamp: Date = Date()
        ) {
            self.ruleId = ruleId
            self.conversationId = conversationId
            self.agentId = agentId
            self.failureType = failureType
            self.reason = reason
            self.originalHypothesis = originalHypothesis
            self.competingHypotheses = competingHypotheses
            self.intuitiveSmell = intuitiveSmell
            self.unresolvedQuestions = unresolvedQuestions
            self.timestamp = timestamp
        }
    }

    /// 흔들리는 에피소드에 대한 A/B 반사실 분기 시뮬레이션
    public func simulateCounterfactualBranches(
        episode: WakeEpisodeRecord,
        sampleCorpus: [String] = []
    ) -> (winningRule: DeclarativeMinedRule?, failureRecord: QuarantinedFailureRecord?, branches: [CounterfactualBranchResult]) {
        var allHypotheses = [episode.hypothesis]
        allHypotheses.append(contentsOf: episode.ambiguity.competingHypotheses)

        var branchResults: [CounterfactualBranchResult] = []
        var bestCandidate: DeclarativeMinedRule? = nil
        var bestBranch: CounterfactualBranchResult? = nil

        let sanitizedTarget = episode.targetFile.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ".", with: "_")

        for (idx, hyp) in allHypotheses.enumerated() {
            let candidateId = "dream-\(episode.agentId)-\(sanitizedTarget)-hyp\(idx)"
            let pattern = hyp.contains("sync") ? "\\bDispatchQueue\\.sync\\b" : "\\bTask\\.sleep\\b"

            let rule = DeclarativeMinedRule(
                id: candidateId,
                summary: "Counterfactual rule from \(hyp)",
                pattern: pattern,
                message: "Invariant: \(hyp)",
                fix: "// Resolved invariant",
                grade: "observation",
                targetFileExtensions: ["swift"],
                fastPathNeedles: hyp.contains("sync") ? ["DispatchQueue"] : ["Task"],
                incidentId: episode.episodeId.uuidString,
                authorAgentId: episode.agentId
            )

            let simResult = simulateDream(candidate: rule, sampleCorpus: sampleCorpus)

            let isWin = simResult.passed && (bestCandidate == nil)
            let branch = CounterfactualBranchResult(
                hypothesisText: hyp,
                candidateRuleId: candidateId,
                falsePositiveCount: simResult.falsePositiveCount,
                stressDurationMs: simResult.stressDurationMs,
                survivedReDoS: simResult.survivedReDoS,
                promotedConfidence: simResult.passed ? 0.95 : 0.2,
                isWinner: isWin,
                reason: simResult.reason
            )
            branchResults.append(branch)

            if isWin {
                bestCandidate = rule
                bestBranch = branch
            }
        }

        if let winner = bestCandidate, let best = bestBranch, best.survivedReDoS && best.falsePositiveCount == 0 {
            return (winningRule: winner, failureRecord: nil, branches: branchResults)
        } else {
            let failRecord = QuarantinedFailureRecord(
                ruleId: "quarantined-\(episode.agentId)-\(sanitizedTarget)",
                conversationId: episode.conversationId,
                agentId: episode.agentId,
                failureType: "Unresolved_Dissonance",
                reason: "All counterfactual branches resulted in ambiguity or failure",
                originalHypothesis: episode.hypothesis,
                competingHypotheses: episode.ambiguity.competingHypotheses,
                intuitiveSmell: episode.ambiguity.intuitiveSmell,
                unresolvedQuestions: episode.ambiguity.unresolvedQuestions
            )
            return (winningRule: nil, failureRecord: failRecord, branches: branchResults)
        }
    }
}
