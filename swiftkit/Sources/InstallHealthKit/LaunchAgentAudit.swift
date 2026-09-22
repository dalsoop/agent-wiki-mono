import Foundation

/// 경로 존재 확인을 추상화 — 테스트에서 목으로 대체 가능(CommandKit 의 `CommandRunning` 패턴과 동일).
public protocol PathExisting: Sendable {
    func exists(_ path: String) -> Bool
}

public struct FileSystemPaths: PathExisting {
    public init() {}
    public func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
}

/// LaunchAgent plist 한 장의 판정 대상 값(plist 파싱 결과를 그대로 담는 값 타입).
public struct LaunchAgentSpec: Equatable, Sendable {
    public let label: String
    public let programArguments: [String]
    /// `StartInterval`/`StartCalendarInterval` 중 하나라도 있으면 주기 작업.
    public let isPeriodic: Bool

    public init(label: String, programArguments: [String], isPeriodic: Bool) {
        self.label = label
        self.programArguments = programArguments
        self.isPeriodic = isPeriodic
    }

    /// plist 딕셔너리에서 판정에 필요한 것만 뽑는다. `Program`(단일 문자열) 형식도 흡수.
    public init(label: String, plist: [String: Any]) {
        var args = plist["ProgramArguments"] as? [String] ?? []
        if args.isEmpty, let program = plist["Program"] as? String { args = [program] }
        self.init(
            label: label,
            programArguments: args,
            isPeriodic: plist["StartInterval"] != nil || plist["StartCalendarInterval"] != nil
        )
    }

    /// 이 plist 가 가리키는 .app 번들 경로(있으면). `open -a <번들>` 과 직접 exec 둘 다 인식.
    public var referencedBundlePath: String? {
        for arg in programArguments {
            if let range = arg.range(of: "/Contents/MacOS/") {
                return String(arg[arg.startIndex..<range.lowerBound])
            }
            if arg.hasSuffix(".app") { return arg }
        }
        return nil
    }

    /// 번들 실행 파일을 직접 exec 하는가(= LaunchServices 중복 방지 우회).
    public var isDirectExec: Bool {
        guard let first = programArguments.first else { return false }
        return first.contains("/Contents/MacOS/")
    }
}

/// LaunchAgent 자동시작 설정의 건강 판정.
///
/// 규칙 정본은 llmwiki `30-runbooks/mac-app-mono-autostart.md`:
/// - `ProgramArguments` 는 `["/usr/bin/open", "-a", "<번들>"]` 이어야 한다. 직접 exec 는 앱이 2개 뜬다.
/// - **예외**: `StartInterval` 류 헤드리스 주기잡(`--tick`)은 직접 exec 가 맞다 —
///   `open -a` 로 바꾸면 주기마다 GUI 가 앞으로 튀어나온다.
/// - 가리키는 번들이 없으면 dangling(자동시작이 조용히 죽음).
public struct LaunchAgentAudit: Sendable {
    private let paths: PathExisting

    public init(paths: PathExisting = FileSystemPaths()) {
        self.paths = paths
    }

    /// plist 한 장 판정.
    public func audit(_ spec: LaunchAgentSpec) -> [HealthIssue] {
        var issues: [HealthIssue] = []

        if spec.isDirectExec, !spec.isPeriodic {
            issues.append(HealthIssue(
                kind: .launchAgentDirectExec,
                severity: .error,
                subject: spec.label,
                detail: "번들 실행 파일을 직접 exec 한다 — LaunchServices 중복 방지를 우회해 앱이 2개 뜬다.",
                remedy: "ProgramArguments 를 [\"/usr/bin/open\", \"-a\", \"<번들>\"] 로 바꾼다.",
                isAutoFixable: spec.referencedBundlePath != nil
            ))
        }

        if let bundle = spec.referencedBundlePath, !paths.exists(bundle) {
            issues.append(HealthIssue(
                kind: .launchAgentDangling,
                severity: .error,
                subject: spec.label,
                detail: "없는 번들을 가리킨다(\(bundle)) — 자동시작이 조용히 실패한다.",
                remedy: "같은 bundle id 로 설치된 현재 번들 경로로 고치거나, 안 쓰면 plist 를 지운다.",
                isAutoFixable: false
            ))
        }

        return issues
    }

    /// 여러 장 일괄 판정.
    public func audit(_ specs: [LaunchAgentSpec]) -> [HealthIssue] {
        specs.flatMap(audit)
    }

    /// 직접 exec plist 를 `open -a` 형태로 고친 ProgramArguments 를 만든다.
    /// 주기잡이거나 번들 경로를 못 찾으면 `nil`(고치면 안 되거나 못 고침).
    public static func repairedProgramArguments(for spec: LaunchAgentSpec) -> [String]? {
        guard spec.isDirectExec, !spec.isPeriodic, let bundle = spec.referencedBundlePath else { return nil }
        return ["/usr/bin/open", "-a", bundle]
    }
}
