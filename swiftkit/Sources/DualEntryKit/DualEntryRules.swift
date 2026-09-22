import Foundation
import InstallHealthKit
import InteropKit
import StateRootKit

/// GUI/CLI dual-entry 안전 규칙 (앱 공용).
///
/// 사고(2026-07-25~26): PATH 가 GUI(`…/MacOS/…`) 를 가리키면 version/list 가 AppKit 을
/// 폭주시켜 WindowServer hang. 규칙은 profile 단위로 적용.
public enum DualEntryRules: Sendable {
    /// GUI 바이너리가 CLI 로 오호출됐으면 true (호출측은 exit 64).
    /// helpers 모드에서만 의미 있음 — argv 단일 바이너리는 CLI 처리를 같은 프로세스가 함.
    /// helpers CLI → 앱 본체 위임임을 알리는 표식. `DualEntryDelegate.exec` 이 심는다.
    public static let delegationMarkerKey = "SWIFT_APP_DUAL_ENTRY_DELEGATED"
    public static let delegationMarkerValue = "1"

    public static func isMisusedAsCLI(
        profile: DualEntryProfile,
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard profile.mode == .helpers || profile.mode == .cliOnly else { return false }
        // helpers CLI 가 일부러 넘긴 호출은 오호출이 아니다.
        //
        // 이 예외가 없으면 `DualEntryDelegate` 와 이 가드가 서로 싸운다. Delegate 는
        // argv0 을 `/Applications/<App>.app/Contents/MacOS/<Gui>` 로 두고 exec 하는데,
        // 아래 realpath 규칙이 그 형태를 무조건 오호출로 본다. 실측(2026-08-05):
        // rightclick 은 그래서 `reload` 를 PATH 로도 앱 본체로도 실행할 수 없었다.
        //
        // 가드가 막으려던 것은 **PATH 에 GUI 를 심링크해 놓고 아무나 부르는 것**이지,
        // 자기 앱의 CLI 가 명시적으로 넘기는 것이 아니다. 화면 기록처럼 TCC 주체가
        // 번들이어야 하는 명령은 이 경로로만 옳게 돈다.
        if environment[delegationMarkerKey] == delegationMarkerValue { return false }
        guard let first = arguments.first else { return false }
        let argv0 = URL(fileURLWithPath: first).lastPathComponent
        if profile.cliNames.contains(argv0) { return true }
        if arguments.count >= 2, profile.cliSubcommands.contains(arguments[1]) { return true }
        // 권한 관리 앱이 대상 GUI 번들에 전달하는 내부 1회성 요청이다. 이 인자는
        // 앱의 PermissionBootstrap만 처리하며 CLI 서브커맨드가 아니므로 GUI 실행을 막지 않는다.
        if arguments.count == 2, arguments[1].hasPrefix("--permission-bootstrap=") { return false }
        // AppKit이 GUI 실행에 전달하는 -NS… 인자는 CLI 서브커맨드가 아니다.
        // 이를 막으면 문서 복원·디버그 실행처럼 정상 GUI 실행까지 exit 64로 끝난다.
        if arguments.count >= 2, arguments[1].hasPrefix("-NS") { return false }
        // PATH 가 MacOS 로 잘못 심링크된 경우: realpath 가 Contents/MacOS 이고
        // 서브커맨드가 있으면 CLI 오호출. 빈 argv(더블클릭 GUI)는 허용.
        // version 이 subcommands 목록에 없어도 hang 전에 막는다(2026-08-01 실측).
        if arguments.count >= 2 {
            let resolved = (first as NSString).resolvingSymlinksInPath
            if resolved.contains(".app/Contents/MacOS/") { return true }
        }
        return false
    }

    /// CLI 이름/서브커맨드로 GUI 가 뜨면 즉시 종료 (helpers 전용).
    public static func exitIfMisusedAsCLI(
        profile: DualEntryProfile,
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        code: Int32 = 64
    ) {
        guard isMisusedAsCLI(profile: profile, arguments: arguments, environment: environment) else { return }
        let argv0 = URL(fileURLWithPath: arguments.first ?? "").lastPathComponent
        let detail = profile.cliNames.contains(argv0)
            ? "argv0=\(argv0)"
            : "subcommand=\(arguments.dropFirst().first ?? "?")"
        let message = """
        error: GUI binary \(profile.guiExecutableName) invoked as CLI (\(detail)).
        PATH CLI is the Helpers symlink inside the app — ship the app (`app-build-manager ship`).
        Never symlink .app/Contents/MacOS/\(profile.guiExecutableName) to brew bin.
        """
        FileHandle.standardError.write(Data(message.utf8))
        exit(code)
    }

    /// ship 번들 Resources/package-identity.json 기준 가드 (helpers 만 차단).
    /// GUI `@main` init 한 줄: `DualEntryRules.exitIfMisusedFromIdentity()`
    public static func exitIfMisusedFromIdentity(
        bundle: Bundle = .main,
        arguments: [String] = CommandLine.arguments,
        code: Int32 = 64
    ) {
        // 낡은 설치본은 **옛 코드의 답**을 낸다. 이 저장소의 검사·연동은 대부분
        // 설치본을 부르므로 그 답이 조용히 사실로 굳는다 — 실측 2026-08-10,
        // 낡은 감사기가 이미 고쳐진 결함 16건을 계속 보고해 없는 문제를 다시
        // 설계할 뻔했다. 모든 CLI 가 이 진입 한 줄을 부르니 여기서 한 번 말한다.
        // stderr 한 줄이고 색인 파일 1회 읽기다 — stdout(JSON)은 건드리지 않는다.
        StaleInstallIndex.warnIfStale(arguments: arguments)
        guard let profile = DualEntryProfile.loadFromPackageIdentity(bundle: bundle) else { return }
        exitIfMisusedAsCLI(profile: profile, arguments: arguments, code: code)
    }

    public static func isGUIMasquerading(at path: String, profile: DualEntryProfile) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }
        let resolved = (path as NSString).resolvingSymlinksInPath
        if resolved.contains(".app/Contents/MacOS/") { return true }
        if (resolved as NSString).lastPathComponent == profile.guiExecutableName { return true }
        // Helpers 는 dual-entry 정본 CLI. 크기 한도는 PATH 에 복사된 GUI 가장만 잡는다.
        if resolved.contains(".app/Contents/Helpers/") { return false }
        do {
            let attrs = try fm.attributesOfItem(atPath: resolved)
            if let size = attrs[.size] as? NSNumber,
               size.uint64Value > profile.maxSafeCLIBytes {
                return true
            }
        } catch {}
        return false
    }

    public static func isSafeCLIExecutable(_ path: String, profile: DualEntryProfile) -> Bool {
        guard !path.isEmpty else { return false }
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: path) else { return false }
        if isGUIMasquerading(at: path, profile: profile) { return false }
        let resolved = (path as NSString).resolvingSymlinksInPath
        if resolved.contains(".app/Contents/Helpers/") { return true }
        if let selfURL = Bundle.main.executableURL?.resolvingSymlinksInPath(),
           resolved == selfURL.path,
           selfURL.lastPathComponent == profile.guiExecutableName {
            return false
        }
        return true
    }

    public static func embeddedHelperURL(
        profile: DualEntryProfile,
        bundle: Bundle = .main
    ) -> URL? {
        let helpers = bundle.bundleURL
            .appendingPathComponent("Contents/Helpers/\(profile.cliProductName)", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: helpers.path) { return helpers }
        let alt = bundle.bundleURL
            .appendingPathComponent("Helpers/\(profile.cliProductName)", isDirectory: false)
        if FileManager.default.isExecutableFile(atPath: alt.path) { return alt }
        return nil
    }

    public static func defaultCLICandidates(profile: DualEntryProfile) -> [String] {
        let home = StateRootKit.resolveHost()
        var paths: [String] = []
        let names = [profile.cliProductName] + profile.cliAliases
        for name in names {
            paths.append(HostPlatform.cliBinPath(name))
            paths.append("/usr/local/bin/\(name)")
            paths.append("\(home)/.local/bin/\(name)")
        }
        return paths
    }

    public static func resolveCLIPath(
        profile: DualEntryProfile,
        candidates: [String]? = nil,
        preferEmbeddedHelper: Bool = false,
        bundle: Bundle = .main
    ) -> String? {
        var list = candidates ?? defaultCLICandidates(profile: profile)
        if let helper = embeddedHelperURL(profile: profile, bundle: bundle) {
            if preferEmbeddedHelper {
                list.insert(helper.path, at: 0)
            } else {
                list.append(helper.path)
            }
        }
        for path in list where isSafeCLIExecutable(path, profile: profile) {
            return path
        }
        return nil
    }

    public static func installStampURL(profile: DualEntryProfile) -> URL {
        StateRootKit.url(profile.stampHomeRelativeDir)
            .appendingPathComponent(profile.stampFileName, isDirectory: false)
    }

    public static func writeInstallStamp(profile: DualEntryProfile, version: String) throws {
        let url = installStampURL(profile: profile)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let body = """
        \(version)
        # dual-entry install stamp (\(profile.cliProductName))
        """
        try body.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func readInstallStamp(profile: DualEntryProfile) -> String? {
        let url = installStampURL(profile: profile)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let line = text.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("#") }
        guard let line, !line.isEmpty else { return nil }
        return line
    }

    /// 스탬프 우선, 안전할 때만 `version` 1회 (2초 워치독).
    public static func installedCLIVersion(
        profile: DualEntryProfile,
        expected: String? = nil,
        allowProcessProbe: Bool = true
    ) -> String {
        if let stamp = readInstallStamp(profile: profile), !stamp.isEmpty {
            return stamp
        }
        #if os(iOS)
        return ""
        #else
        guard allowProcessProbe, let path = resolveCLIPath(profile: profile) else { return "" }
        if ProcessInfo.processInfo.environment[profile.versionProbeEnvKey] == "1" { return "" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["version"]
        var env = ProcessInfo.processInfo.environment
        env[profile.versionProbeEnvKey] = "1"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ""
        }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            let killBy = Date().addingTimeInterval(0.5)
            while process.isRunning, Date() < killBy {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            return ""
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !out.isEmpty {
            let ok = expected.map { out == $0 || !out.contains("error") } ?? !out.contains("error")
            if ok { try? writeInstallStamp(profile: profile, version: out) }
        }
        return out
        #endif
    }

    public struct Diagnosis: Sendable, Equatable {
        public var ok: Bool
        public var path: String?
        public var issues: [String]
        public var stamp: String?

        public init(ok: Bool, path: String?, issues: [String], stamp: String?) {
            self.ok = ok
            self.path = path
            self.issues = issues
            self.stamp = stamp
        }
    }

    public static func diagnose(
        profile: DualEntryProfile,
        candidates: [String]? = nil
    ) -> Diagnosis {
        let list = candidates ?? defaultCLICandidates(profile: profile)
        var issues: [String] = []
        let fm = FileManager.default
        var firstSafe: String?
        for path in list {
            guard fm.fileExists(atPath: path) else { continue }
            if isGUIMasquerading(at: path, profile: profile) {
                let resolved = (path as NSString).resolvingSymlinksInPath
                issues.append("GUI masquerade: \(path) → \(resolved)")
                continue
            }
            if isSafeCLIExecutable(path, profile: profile), firstSafe == nil {
                firstSafe = (path as NSString).resolvingSymlinksInPath
            }
        }
        if firstSafe == nil {
            issues.append(
                "no safe CLI on PATH — ship the app so Helpers is on PATH (not a second install-cli axis)"
            )
        }
        return Diagnosis(
            ok: issues.isEmpty && firstSafe != nil,
            path: firstSafe,
            issues: issues,
            stamp: readInstallStamp(profile: profile)
        )
    }
}
