import InteropKit
import Foundation
import LocalizationKit
import CommandKit
import StateRootKit

/// full CLI dual-entry 상태 진단(읽기 전용). PATH 쓰기(adopt/install)는 배포 도구(app-build-manager ship)만 한다.
/// 여기 남은 것은 PATH·Helpers 상태를 읽어 보고하는 진단뿐이다. GUI 바이너리는 PATH 에 두지 않는다.
/// - GUI 바이너리를 PATH 에 심지 않는다 (dual-entry hang)
public enum DualEntryAdoption: Sendable {
    public static let fullCLIName = "agent-wiki"
    public static let studioCLIName = "agent-wiki-studio"
    public static let aliases = ["knowledge-base-wiki", "memo-citation-ledger"]

    /// monlith 앱 번들 후보 (Display 이름 순).
    public static let monlithAppNames = ["Agent Wiki.app", "KnowledgeBaseWiki.app"]
    /// ADM ship 정본 이름 우선, 옛 Display 이름 폴백.
    public static let studioAppNames = ["AgentWikiStudio.app", "Agent Wiki Studio.app"]

    public static let maxSafeCLIBytes: UInt64 = 20_000_000

    public struct Paths: Equatable, Sendable {
        public var monlithHelper: String?
        public var studioHelper: String?
        public var pathCLI: String?
        public var studioApp: String?
        public var monlithApp: String?
        /// adopt 시 복사 원본으로 쓸 경로 (monlith helper → PATH 순)
        public var adoptSource: String?
    }

    public struct Status: Equatable, Sendable {
        public var paths: Paths
        public var monlithHelperOK: Bool
        public var studioHelperOK: Bool
        public var pathPointsToStudio: Bool
        public var pathIsSafeCLI: Bool
        public var checklist: [String: Bool]

        /// Studio 앱 + 안전한 full CLI 바이너리 원본 1개 이상
        public var readyToAdopt: Bool { paths.studioApp != nil && paths.adoptSource != nil }
        public var adopted: Bool { studioHelperOK && pathPointsToStudio && pathIsSafeCLI }
    }

    public static func resolveApplications() -> Paths {
        let apps = "/Applications"
        func firstApp(_ names: [String]) -> String? {
            names.map { "\(apps)/\($0)" }.first { FileManager.default.fileExists(atPath: $0) }
        }
        let monlithApp = firstApp(monlithAppNames)
        let studioApp = firstApp(studioAppNames)
        let monlithHelper = monlithApp.map { "\($0)/Contents/Helpers/\(fullCLIName)" }
            .flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
        let studioHelper = studioApp.map { "\($0)/Contents/Helpers/\(fullCLIName)" }
            .flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
        let pathCLI = resolveOnPATH(fullCLIName)
        // 원본 우선순위: Studio 로컬 빌드 → monlith Helpers → PATH
        let studioBuilt = resolveStudioBuiltCLI()
        let adoptSource: String? = {
            if let s = studioBuilt, isSafeCLIExecutable(s) { return s }
            if let m = monlithHelper, isSafeCLIExecutable(m) { return m }
            if let p = pathCLI, isSafeCLIExecutable(p) { return p }
            return nil
        }()
        return Paths(
            monlithHelper: monlithHelper,
            studioHelper: studioHelper,
            pathCLI: pathCLI,
            studioApp: studioApp,
            monlithApp: monlithApp,
            adoptSource: adoptSource
        )
    }


    /// Studio package `.build/**/agent-wiki` (debug/release) if present.
    public static func resolveStudioBuiltCLI() -> String? {
        let env = ProcessInfo.processInfo.environment["AGENT_WIKI_STUDIO_PACKAGE"]
        var roots: [String] = []
        if let env, !env.isEmpty { roots.append(env) }
        roots.append(contentsOf: [
            StateRootKit.path("Documents/WORK/WORKSPACE/apps/swift-app-mono/main/apps/agent-wiki-studio-swift"),
            StateRootKit.path("Documents/WORK/WORKSPACE/apps/swift-app-mono/.worktrees/main/apps/agent-wiki-studio-swift"),
        ])
        let suffixes = [
            "/.build/arm64-apple-macosx/release/agent-wiki",
            "/.build/arm64-apple-macosx/debug/agent-wiki",
            "/.build/release/agent-wiki",
            "/.build/debug/agent-wiki",
        ]
        for root in roots {
            for suf in suffixes {
                let path = root + suf
                if isSafeCLIExecutable(path) { return path }
            }
        }
        return nil
    }

    public static func resolveOnPATH(_ name: String) -> String? {
        let candidates = [
            HostPlatform.cliBinPath(name),
            "/usr/local/bin/\(name)",
            StateRootKit.path(".local/bin/\(name)"),
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        return nil
    }

    public static func isSafeCLIExecutable(_ path: String) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else { return false }
        guard fm.isExecutableFile(atPath: path) else { return false }
        // GUI masquerade: never MacOS/ product
        if path.contains(".app/Contents/MacOS/") { return false }
        let base = (path as NSString).lastPathComponent
        if base == "KnowledgeBaseWiki" || base == "AgentWikiStudio" || base == "AgentWikiReader" {
            return false
        }
        do {
            let attrs = try fm.attributesOfItem(atPath: path)
            if let size = attrs[.size] as? UInt64, size > maxSafeCLIBytes {
                return false
            }
        } catch {
            fputs("warning: attributesOfItem \(path): \(error.localizedDescription)\n", stderr)
            return false
        }
        return true
    }

    public static func status(paths: Paths = resolveApplications()) -> Status {
        // monlith 는 GUI-only 가능 — Helpers/agent-wiki 없으면 OK, 있으면 안전해야 함.
        let monOK: Bool = {
            guard let h = paths.monlithHelper else { return true }
            return isSafeCLIExecutable(h)
        }()
        let stuOK = paths.studioHelper.map(isSafeCLIExecutable) ?? false
        let pathSafe = paths.pathCLI.map(isSafeCLIExecutable) ?? false
        // install 은 PATH 로 **복사** 한다(심링크 아님). Studio 승계 판정:
        // 1) PATH 가 Studio 번들 안이거나 2) Studio Helpers 와 바이트 동일.
        let pathStudio: Bool = {
            guard let path = paths.pathCLI else { return false }
            if let studioApp = paths.studioApp {
                let realPath = (try? fmReal(path)) ?? path
                if realPath.hasPrefix(studioApp + "/") { return true }
            }
            guard let studio = paths.studioHelper else { return false }
            return filesEqual(path, studio)
        }()
        let checklist: [String: Bool] = [
            "studio_app_present": paths.studioApp != nil,
            "adopt_source_safe": paths.adoptSource.map(isSafeCLIExecutable) ?? false,
            "monlith_helper_safe": monOK,
            "studio_helper_agent_wiki": stuOK,
            "path_agent_wiki_safe": pathSafe,
            "path_points_to_studio": pathStudio,
        ]
        return Status(
            paths: paths,
            monlithHelperOK: monOK,
            studioHelperOK: stuOK,
            pathPointsToStudio: pathStudio,
            pathIsSafeCLI: pathSafe,
            checklist: checklist
        )
    }

    private static func fmReal(_ path: String) throws -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    private static func filesEqual(_ a: String, _ b: String) -> Bool {
        let fm = FileManager.default
        guard let da = fm.contents(atPath: a), let db = fm.contents(atPath: b) else { return false }
        return da == db
    }
}
