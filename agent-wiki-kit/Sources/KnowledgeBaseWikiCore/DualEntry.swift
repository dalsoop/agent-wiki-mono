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

    public static func installedCLIVersion(
        expected: String = LedgerVersion.current,
        allowProcessProbe: Bool = true
    ) -> String {
        DualEntryRules.installedCLIVersion(
            profile: profile,
            expected: expected,
            allowProcessProbe: allowProcessProbe
        )
    }

    public typealias Diagnosis = DualEntryRules.Diagnosis

    public static func diagnose(candidates: [String]? = nil) -> Diagnosis {
        DualEntryRules.diagnose(profile: profile, candidates: candidates)
    }
}
