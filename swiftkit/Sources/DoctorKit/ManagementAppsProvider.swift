import Foundation
import InteropKit

/// Inventories fleet **management** apps and folds their health reports into DoctorKit.
///
/// Why: agents re-discovered path-cli-health / agent-cli-manager after ad-hoc symlink thrash
/// (2026-08). Doctor must pull those owners itself so PATH dual-entry gaps surface in one scan.
public struct ManagementAppsDoctorProvider: DoctorProvider {
    public let id = "management-apps"

    public struct ProbeHooks: Sendable {
        public var resolveOnPath: (@Sendable (String, [String]) -> String?)?
        public var isSymlink: (@Sendable (String) -> Bool)?
        public var readlink: (@Sendable (String) -> String?)?
        public var appInstalled: (@Sendable (String, [String]) -> Bool)?
        public var runCLI: (@Sendable (String, [String], TimeInterval) -> (exit: Int32, stdout: String))?

        public init(
            resolveOnPath: (@Sendable (String, [String]) -> String?)? = nil,
            isSymlink: (@Sendable (String) -> Bool)? = nil,
            readlink: (@Sendable (String) -> String?)? = nil,
            appInstalled: (@Sendable (String, [String]) -> Bool)? = nil,
            runCLI: (@Sendable (String, [String], TimeInterval) -> (exit: Int32, stdout: String))? = nil
        ) {
            self.resolveOnPath = resolveOnPath
            self.isSymlink = isSymlink
            self.readlink = readlink
            self.appInstalled = appInstalled
            self.runCLI = runCLI
        }
    }

    private let apps: [ManagementAppSpec]
    private let pathRoots: [String]
    private let applicationsDirectory: String
    private let resolveOnPath: @Sendable (String, [String]) -> String?
    private let isSymlink: @Sendable (String) -> Bool
    private let readlink: @Sendable (String) -> String?
    private let appInstalled: @Sendable (String, [String]) -> Bool
    private let runCLI: @Sendable (String, [String], TimeInterval) -> (exit: Int32, stdout: String)
    private let pullExternalReports: Bool

    public init(
        apps: [ManagementAppSpec] = ManagementAppCatalog.builtIn,
        pathRoots: [String] = HostPlatform.standardBinPaths,
        applicationsDirectory: String = "/Applications",
        hooks: ProbeHooks = ProbeHooks(),
        pullExternalReports: Bool = true
    ) {
        self.apps = apps
        self.pathRoots = pathRoots
        self.applicationsDirectory = applicationsDirectory
        self.resolveOnPath = hooks.resolveOnPath ?? Self.defaultResolve
        self.isSymlink = hooks.isSymlink ?? { path in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return false }
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: path)
                if let t = attrs[.type] as? FileAttributeType {
                    return t == .typeSymbolicLink
                }
            } catch {}
            let url = URL(fileURLWithPath: path)
            do {
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                return values.isSymbolicLink == true
            } catch {
                return false
            }
        }
        self.readlink = hooks.readlink ?? { path in
            do {
                let t = try FileManager.default.destinationOfSymbolicLink(atPath: path)
                if t.hasPrefix("/") { return t }
                let parent = (path as NSString).deletingLastPathComponent
                return (parent as NSString).appendingPathComponent(t)
            } catch {
                return nil
            }
        }
        self.appInstalled = hooks.appInstalled ?? { appsDir, names in
            names.contains { name in
                let p = (appsDir as NSString).appendingPathComponent("\(name).app")
                return FileManager.default.fileExists(atPath: p)
            }
        }
        self.runCLI = hooks.runCLI ?? Self.defaultRunCLI
        self.pullExternalReports = pullExternalReports
    }

    public func run() async -> [DoctorFinding] {
        var out: [DoctorFinding] = []
        out.append(contentsOf: inventoryFindings())
        out.append(contentsOf: helpersContractFindings())
        if pullExternalReports {
            out.append(contentsOf: ManagementExternalReports(
                pathRoots: pathRoots,
                resolveOnPath: resolveOnPath,
                runCLI: runCLI,
                source: id
            ).pullAll())
        }
        if out.isEmpty {
            out.append(DoctorFinding(
                category: .management,
                severity: .ok,
                body: .init(
                    subject: "management",
                    title: "관리 앱 점검 통과",
                    detail: "catalog empty or all ok"
                ),
                source: id
            ))
        }
        return out
    }

    func inventoryFindings() -> [DoctorFinding] {
        apps.flatMap { inventory(for: $0) }
    }

    func helpersContractFindings() -> [DoctorFinding] {
        ManagementHelpersContract.findings(
            applicationsDirectory: applicationsDirectory,
            pathRoots: pathRoots,
            resolveOnPath: resolveOnPath,
            isSymlink: isSymlink,
            readlink: readlink,
            source: id
        )
    }

    static func helpersProductName(from identity: [String: Any]) -> String? {
        ManagementHelpersContract.helpersProductName(from: identity)
    }

    private func inventory(for app: ManagementAppSpec) -> [DoctorFinding] {
        var out: [DoctorFinding] = []
        let path = resolveOnPath(app.cli, pathRoots)
        let installed = app.appBundleNames.isEmpty
            ? true
            : appInstalled(applicationsDirectory, app.appBundleNames)

        if path == nil {
            out.append(DoctorFinding(
                category: .management,
                severity: app.critical ? .fail : .warn,
                body: .init(
                    subject: app.cli,
                    title: "관리 CLI PATH에 없음: \(app.displayName)",
                    detail: "\(app.role). expected in \(pathRoots.joined(separator: ", "))",
                    remedy: "app-build-manager ship apps/\(app.id)-swift release  (또는 해당 앱 디렉터리)"
                ),
                source: id,
                payload: ["cli": app.cli, "kind": "missing_path"]
            ))
        } else if let path, app.expectsHelpersSymlink {
            let linked = isSymlink(path)
            if !linked {
                out.append(DoctorFinding(
                    category: .management,
                    severity: .fail,
                    body: .init(
                        subject: app.cli,
                        title: "관리 CLI 가 plain 사본 (dual-entry 깨짐): \(app.displayName)",
                        detail: "\(path) 가 Helpers 심링크가 아니라 파일 사본이다. "
                            + "ship 이후 cp 로 PATH 를 덮으면 낡은 dual-entry stub 이 살아 남는다 "
                            + "(실측: agent-cli-manager help 만 응답). \(app.role)",
                        remedy: "path-cli-health repair-copies --apply  또는  "
                            + "rm \(path) && app-build-manager ship <앱> release"
                    ),
                    source: id,
                    payload: ["cli": app.cli, "path": path, "kind": "plain_copy"]
                ))
            } else if let target = readlink(path) {
                let helpersOK = target.contains("/Contents/Helpers/")
                if !helpersOK {
                    out.append(DoctorFinding(
                        category: .management,
                        severity: .warn,
                        body: .init(
                            subject: app.cli,
                            title: "관리 CLI 심링크가 Helpers 가 아님: \(app.displayName)",
                            detail: "\(path) → \(target). dual-entry 계약은 Contents/Helpers/<cli>.",
                            remedy: "app-build-manager ship <앱> release 로 Helpers 링크 재설치"
                        ),
                        source: id,
                        payload: ["cli": app.cli, "path": path, "target": target, "kind": "bad_symlink"]
                    ))
                } else if installed {
                    out.append(DoctorFinding(
                        category: .management,
                        severity: .ok,
                        body: .init(
                            subject: app.cli,
                            title: "관리 앱 OK: \(app.displayName)",
                            detail: "\(path) → \(target). \(app.role)"
                        ),
                        source: id,
                        payload: ["cli": app.cli, "path": path, "target": target, "kind": "ok"]
                    ))
                }
            }
        } else if let path {
            out.append(DoctorFinding(
                category: .management,
                severity: .ok,
                body: .init(
                    subject: app.cli,
                    title: "관리 CLI 존재: \(app.displayName)",
                    detail: "\(path). \(app.role)"
                ),
                source: id,
                payload: ["cli": app.cli, "path": path, "kind": "present"]
            ))
        }

        if !app.appBundleNames.isEmpty && !installed {
            out.append(DoctorFinding(
                category: .management,
                severity: app.critical ? .fail : .warn,
                body: .init(
                    subject: app.cli,
                    title: "관리 앱 미설치: \(app.displayName)",
                    detail: "\(applicationsDirectory) 에 \(app.appBundleNames.joined(separator: " | ")).app 없음. \(app.role)",
                    remedy: "app-build-manager ship apps/\(app.id)-swift release"
                ),
                source: id,
                payload: ["cli": app.cli, "kind": "missing_app"]
            ))
        }

        return out
    }

    private static func defaultResolve(cli: String, roots: [String]) -> String? {
        for root in roots {
            let p = (root as NSString).appendingPathComponent(cli)
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        let (code, out) = defaultRunCLI("/usr/bin/which", [cli], 5)
        if code == 0 {
            let p = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !p.isEmpty { return p }
        }
        return nil
    }

    internal static func defaultRunCLI(
        _ exe: String,
        _ args: [String],
        _ timeout: TimeInterval
    ) -> (exit: Int32, stdout: String) {
        let p = Process()
        if exe.contains("/") {
            p.executableURL = URL(fileURLWithPath: exe)
            p.arguments = args
        } else {
            p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            p.arguments = [exe] + args
        }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do {
            try p.run()
            let item = DispatchWorkItem { p.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: item)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            item.cancel()
            let s = String(data: data, encoding: .utf8) ?? ""
            return (p.terminationStatus, s)
        } catch {
            return (127, "")
        }
    }
}
