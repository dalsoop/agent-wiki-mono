import Foundation

/// package-identity.dual_entry 값.
public enum DualEntryMode: String, Sendable, Equatable {
    case helpers
    case argv
    case cliOnly = "cli_only"
}

/// dual-entry 앱 프로파일 — identity.cli / gui / helpers 계약의 런타임 표현.
///
/// 정본: gujo wiki dual-entry hang · package-identity.dual_entry
public struct DualEntryProfile: Sendable, Equatable {
    public var mode: DualEntryMode
    public var guiExecutableName: String
    public var cliProductName: String
    public var cliAliases: [String]
    /// GUI 가 argv 로 받으면 오호출로 보는 CLI 서브커맨드.
    public var cliSubcommands: Set<String>
    /// install stamp 디렉터리 (~/.<name>/)
    public var stampHomeRelativeDir: String
    public var stampFileName: String
    /// 이 크기 초과 실행 파일은 GUI masquerade 로 본다 (기본 5MB).
    public var maxSafeCLIBytes: UInt64
    /// version 프로브 재진입 방지 env 키.
    public var versionProbeEnvKey: String

    public init(
        mode: DualEntryMode = .helpers,
        guiExecutableName: String,
        cliProductName: String,
        cliAliases: [String] = [],
        cliSubcommands: Set<String> = DualEntryProfile.defaultCLISubcommands,
        stampHomeRelativeDir: String,
        stampFileName: String = "cli-install-version",
        maxSafeCLIBytes: UInt64 = 5_000_000,
        versionProbeEnvKey: String = "DUAL_ENTRY_VERSION_PROBE"
    ) {
        self.mode = mode
        self.guiExecutableName = guiExecutableName
        self.cliProductName = cliProductName
        self.cliAliases = cliAliases
        self.cliSubcommands = cliSubcommands
        self.stampHomeRelativeDir = stampHomeRelativeDir
        self.stampFileName = stampFileName
        self.maxSafeCLIBytes = maxSafeCLIBytes
        self.versionProbeEnvKey = versionProbeEnvKey
    }

    /// Bundle Resources/package-identity.json (ship 번들) 에서 로드.
    public static func loadFromPackageIdentity(bundle: Bundle = .main) -> DualEntryProfile? {
        let candidates: [URL] = [
            bundle.url(forResource: "package-identity", withExtension: "json"),
            bundle.bundleURL.appendingPathComponent("Contents/Resources/package-identity.json"),
            bundle.bundleURL.appendingPathComponent("package-identity.json"),
        ].compactMap { $0 }
        for url in candidates {
            if let p = load(from: url) { return p }
        }
        return nil
    }

    public static func load(from url: URL) -> DualEntryProfile? {
        guard let data = try? Data(contentsOf: url),
              let obj = DualEntryJSON.object(from: data)
        else { return nil }
        let cli = (obj["cli_product"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? (obj["cli"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard !cli.isEmpty else { return nil }
        let gui = (obj["gui_product"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? cli
        let modeRaw = (obj["dual_entry"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let mode = DualEntryMode(rawValue: modeRaw)
            ?? (gui != cli ? .helpers : .argv)
        let aliases = (obj["cli_aliases"] as? [String]) ?? []
        let stampDir = ".\(cli)"
        return DualEntryProfile(
            mode: mode,
            guiExecutableName: gui,
            cliProductName: cli,
            cliAliases: aliases,
            stampHomeRelativeDir: stampDir
        )
    }

    public var cliNames: Set<String> {
        Set([cliProductName] + cliAliases)
    }

    public static let defaultCLISubcommands: Set<String> = [
        "version", "--version", "-v", "help", "--help", "-h",
        "list", "status", "install", "doctor", "dual-entry",
        "check", "verify", "sync", "run", "start", "stop",
        // ProxmoxOperationsManager / common helpers
        "seed", "hosts", "guests", "refresh", "open",
    ]
}
