import Foundation
import SessionKit
import WikiLedgerKit

// 드리밍 설정 — 호스트 설정의 `dream` 자리. 비운 칸은 기본값이다.
// 근거: docs/business-rules.md "드리밍"(하루 한 번·안전장치 기본값은 조정 가능, AI 실행 도구·모델은 설정),
// docs/architecture.md "agent-law"(드리밍은 지원 CLI 목록의 실행 도구를 공용 실행기로 무인 호출).

public struct LawDreamSettings: Codable, Equatable, Sendable {
    /// AI 실행 도구(지원 CLI 목록). 기본 Claude Code.
    public var cli: SupportedAIAgentCLI?
    /// 정확한 모델 id.
    public var model: String?
    /// 추론 강도(`LawEffort`).
    public var effort: String?
    /// 자동 실행 간격(시간). 마지막 실행 뒤 이만큼 지나야 자동 드리밍이 돈다.
    public var intervalHours: Double?
    /// 한 번에 적용할 최대 변경 수. 넘는 제안은 다음 실행으로 미룬다.
    public var maxChanges: Int?
    /// 한 묶음의 폐지 상한. 넘으면 묶음을 적용하지 않고 경보.
    public var maxRepeals: Int?
    /// 목차 줄 수 상한.
    public var contentsMaxLines: Int?
    /// 판결·조문을 읽기만 할 저장소 루트 경로들.
    public var repositories: [String]?
    /// AI 실행 시간 상한(초).
    public var timeoutSeconds: Double?

    public init(
        cli: SupportedAIAgentCLI? = nil, model: String? = nil, effort: String? = nil, intervalHours: Double? = nil,
        maxChanges: Int? = nil, maxRepeals: Int? = nil, contentsMaxLines: Int? = nil, repositories: [String]? = nil,
        timeoutSeconds: Double? = nil
    ) {
        self.cli = cli
        self.model = model
        self.effort = effort
        self.intervalHours = intervalHours
        self.maxChanges = maxChanges
        self.maxRepeals = maxRepeals
        self.contentsMaxLines = contentsMaxLines
        self.repositories = repositories
        self.timeoutSeconds = timeoutSeconds
    }

    public static let defaultCLI: SupportedAIAgentCLI = .claude
    public static let defaultModel = "claude-opus-5-5"
    public static let defaultEffort = LawEffort.high.rawValue
    public static let defaultIntervalHours: Double = 24
    public static let defaultMaxChanges = 10
    public static let defaultMaxRepeals = 3
    public static let defaultContentsMaxLines = 200
    public static let defaultTimeoutSeconds: Double = 900

    public var resolvedCLI: SupportedAIAgentCLI { cli ?? Self.defaultCLI }

    public var resolvedModel: String {
        let trimmed = model?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? Self.defaultModel : trimmed
    }

    public var resolvedEffort: String { effort.flatMap { LawEffort(rawValue: $0)?.rawValue } ?? Self.defaultEffort }

    public var interval: TimeInterval { (intervalHours.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultIntervalHours) * 3600 }

    public var resolvedMaxChanges: Int { maxChanges.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultMaxChanges }

    public var resolvedMaxRepeals: Int { maxRepeals.flatMap { $0 >= 0 ? $0 : nil } ?? Self.defaultMaxRepeals }

    public var resolvedContentsMaxLines: Int {
        contentsMaxLines.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultContentsMaxLines
    }

    public var resolvedRepositories: [String] {
        (repositories ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public var timeout: TimeInterval { timeoutSeconds.flatMap { $0 > 0 ? $0 : nil } ?? Self.defaultTimeoutSeconds }

    /// 이 설정으로 만든 AI 실행 한 번.
    public func request(prompt: String) -> LawAIRequest {
        LawAIRequest(cli: resolvedCLI, model: resolvedModel, effort: resolvedEffort, prompt: prompt, timeout: timeout)
    }
}
