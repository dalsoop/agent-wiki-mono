import Foundation

/// 자율 마이닝된 동적 린트 규칙 스키마 (Mined Rule Schema).
///
/// 학술 논문(CPAT, QLose, SyGuS) 및 Meta Getafix, Google Tricorder 모델을 기반으로
/// 인시던트·버그 커밋의 AST Diff에서 추출된 안티패턴을 선언형 JSON으로 정의한다.
/// 앱 재컴파일 없이 `~/.agent-lint/mined-rules/*.json` 및 레포 내 `.agent-lint/mined-rules/`에서 로드된다.
public struct DeclarativeMinedRule: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let summary: String
    public let pattern: String
    public let message: String
    public let fix: String
    public let grade: String
    public let targetFileExtensions: [String]
    public let pathNeedles: [String]
    public let fastPathNeedles: [String]
    public let excludePathPatterns: [String]
    public let incidentId: String?
    public let minedAt: Date
    public let rationale: String
    public let authorAgentId: String
    public let synthesisDurationSec: Double
    public let backtestDurationSec: Double

    public init(
        id: String,
        summary: String,
        pattern: String,
        message: String,
        fix: String,
        grade: String = "observation",
        targetFileExtensions: [String] = ["swift"],
        pathNeedles: [String] = [],
        fastPathNeedles: [String] = [],
        excludePathPatterns: [String] = ["/Tests/", "/Fixtures/"],
        incidentId: String? = nil,
        minedAt: Date = Date(),
        rationale: String = "Automated mining from incident diff",
        authorAgentId: String = "agent:synthesizer",
        synthesisDurationSec: Double = 0.0,
        backtestDurationSec: Double = 0.0
    ) {
        self.id = id
        self.summary = summary
        self.pattern = pattern
        self.message = message
        self.fix = fix
        self.grade = grade
        self.targetFileExtensions = targetFileExtensions
        self.pathNeedles = pathNeedles
        self.fastPathNeedles = fastPathNeedles
        self.excludePathPatterns = excludePathPatterns
        self.incidentId = incidentId
        self.minedAt = minedAt
        self.rationale = rationale
        self.authorAgentId = authorAgentId
        self.synthesisDurationSec = synthesisDurationSec
        self.backtestDurationSec = backtestDurationSec
    }
}
