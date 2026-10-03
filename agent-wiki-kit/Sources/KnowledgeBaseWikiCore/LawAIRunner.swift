import Foundation
import CommandKit
import SessionKit
import WikiLedgerKit

// 공용 AI 실행기 — 지원 CLI 목록(SessionKit `SupportedAIAgentCLI`)의 실행 도구를 무인으로 한 번 부르고
// JSON 응답을 받는다. 항소심 중재자(`court hear`)와 드리밍(`dream run`)이 같이 쓴다.
// 근거: docs/business-rules.md "작성자와 모델 기록"(AI 판단을 거친 앱 기록은 runtime·model·effort 를 적는다)·"드리밍"·
// "심급제", docs/standards.md "agent-law (ledger 3)"(실행 도구를 부를 때는 지원 CLI 목록을 쓴다).
// 하위 프로세스는 공용 실행기(`SafeProcessRunner`)로만 부르고, 시험은 `execute` 를 주입한다.

/// AI 실행 한 번의 입력.
public struct LawAIRequest: Sendable, Equatable {
    public var cli: SupportedAIAgentCLI
    public var model: String
    public var effort: String?
    public var prompt: String
    public var timeout: TimeInterval

    public init(cli: SupportedAIAgentCLI, model: String, effort: String? = nil, prompt: String, timeout: TimeInterval = 900) {
        self.cli = cli
        self.model = model
        self.effort = effort
        self.prompt = prompt
        self.timeout = timeout
    }

    /// 이 실행이 낸 판단의 모델 기록(코어 칸). 기록 어휘에 없는 도구면 runtime 이 nil.
    public var modelRecord: LawModelRecord {
        LawModelRecord(
            runtime: LawRuntime(cli: cli)?.rawValue, model: model,
            effort: effort.flatMap { LawEffort(rawValue: $0)?.rawValue } ?? LawEffort.unknown.rawValue)
    }
}

public enum LawAIRunnerError: Error, Equatable, CustomStringConvertible {
    case unsupportedCLI(String)
    case failed(code: Int32, timedOut: Bool, message: String)
    case noJSON(String)
    case invalidJSON(String)

    public var description: String {
        switch self {
        case .unsupportedCLI(let cli): return "무인 실행을 지원하지 않는 실행 도구: \(cli)"
        case .failed(let code, let timedOut, let message):
            return timedOut ? "AI 실행 시간 초과" : "AI 실행 실패(종료 코드 \(code)): \(message)"
        case .noJSON(let head): return "AI 응답에 JSON 객체가 없음: \(head)"
        case .invalidJSON(let message): return "AI 응답 JSON 형식 오류: \(message)"
        }
    }
}

/// 공용 AI 실행기. `LawAIRunner.live.runJSON(request, as: T.self)` 처럼 쓴다.
public struct LawAIRunner: Sendable {
    public typealias Execute = @Sendable (CommandSpecification) -> CommandResult

    private let execute: Execute

    public init(execute: @escaping Execute) { self.execute = execute }

    /// 기본 실행기 — `/usr/bin/env <실행 파일>`, 공용 실행기 `SafeProcessRunner`.
    public static let live = LawAIRunner { spec in SafeProcessRunner.run(spec) }

    /// 실행 명세. 실행 파일 이름과 인자는 지원 CLI 목록이 정한다.
    public static func specification(
        for request: LawAIRequest, environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> CommandSpecification {
        guard let plan = request.cli.unattendedRunPlan(prompt: request.prompt, model: request.model, effort: request.effort)
        else { throw LawAIRunnerError.unsupportedCLI(request.cli.rawValue) }
        var env = environment
        let home = environment["HOME"] ?? NSHomeDirectory()
        env["PATH"] = ["\(home)/.local/bin", HostPlatformPaths.homebrewBin, "/usr/local/bin", environment["PATH"] ?? "/usr/bin:/bin"]
            .joined(separator: ":")
        return CommandSpecification(
            "/usr/bin/env", [request.cli.executableName] + plan.arguments, environment: env,
            input: plan.standardInput.map { Data($0.utf8) }, timeout: request.timeout)
    }

    /// 실행하고 표준 출력을 돌려준다.
    public func run(_ request: LawAIRequest) throws -> String {
        let result = execute(try Self.specification(for: request))
        guard result.ok else {
            throw LawAIRunnerError.failed(
                code: result.exitCode, timedOut: result.timedOut, message: String(result.trimmedStderr.prefix(400)))
        }
        return result.stdout
    }

    /// 실행하고 응답 속 JSON 객체 하나를 `T` 로 읽는다.
    public func runJSON<T: Decodable>(_ request: LawAIRequest, as type: T.Type) throws -> T {
        try Self.decode(try run(request), as: type)
    }

    /// 응답 텍스트에서 JSON 객체 하나를 읽는다(코드 울타리·앞뒤 설명은 건너뛴다).
    public static func decode<T: Decodable>(_ text: String, as type: T.Type) throws -> T {
        guard let data = jsonObject(in: text) else { throw LawAIRunnerError.noJSON(String(text.prefix(120))) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LawAIRunnerError.invalidJSON("\(error)")
        }
    }

    /// 첫 `{` 부터 마지막 `}` 까지.
    public static func jsonObject(in text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return Data(text[start...end].utf8)
    }
}
