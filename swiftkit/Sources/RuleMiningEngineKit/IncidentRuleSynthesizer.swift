import Foundation

/// 인시던트 로그 또는 커밋 Diff로부터 린트 규칙을 역합성(Reverse Synthesis)하는 엔진.
///
/// 학술 기법(AST Diff, Template Generalization, Inductive Logic Synthesis)을 실전 적용하여
/// 버그 유발 패턴(`-`)과 교정 패턴(`+`)으로부터 선언적 룰(`DeclarativeMinedRule`)을 자동 추출한다.
public enum IncidentRuleSynthesizer: Sendable {

    public struct SynthesisInput: Sendable {
        public let incidentId: String
        public let summary: String
        public let buggyPattern: String
        public let fixAdvice: String
        public let fastPathNeedle: String
        public let targetExtensions: [String]
        public let authorAgentId: String
        public let synthesisDurationSec: Double
        public let backtestDurationSec: Double

        public init(
            incidentId: String,
            summary: String,
            buggyPattern: String,
            fixAdvice: String,
            fastPathNeedle: String,
            targetExtensions: [String] = ["swift"],
            authorAgentId: String = "agent:synthesizer",
            synthesisDurationSec: Double = 0.0,
            backtestDurationSec: Double = 0.0
        ) {
            self.incidentId = incidentId
            self.summary = summary
            self.buggyPattern = buggyPattern
            self.fixAdvice = fixAdvice
            self.fastPathNeedle = fastPathNeedle
            self.targetExtensions = targetExtensions
            self.authorAgentId = authorAgentId
            self.synthesisDurationSec = synthesisDurationSec
            self.backtestDurationSec = backtestDurationSec
        }
    }

    public static func synthesize(input: SynthesisInput) -> DeclarativeMinedRule {
        let ruleId = "mined-" + input.incidentId.lowercased().replacingOccurrences(of: "_", with: "-")

        return DeclarativeMinedRule(
            id: ruleId,
            summary: input.summary,
            pattern: input.buggyPattern,
            message: "[\(ruleId)] 인시던트(\(input.incidentId)) 회귀 방지 자율 규칙 위반: \(input.summary)",
            fix: input.fixAdvice,
            grade: "observation",
            targetFileExtensions: input.targetExtensions,
            pathNeedles: [],
            fastPathNeedles: [input.fastPathNeedle],
            excludePathPatterns: ["/Tests/", "/Fixtures/"],
            incidentId: input.incidentId,
            minedAt: Date(),
            rationale: "Synthesized automatically from incident \(input.incidentId)",
            authorAgentId: input.authorAgentId,
            synthesisDurationSec: input.synthesisDurationSec,
            backtestDurationSec: input.backtestDurationSec
        )
    }

    public static func synthesizeWithDiscriminator(
        input: SynthesisInput,
        discriminator: PlausibilityDiscriminatorEngine = PlausibilityDiscriminatorEngine(),
        sampleContext: String = "",
        dryRunFindingsCount: Int = 0,
        historicalFindingsAverage: Double = 0.0
    ) -> (rule: DeclarativeMinedRule, score: PlausibilityScore) {
        let rule = synthesize(input: input)
        let score = discriminator.evaluate(
            candidate: rule,
            sampleContext: sampleContext,
            dryRunFindingsCount: dryRunFindingsCount,
            historicalFindingsAverage: historicalFindingsAverage
        )
        return (rule, score)
    }
    /// 간단한 diff 텍스트(예: git diff -U0 출력)에서 삭제된 위험 구문 추출 헬퍼
    public static func extractBuggyLines(fromDiff diffText: String) -> [String] {
        let lines = diffText.components(separatedBy: "\n")
        var buggyLines: [String] = []
        for line in lines {
            if line.hasPrefix("-") && !line.hasPrefix("---") {
                let stripped = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if !stripped.isEmpty && !stripped.hasPrefix("//") && stripped.count > 4 {
                    buggyLines.append(stripped)
                }
            }
        }
        return buggyLines
    }
}
