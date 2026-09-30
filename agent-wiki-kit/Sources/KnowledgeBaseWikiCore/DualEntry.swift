import CommandKit
import DualEntryKit
import Foundation

/// Agent Wiki dual-entry — 공용 DualEntryKit 프로파일 래퍼.
///
/// 정본 구현은 swiftkit DualEntryKit. 앱 전용 이름·서브커맨드·stamp 경로만 여기서 고정.
/// 공개 CLI 정본 = agent-wiki. knowledge-base-wiki·memo-citation-ledger 는 호환 별칭.
public enum DualEntry: Sendable {
    public static let profile = DualEntryProfile(
        mode: .helpers,
        guiExecutableName: "KnowledgeBaseWiki",
        cliProductName: "agent-wiki",
        cliAliases: ["knowledge-base-wiki", "memo-citation-ledger"],
        cliSubcommands: [
            "help", "--help", "-h", "version", "--version", "list", "search", "context", "path", "show",
            "publish", "tick", "agent", "verify", "checkpoint", "schedule", "install",
            "capabilities", "root", "init", "world", "backup", "event", "graph",
            "app", "review", "blob", "diff", "recent", "changes", "discuss",
            "learn", "metrics", "rules", "index", "migrate", "capture", "history",
            "cited-by", "rollback", "task", "orchestration", "batch", "okf-export", "distill",
            "repository", "promotion", "repository-summary", "promote", "dual-entry", "classify",
            "skill-install", "skill-uninstall", "skill-status", "skill", "skills",
        ],
        stampHomeRelativeDir: ".memo-citation-ledger",
        stampFileName: "cli-install-version",
        // Studio Helpers `agent-wiki` 실측 ~11.2 MB (2026-08-20). GUI MacOS 바이너리와
        // 크기만으로 가르던 한도(10 MB)가 CLI를 가장으로 오인했다. Helpers 경로는
        // DualEntryRules 에서 크기와 무관하게 CLI 로 본다.
        maxSafeCLIBytes: 20_000_000,
        versionProbeEnvKey: "MEMO_LEDGER_VERSION_PROBE"
    )

    public static var guiExecutableName: String { profile.guiExecutableName }
    public static var cliProductName: String { profile.cliProductName }
    public static var cliAliasName: String { profile.cliAliases.first ?? "memo-citation-ledger" }
    public static var cliNames: Set<String> { profile.cliNames }
    public static var cliSubcommands: Set<String> { profile.cliSubcommands }
    public static var maxSafeCLIBytes: UInt64 { profile.maxSafeCLIBytes }

    public static var installStampURL: URL {
        DualEntryRules.installStampURL(profile: profile)
    }

    public static func isMisusedAsCLI(arguments: [String] = CommandLine.arguments) -> Bool {
        DualEntryRules.isMisusedAsCLI(profile: profile, arguments: arguments)
    }

    public static func isSafeCLIExecutable(_ path: String) -> Bool {
        DualEntryRules.isSafeCLIExecutable(path, profile: profile)
    }

    public static func isGUIMasquerading(at path: String) -> Bool {
        DualEntryRules.isGUIMasquerading(at: path, profile: profile)
    }

    public static func embeddedHelperURL(bundle: Bundle = .main) -> URL? {
        DualEntryRules.embeddedHelperURL(profile: profile, bundle: bundle)
    }

    public static func resolveCLIPath(
        candidates: [String]? = nil,
        preferEmbeddedHelper: Bool = false,
        bundle: Bundle = .main
    ) -> String? {
        DualEntryRules.resolveCLIPath(
            profile: profile,
            candidates: candidates,
            preferEmbeddedHelper: preferEmbeddedHelper,
            bundle: bundle
        )
    }

    public static func defaultCLICandidates() -> [String] {
        DualEntryRules.defaultCLICandidates(profile: profile)
    }

    public static func writeInstallStamp(version: String = LedgerVersion.current) throws {
        try DualEntryRules.writeInstallStamp(profile: profile, version: version)
    }

    public static func readInstallStamp() -> String? {
        DualEntryRules.readInstallStamp(profile: profile)
    }

    /// 스탬프가 앱 버전과 같으면 스탬프를 쓴다. 다르면(배포 도구는 스탬프를 쓰지 않으므로 ship 직후 흔하다)
    /// PATH CLI 의 `version` 을 한 번 다시 물어 실제 값을 쓴다. 스탬프 갱신은 CLI `version` 쪽 몫이라 여기서 쓰지 않는다.
    public static func installedCLIVersion(
        expected: String = LedgerVersion.current,
        allowProcessProbe: Bool = true
    ) -> String {
        resolveInstalledCLIVersion(
            expected: expected,
            allowProcessProbe: allowProcessProbe,
            readStamp: { readInstallStamp() },
            probe: { probeCLIVersion() },
            fallback: {
                DualEntryRules.installedCLIVersion(
                    profile: profile, expected: expected, allowProcessProbe: allowProcessProbe)
            }
        )
    }

    /// 순수 판정부(프로세스·스탬프 파일은 주입). 테스트가 실제 홈을 건드리지 않게 분리했다.
    static func resolveInstalledCLIVersion(
        expected: String,
        allowProcessProbe: Bool,
        readStamp: () -> String?,
        probe: () -> String?,
        fallback: () -> String
    ) -> String {
        guard let stamp = readStamp(), !stamp.isEmpty else { return fallback() }
        if stamp == expected || !allowProcessProbe { return stamp }
        if let live = probe(), !live.isEmpty { return live }
        return stamp
    }

    /// PATH CLI `version` 1회(2초 제한). 안전한 실 CLI 가 아니거나 실패하면 nil.
    static func probeCLIVersion() -> String? {
        guard let path = resolveCLIPath() else { return nil }
        var env = ProcessInfo.processInfo.environment
        if env[profile.versionProbeEnvKey] == "1" { return nil }
        env[profile.versionProbeEnvKey] = "1"
        let result = SafeProcessRunner.run(path, ["version"], environment: env, timeout: 2)
        guard result.exitCode == 0 else { return nil }
        let out = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty || out.contains("error") ? nil : out
    }

    public typealias Diagnosis = DualEntryRules.Diagnosis

    public static func diagnose(candidates: [String]? = nil) -> Diagnosis {
        DualEntryRules.diagnose(profile: profile, candidates: candidates)
    }
}
