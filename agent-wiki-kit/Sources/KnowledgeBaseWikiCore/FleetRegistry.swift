import Foundation
import StateRootKit

/// 중앙 관제 레지스트리 — 지식 정본(각 world `.wiki`)이 아니라
/// monorepo·개인 원장의 **맵·가중치·건강** 만 둔다 (BMAD federated_knowledge 급).
/// 경로: `~/.memo-citation-ledger/fleet.json`
public struct FleetRegistry: Codable, Sendable, Equatable {
    public var version: Int
    public var workspaceRoots: [String]
    public var worlds: [FleetWorldEntry]

    public init(
        version: Int = 1,
        workspaceRoots: [String] = [],
        worlds: [FleetWorldEntry] = []
    ) {
        self.version = version
        self.workspaceRoots = workspaceRoots
        self.worlds = worlds
    }
}

public enum FleetWorldKind: String, Codable, Sendable, Equatable, CaseIterable {
    case personal
    case repo
    case unknown
}

public struct FleetWorldEntry: Codable, Sendable, Equatable, Identifiable {
    public var name: String
    public var rootPath: String
    public var kind: FleetWorldKind
    public var defaultWeight: Double
    public var enabled: Bool
    public var gitRemote: String?
    /// Stable logical owner for repo worlds. Optional for backward-compatible fleet.json decoding.
    public var repoId: String?
    public var normalizedGitRemote: String?
    /// Physical checkout instances observed for the same logical repository.
    public var worktreePaths: [String]?

    public var id: String { name }

    public init(
        name: String,
        rootPath: String,
        kind: FleetWorldKind = .unknown,
        defaultWeight: Double = 1.0,
        enabled: Bool = true,
        gitRemote: String? = nil,
        repoId: String? = nil,
        normalizedGitRemote: String? = nil,
        worktreePaths: [String]? = nil
    ) {
        self.name = name
        self.rootPath = rootPath
        self.kind = kind
        self.defaultWeight = defaultWeight
        self.enabled = enabled
        self.gitRemote = gitRemote
        self.repoId = repoId
        self.normalizedGitRemote = normalizedGitRemote
        self.worktreePaths = worktreePaths
    }
}

public enum FleetIssueSeverity: String, Codable, Sendable, Equatable {
    case error
    case warning
    case info
}

public struct FleetIssue: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var severity: FleetIssueSeverity
    public var code: String
    public var message: String
    public var world: String?

    public init(
        id: String,
        severity: FleetIssueSeverity,
        code: String,
        message: String,
        world: String? = nil
    ) {
        self.id = id
        self.severity = severity
        self.code = code
        self.message = message
        self.world = world
    }
}

public struct FleetDoctorReport: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var issues: [FleetIssue]
    public var worlds: [FleetWorldHealth]

    public init(generatedAt: Date = Date(), issues: [FleetIssue], worlds: [FleetWorldHealth]) {
        self.generatedAt = generatedAt
        self.issues = issues
        self.worlds = worlds
    }

    public var hasErrors: Bool { issues.contains { $0.severity == .error } }
}

public struct FleetWorldHealth: Codable, Sendable, Equatable {
    public var name: String
    public var rootPath: String
    public var exists: Bool
    public var hasObjectsDir: Bool
    public var absolutePath: Bool
    public var objectFileCount: Int?
    public var enabled: Bool
    public var kind: FleetWorldKind
    public var defaultWeight: Double

    public init(
        name: String,
        rootPath: String,
        exists: Bool,
        hasObjectsDir: Bool,
        absolutePath: Bool,
        objectFileCount: Int?,
        enabled: Bool,
        kind: FleetWorldKind,
        defaultWeight: Double
    ) {
        self.name = name
        self.rootPath = rootPath
        self.exists = exists
        self.hasObjectsDir = hasObjectsDir
        self.absolutePath = absolutePath
        self.objectFileCount = objectFileCount
        self.enabled = enabled
        self.kind = kind
        self.defaultWeight = defaultWeight
    }
}

/// `.wiki` 후보 (scan 결과) — register 전 미리보기.
public struct FleetScanCandidate: Codable, Sendable, Equatable {
    public var name: String
    public var rootPath: String
    public var kind: FleetWorldKind
    public var alreadyRegistered: Bool

    public init(name: String, rootPath: String, kind: FleetWorldKind, alreadyRegistered: Bool) {
        self.name = name
        self.rootPath = rootPath
        self.kind = kind
        self.alreadyRegistered = alreadyRegistered
    }
}

public enum FleetStoreError: Error, CustomStringConvertible, Equatable {
    case io(String)
    case invalidJSON(String)

    public var description: String {
        switch self {
        case .io(let s): return "fleet io: \(s)"
        case .invalidJSON(let s): return "fleet invalid json: \(s)"
        }
    }
}

public struct FleetStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL
    }

    public static var defaultURL: URL {
        URL(fileURLWithPath: StateRootKit.hostPath(".memo-citation-ledger/fleet.json"))
    }

    public func load() throws -> FleetRegistry {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return FleetRegistry()
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw FleetStoreError.io(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(FleetRegistry.self, from: data)
        } catch {
            throw FleetStoreError.invalidJSON(String(describing: error))
        }
    }

    public func save(_ registry: FleetRegistry) throws {
        let dir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(registry)
            try data.write(to: fileURL, options: .atomic)
        } catch let e as FleetStoreError {
            throw e
        } catch {
            throw FleetStoreError.io(error.localizedDescription)
        }
    }

    /// name 또는 rootPath 로 기존 항목을 갱신·추가.
    @discardableResult
    public func register(
        name: String,
        rootPath: String,
        kind: FleetWorldKind = .unknown,
        defaultWeight: Double = 1.0,
        enabled: Bool = true,
        gitRemote: String? = nil
    ) throws -> FleetRegistry {
        var reg = try load()
        let abs = (rootPath as NSString).expandingTildeInPath
        let standardized = URL(fileURLWithPath: abs).standardizedFileURL.path
        let inspected = kind == .repo ? GitRepositoryInspector.inspect(worldRoot: standardized) : nil
        let rawRemote = gitRemote ?? inspected?.remoteURL
        let normalized = rawRemote.flatMap { try? RepositoryIdentity.normalize(remoteURL: $0) }
        let repositoryID = normalized.map { RepositoryIdentity.repoID(normalizedRemote: $0) }
        if let repositoryID,
           let index = reg.worlds.firstIndex(where: { $0.repoId == repositoryID }) {
            var existing = reg.worlds[index]
            existing.enabled = enabled
            existing.defaultWeight = defaultWeight
            existing.gitRemote = rawRemote
            existing.repoId = repositoryID
            existing.normalizedGitRemote = normalized
            existing.worktreePaths = Array(Set(
                (existing.worktreePaths ?? [existing.rootPath]) + [standardized]
            )).sorted()
            reg.worlds[index] = existing
            try save(reg)
            return reg
        }
        reg.worlds.removeAll { $0.name == name || $0.rootPath == standardized }
        reg.worlds.append(FleetWorldEntry(
            name: name,
            rootPath: standardized,
            kind: kind,
            defaultWeight: defaultWeight,
            enabled: enabled,
            gitRemote: rawRemote,
            repoId: repositoryID,
            normalizedGitRemote: normalized,
            worktreePaths: kind == .repo ? [standardized] : nil
        ))
        reg.worlds.sort { $0.name < $1.name }
        try save(reg)
        return reg
    }

    @discardableResult
    public func remove(name: String) throws -> FleetRegistry {
        var reg = try load()
        reg.worlds.removeAll { $0.name == name }
        try save(reg)
        return reg
    }
}

// MARK: - Doctor & scan

public enum FleetDiagnostics {
    /// 경로·objects 존재·상대경로·config 유령을 검사.
    public static func doctor(
        registry: FleetRegistry,
        ledgerConfig: LedgerConfig = .load(),
        fileManager: FileManager = .default
    ) -> FleetDoctorReport {
        var issues: [FleetIssue] = []
        var health: [FleetWorldHealth] = []

        for w in registry.worlds {
            let abs = isAbsolutePath(w.rootPath)
            let exists = fileManager.fileExists(atPath: w.rootPath)
            let objects = (w.rootPath as NSString).appendingPathComponent("objects")
            let hasObjects = fileManager.fileExists(atPath: objects)
            var count: Int?
            // Ephemeral / missing roots: never deep-walk (ship-/tmp · deleted WT hang).
            if hasObjects, !RepositoryLaunchContext.isEphemeralPath(w.rootPath) {
                count = countMarkdownFiles(at: objects, fileManager: fileManager)
            }
            health.append(FleetWorldHealth(
                name: w.name,
                rootPath: w.rootPath,
                exists: exists,
                hasObjectsDir: hasObjects,
                absolutePath: abs,
                objectFileCount: count,
                enabled: w.enabled,
                kind: w.kind,
                defaultWeight: w.defaultWeight
            ))
            if !abs {
                issues.append(FleetIssue(
                    id: "path.relative.\(w.name)",
                    severity: .error,
                    code: "relative-path",
                    message: "world '\(w.name)' rootPath is relative: \(w.rootPath)",
                    world: w.name
                ))
            }
            if !exists {
                issues.append(FleetIssue(
                    id: "path.missing.\(w.name)",
                    severity: .error,
                    code: "missing-path",
                    message: "world '\(w.name)' path does not exist: \(w.rootPath)",
                    world: w.name
                ))
            } else if !hasObjects {
                issues.append(FleetIssue(
                    id: "path.no-objects.\(w.name)",
                    severity: .warning,
                    code: "no-objects-dir",
                    message: "world '\(w.name)' has no objects/ directory",
                    world: w.name
                ))
            }
            if w.rootPath.contains("/var/folders/") || w.rootPath.contains("/tmp/")
                || w.rootPath.contains("tmp.") {
                issues.append(FleetIssue(
                    id: "path.ephemeral.\(w.name)",
                    severity: .warning,
                    code: "ephemeral-path",
                    message: "world '\(w.name)' looks like a temp path — remove from fleet",
                    world: w.name
                ))
            }
        }

        // LedgerConfig worlds 와 교차 — 등록됐지만 fleet 에 없거나 죽은 경로.
        for lw in ledgerConfig.effectiveWorlds {
            let path = (lw.rootPath as NSString).expandingTildeInPath
            let inFleet = registry.worlds.contains {
                $0.name == lw.name || $0.rootPath == path
            }
            if !fileManager.fileExists(atPath: path) {
                issues.append(FleetIssue(
                    id: "config.ghost.\(lw.name)",
                    severity: .warning,
                    code: "config-ghost",
                    message: "LedgerConfig world '\(lw.name)' path missing: \(path)",
                    world: lw.name
                ))
            }
            if !inFleet, fileManager.fileExists(atPath: path) {
                issues.append(FleetIssue(
                    id: "config.unregistered.\(lw.name)",
                    severity: .info,
                    code: "config-unregistered",
                    message: "LedgerConfig world '\(lw.name)' not in fleet — fleet scan/register recommended",
                    world: lw.name
                ))
            }
        }

        if registry.worlds.isEmpty {
            issues.append(FleetIssue(
                id: "fleet.empty",
                severity: .info,
                code: "empty-fleet",
                message: "fleet has no worlds — run: fleet scan --apply"
            ))
        }

        health.sort { $0.name < $1.name }
        return FleetDoctorReport(issues: issues, worlds: health)
    }

    /// workspace 루트 아래 `*-mono` 및 직접 `.wiki`, 개인 gujo-wiki 후보 탐색.
    public static func scan(
        workspaceRoots: [String],
        registry: FleetRegistry,
        personalWikiPaths: [String] = defaultPersonalWikiPaths(),
        fileManager: FileManager = .default
    ) -> [FleetScanCandidate] {
        var out: [FleetScanCandidate] = []
        var seenPaths = Set<String>()

        func consider(name: String, wikiPath: String, kind: FleetWorldKind) {
            let abs = URL(fileURLWithPath: (wikiPath as NSString).expandingTildeInPath)
                .standardizedFileURL.path
            guard !seenPaths.contains(abs) else { return }
            guard fileManager.fileExists(atPath: abs) else { return }
            seenPaths.insert(abs)
            let registered = registry.worlds.contains {
                $0.rootPath == abs || $0.name == name
            }
            out.append(FleetScanCandidate(
                name: name, rootPath: abs, kind: kind, alreadyRegistered: registered))
        }

        for personal in personalWikiPaths {
            let expanded = (personal as NSString).expandingTildeInPath
            if fileManager.fileExists(atPath: expanded) {
                // personal 은 폴더 자체가 원장 루트 (objects 직하) 일 수 있음.
                let asWiki = (expanded as NSString).appendingPathComponent(".wiki")
                if fileManager.fileExists(atPath: asWiki) {
                    consider(name: "gujo-wiki", wikiPath: asWiki, kind: .personal)
                } else if fileManager.fileExists(
                    atPath: (expanded as NSString).appendingPathComponent("objects")) {
                    consider(name: "gujo-wiki", wikiPath: expanded, kind: .personal)
                }
            }
        }

        for root in workspaceRoots {
            let expanded = URL(fileURLWithPath: (root as NSString).expandingTildeInPath)
                .standardizedFileURL
            guard let children = try? fileManager.contentsOfDirectory(
                at: expanded,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for child in children {
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: child.path, isDirectory: &isDir),
                      isDir.boolValue else { continue }
                let base = child.lastPathComponent
                // *-mono 또는 내부에 main/.wiki / .wiki
                let candidates = [
                    child.appendingPathComponent(".wiki"),
                    child.appendingPathComponent("main/.wiki"),
                ]
                for wiki in candidates {
                    if fileManager.fileExists(atPath: wiki.path) {
                        consider(name: base, wikiPath: wiki.path, kind: .repo)
                    }
                }
                // bare+worktree: apps 아래 단일 체크는 과함 — mono 루트만.
            }
        }

        out.sort { $0.name < $1.name }
        return out
    }

    public static func defaultPersonalWikiPaths() -> [String] {
        [
            StateRootKit.path("gujo-wiki"),
        ]
    }

    public static func defaultWorkspaceRoots() -> [String] {
        [
            StateRootKit.path("Documents/WORK/WORKSPACE"),
        ]
    }

    private static func isAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") || (path as NSString).expandingTildeInPath.hasPrefix("/")
            && path.hasPrefix("~")
            || path.hasPrefix("/")
    }

    /// Health signal only — must stay off the slow path on main-thread init.
    /// Caps walk + skips xattr-heavy full-tree traversal (gujo-wiki · syncthing hang 2026-08-06).
    private static func countMarkdownFiles(
        at dir: String,
        fileManager: FileManager,
        limit: Int = 2_000
    ) -> Int {
        let root = URL(fileURLWithPath: dir, isDirectory: true)
        // Resource-key enumerator avoids path-string getxattr storm of enumeratorAtPath.
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return 0 }
        var n = 0
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else { continue }
            if fileURL.pathExtension.lowercased() == "md" {
                n += 1
                if n >= limit {
                    enumerator.skipDescendants()
                    break
                }
            }
        }
        return n
    }
}

extension FleetRegistry {
    /// doctor 용 enabled world 만.
    public var enabledWorlds: [FleetWorldEntry] {
        worlds.filter(\.enabled)
    }

    /// Repo picker/StateMirror projection: worktree entries sharing a normalized remote collapse
    /// to one logical owner. Old fleet rows are upgraded lazily from gitRemote when possible.
    public var canonicalRepositories: [CanonicalRepositoryRegistration] {
        var grouped: [String: CanonicalRepositoryRegistration] = [:]
        for world in worlds where world.kind == .repo {
            let normalized = world.normalizedGitRemote
                ?? world.gitRemote.flatMap { try? RepositoryIdentity.normalize(remoteURL: $0) }
            guard let normalized else { continue }
            let id = world.repoId ?? RepositoryIdentity.repoID(normalizedRemote: normalized)
            let paths = Set((world.worktreePaths ?? []) + [world.rootPath])
            if var current = grouped[id] {
                current.worktreePaths = Array(Set(current.worktreePaths).union(paths)).sorted()
                grouped[id] = current
            } else {
                grouped[id] = CanonicalRepositoryRegistration(
                    repoId: id,
                    normalizedRemote: normalized,
                    canonicalWorldName: world.name,
                    canonicalKnowledgeRoot: world.rootPath,
                    worktreePaths: Array(paths).sorted())
            }
        }
        return grouped.values.sorted { $0.repoId < $1.repoId }
    }
}

public struct CanonicalRepositoryRegistration: Codable, Sendable, Equatable, Identifiable {
    public let repoId: String
    public let normalizedRemote: String
    public let canonicalWorldName: String
    public let canonicalKnowledgeRoot: String
    public var worktreePaths: [String]

    public var id: String { repoId }
}
