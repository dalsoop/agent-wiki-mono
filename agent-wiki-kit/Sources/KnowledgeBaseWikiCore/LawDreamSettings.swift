import Foundation
import SessionKit
import WikiLedgerKit

// 드리밍 설정 — 호스트 설정의 `dream` 자리. 간격·안전장치는 비우면 기본값, AI(실행 도구·모델·강도)는 설정(`world ai dream`)에서만 받는다.
// 근거: docs/business-rules.md "드리밍"(하루 한 번·안전장치 기본값은 조정 가능, AI 실행 도구·모델은 설정),
// docs/architecture.md "agent-law"(드리밍은 지원 CLI 목록의 실행 도구를 공용 실행기로 무인 호출).

public struct LawDreamSettings: Codable, Equatable, Sendable {
    /// AI 실행 도구(지원 CLI 목록). 기본값 없음.
    public var cli: SupportedAIAgentCLI?
    /// 정확한 모델 id. 기본값 없음.
    public var model: String?
    /// 추론 강도(`LawEffort`). 비우면 실행 도구의 기본.
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

    public static let defaultIntervalHours: Double = 24
    public static let defaultMaxChanges = 10
    public static let defaultMaxRepeals = 3
    public static let defaultContentsMaxLines = 200
    public static let defaultTimeoutSeconds: Double = 900

    /// 드리밍 AI 가 설정되지 않았을 때의 안내.
    public static let missingAIGuidance =
        "드리밍 AI 미설정 — `agent-wiki world ai dream --runtime <r> --model <m> [--effort <e>]`"

    /// 설정한 드리밍 AI(실행 도구·모델·추론 강도). 실행 도구나 모델이 비면 nil — 모델 이름은 소스에 두지 않는다.
    public var ai: LawAISelection? {
        let trimmed = model?.trimmingCharacters(in: .whitespaces) ?? ""
        guard let cli, !trimmed.isEmpty else { return nil }
        return LawAISelection(cli: cli, model: trimmed, effort: effort.flatMap { LawEffort(rawValue: $0)?.rawValue })
    }

    /// 상태 표시용 `<도구>:<모델>:<강도>`. 미설정이면 nil.
    public var runnerLabel: String? { ai?.label }

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

    /// 이 설정으로 만든 AI 실행 한 번. 드리밍 AI 가 없으면 `LawDreamError.aiUnset`.
    public func request(prompt: String) throws -> LawAIRequest {
        guard let ai else { throw LawDreamError.aiUnset }
        return LawAIRequest(cli: ai.cli, model: ai.model, effort: ai.effort, prompt: prompt, timeout: timeout)
    }
}

/// 설정에서 고른 AI 하나 — 실행 도구(지원 CLI 목록)·정확한 모델 id·추론 강도(선택).
/// `world ai dream` 과 `world ai arbiters --add <runtime>:<model>[:<effort>]` 이 같은 문법을 쓴다.
public struct LawAISelection: Equatable, Sendable {
    public var cli: SupportedAIAgentCLI
    public var model: String
    public var effort: String?

    public init(cli: SupportedAIAgentCLI, model: String, effort: String? = nil) {
        self.cli = cli
        self.model = model
        self.effort = effort
    }

    public var label: String { [cli.rawValue, model, effort].compactMap { $0 }.joined(separator: ":") }

    /// 실행 도구 이름을 지원 CLI 목록으로 해석한다. 목록 밖이면 nil.
    public static func runtime(named raw: String) -> SupportedAIAgentCLI? {
        let name = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return SupportedAIAgentCLI.allCases.first { $0.rawValue == name || $0.executableName == name }
    }

    /// 추론 강도 값 검사. 비면 nil(=지정 안 함), 어휘 밖이면 오류.
    public static func effort(named raw: String?) -> Result<String?, LawAISelectionError> {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return .success(nil) }
        guard let effort = LawEffort(rawValue: raw.lowercased()), effort != .unknown else {
            return .failure(.unknownEffort(raw))
        }
        return .success(effort.rawValue)
    }

    /// 실행 도구·모델·강도로 만든다. 실행 도구는 지원 CLI 목록, 강도는 `LawEffort` 어휘(unknown 제외).
    public static func make(runtime: String, model: String, effort: String?) -> Result<LawAISelection, LawAISelectionError> {
        guard let cli = Self.runtime(named: runtime) else { return .failure(.unknownRuntime(runtime)) }
        let trimmed = model.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .failure(.emptyModel) }
        return Self.effort(named: effort).map { LawAISelection(cli: cli, model: trimmed, effort: $0) }
    }

    /// `<runtime>:<model>[:<effort>]` 한 칸.
    public static func parse(_ spec: String) -> Result<LawAISelection, LawAISelectionError> {
        let parts = spec.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 || parts.count == 3 else { return .failure(.malformed(spec)) }
        return make(runtime: parts[0], model: parts[1], effort: parts.count == 3 ? parts[2] : nil)
    }
}

public enum LawAISelectionError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownRuntime(String)
    case emptyModel
    case unknownEffort(String)
    case malformed(String)

    public var description: String {
        switch self {
        case .unknownRuntime(let raw):
            return "지원하지 않는 실행 도구: \(raw) (지원: \(SupportedAIAgentCLI.helpPipe))"
        case .emptyModel: return "모델 id 가 비어 있음"
        case .unknownEffort(let raw):
            let allowed = LawEffort.allCases.filter { $0 != .unknown }.map(\.rawValue).joined(separator: "|")
            return "알 수 없는 추론 강도: \(raw) (\(allowed))"
        case .malformed(let spec): return "형식은 <runtime>:<model>[:<effort>] — 받은 값: \(spec)"
        }
    }
}

extension LawArbiterCandidate {
    public init(_ selection: LawAISelection) {
        self.init(cli: selection.cli, model: selection.model, effort: selection.effort)
    }

    public var label: String { LawAISelection(cli: cli, model: model, effort: effort).label }
}

/// `world ai` 설정 변경. 드리밍 AI 와 중재자 후보는 이 경로로만 호스트 설정에 들어간다(소스에 모델 이름을 두지 않는다).
/// 근거: docs/business-rules.md "드리밍"·"심급제", docs/contracts.md "agent-law 명령 (ledger 3)".
public enum LawAIConfigMutation {
    /// `world ai dream --runtime <r> --model <m> [--effort <e>]`. 간격·안전장치 칸은 그대로 둔다.
    public static func settingDream(
        in file: BoundLedgerFile, runtime: String, model: String, effort: String?
    ) -> Result<BoundLedgerFile, WorldMutationFailure> {
        switch LawAISelection.make(runtime: runtime, model: model, effort: effort) {
        case .failure(let error): return .failure(WorldMutationFailure(error.description))
        case .success(let selection):
            var next = file
            var dream = file.dream ?? LawDreamSettings()
            dream.cli = selection.cli
            dream.model = selection.model
            dream.effort = selection.effort
            next.dream = dream
            return .success(next)
        }
    }

    /// `world ai arbiters --add <runtime>:<model>[:<effort>]…` — 뒤에 덧붙인다. 이미 있는 후보는 다시 넣지 않는다.
    public static func addingArbiters(
        in file: BoundLedgerFile, specs: [String]
    ) -> Result<BoundLedgerFile, WorldMutationFailure> {
        var court = file.court ?? LawCourtSettings()
        var arbiters = court.arbiters ?? []
        for spec in specs {
            switch LawAISelection.parse(spec) {
            case .failure(let error): return .failure(WorldMutationFailure(error.description))
            case .success(let selection):
                let candidate = LawArbiterCandidate(selection)
                if !arbiters.contains(candidate) { arbiters.append(candidate) }
            }
        }
        court.arbiters = arbiters
        var next = file
        next.court = court
        return .success(next)
    }

    /// `world ai arbiters --clear` — 중재자 없음. 항소심 사건은 대법원으로 회부된다.
    public static func clearingArbiters(in file: BoundLedgerFile) -> BoundLedgerFile {
        var court = file.court ?? LawCourtSettings()
        court.arbiters = nil
        var next = file
        next.court = court
        return next
    }
}
