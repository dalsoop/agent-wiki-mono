import Foundation

/// **함대의 모든 앱은 같은 방식으로 물어볼 수 있어야 한다.**
///
/// 이게 없으면 관측이 앱마다 다른 모양이 되고, 결국 "이건 왜 안 보이지" 를 매번 손으로
/// 판다. 실측(2026-08-05): 디스크가 두 번 가득 찼는데 **두 번 다 명령이 실패한 뒤에야**
/// 알았다. 원인은 worktree 287GB 였는데 `worktree-lifecycle` 에는 그걸 한 마디로 물어볼
/// `status` 가 없었다 — `list` 는 75개 목록을 쏟아내지 상태를 말하지 않는다.
///
/// (처음엔 `disk-space-analyzer` 를 원인으로 적었지만 그 앱은 `status --json` 이 이미
/// 있었다. **계약으로 재고 나서야 어느 앱이 진짜 안 보이는지 갈렸다** — 짐작으로 고쳤으면
/// 멀쩡한 앱을 건드리고 진짜 구멍은 남겨뒀을 것이다.)
///
/// ## 계약 (넷)
///
/// 1. **`status` 가 있다.** 앱이 자기 상태를 한 마디로 답한다.
/// 2. **인자 없이 답한다.** 물어보는 쪽은 그 앱의 인자 규약을 모른다.
///    (실측: 9개 앱이 `status` 에 인자를 요구해 `EX_USAGE` 로 답했다.)
/// 3. **`--json` 을 받는다.** 사람 문구만 내면 조합이 안 된다.
/// 4. **종료 코드는 `CLIExit` 계약을 따른다.** 0 정상 · 1 발견 · 64 질문이 틀림 ·
///    69 설정 안 됨. 뭉치면 "고쳐야 할 목록" 이 거짓이 된다.
///
/// ## 왜 앱마다 붙이지 않고 계약으로 두나
///
/// 오늘 종료 코드를 여섯 앱에서 손으로 고쳤는데, 그건 **그 여섯 개만** 고친 것이다.
/// 다음 앱은 또 틀린다. 계약을 한 곳에 두고 위반을 세면, 새로 생긴 앱도 같은 자로 잰다.
public enum ObservabilityContract {
    /// 함대가 물어보는 표준 질문.
    public static let statusCommand = "status"

    /// 계약 위반의 종류. **섞어 세지 않는다** — 고치는 방법이 서로 다르다.
    public enum Violation: String, Sendable, Codable, CaseIterable {
        /// `status` 자체가 없다. 물어볼 방법이 없는 앱.
        case noStatus
        /// `status` 는 있는데 `--json` 을 안 낸다. 조합이 안 된다.
        case noJSON
        /// 인자를 요구한다(`EX_USAGE`). 물어보는 쪽은 그 규약을 모른다.
        case needsArguments
        /// CLI 가 PATH 에 없다. 선언은 있는데 설치가 안 됐다.
        case notInstalled

        public var title: String {
            switch self {
            case .noStatus: "status 없음"
            case .noJSON: "--json 없음"
            case .needsArguments: "인자를 요구함"
            case .notInstalled: "CLI 미설치"
            }
        }

        /// 무엇을 하면 해소되나. **각각 다른 일이다.**
        public var remedy: String {
            switch self {
            case .noStatus:
                "`status` 서브커맨드를 추가한다 — 앱이 자기 상태를 한 마디로 답해야 한다"
            case .noJSON:
                "`status --json` 으로 `{ok,result}` 봉투를 낸다"
            case .needsArguments:
                "인자 없이 기본 대상으로 답하게 한다 — 물어보는 쪽은 규약을 모른다"
            case .notInstalled:
                "`app-build-manager ship apps/<app>` 으로 PATH 에 올린다"
            }
        }
    }

    /// 한 앱의 계약 준수 여부.
    public struct Conformance: Sendable, Codable, Equatable {
        public let app: String
        public let cli: String
        public let violations: [Violation]

        public var conforms: Bool { violations.isEmpty }

        public init(app: String, cli: String, violations: [Violation]) {
            self.app = app
            self.cli = cli
            self.violations = violations
        }
    }

    /// capabilities 선언만으로 알 수 있는 위반. **실행하지 않고** 판단한다.
    ///
    /// 실행해야만 알 수 있는 것(인자 요구 등)은 조회하는 쪽이 채운다 —
    /// 선언과 실제가 다를 수 있기 때문이다(실측: registry 는 인자 요구를 안 담는다).
    public static func declaredViolations(commands: [(name: String, json: Bool)],
                                          cliInstalled: Bool) -> [Violation] {
        var out: [Violation] = []
        if !cliInstalled { out.append(.notInstalled) }
        guard let status = commands.first(where: { $0.name == statusCommand }) else {
            out.append(.noStatus)
            return out
        }
        if !status.json { out.append(.noJSON) }
        return out
    }

    /// 실행 결과에서 드러나는 위반.
    public static func observedViolation(exitCode: Int32) -> Violation? {
        exitCode == 64 ? .needsArguments : nil
    }

    /// 선언된 `cli` 를 **실행 가능한 절대 경로로** 바꾼다. 못 찾으면 nil.
    ///
    /// registry 의 `cli` 는 절대 경로일 때도 있고 이름일 때도 있다(실측: 238개 중
    /// 이름이 다수). 이름을 그대로 `isExecutableFile` 에 넣으면 **항상 false** 라
    /// 멀쩡히 설치된 앱이 "CLI 미설치" 로 잡힌다 — 실제로 8건 중 7건이 거짓이었다
    /// (`agent-orca-doctor`·`github-bar` 등 전부 `/opt/homebrew/bin` 에 있었다).
    ///
    /// 실행하는 쪽도 같은 문자열을 `executableURL` 에 넣기 때문에, 해석을 계약 옆에
    /// 두어 **재는 쪽과 실행하는 쪽이 어긋나지 않게** 한다.
    public static func resolvedExecutable(
        _ cli: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        guard !cli.isEmpty else { return nil }
        if cli.contains("/") {
            return fileManager.isExecutableFile(atPath: cli) ? cli : nil
        }
        // PATH 가 비면 못 찾은 것으로 둔다 — 기본 경로를 지어내지 않는다.
        let path = environment["PATH"] ?? ""
        for dir in path.split(separator: ":") where !dir.isEmpty {
            let candidate = (String(dir) as NSString).appendingPathComponent(cli)
            if fileManager.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}
