import Foundation
import RepositoryIdentityKit
import CommandKit

/// A repository is a logical owner, while a checkout/worktree is only an execution instance.
/// The stable join key is derived exclusively from the normalized Git remote.
public struct RepositoryIdentity: Codable, Sendable, Equatable {
    public static let schemaVersion = "knowledge-base-wiki.repository-identity.v1"
    public static let identityAlgorithmVersion = RepositoryIdentityAlgorithm.version

    public let schemaVersion: String
    public let repoId: String
    public let remoteName: String
    public let remoteURL: String
    public let normalizedRemote: String
    public let worktreePath: String
    public let gitCommonDirectory: String
    public let currentBranch: String?
    public let defaultBranch: String?
    public let sourceCommit: String

    public init(
        remoteName: String = "origin",
        remoteURL: String,
        worktreePath: String,
        gitCommonDirectory: String,
        currentBranch: String? = nil,
        defaultBranch: String? = nil,
        sourceCommit: String
    ) throws {
        let normalized = try Self.normalize(remoteURL: remoteURL)
        self.schemaVersion = Self.schemaVersion
        self.repoId = Self.repoID(normalizedRemote: normalized)
        self.remoteName = remoteName
        self.remoteURL = remoteURL
        self.normalizedRemote = normalized
        self.worktreePath = URL(fileURLWithPath: worktreePath).standardizedFileURL.path
        self.gitCommonDirectory = URL(fileURLWithPath: gitCommonDirectory).standardizedFileURL.path
        self.currentBranch = currentBranch
        self.defaultBranch = defaultBranch
        self.sourceCommit = sourceCommit.lowercased()
    }

    public static func normalize(remoteURL raw: String) throws -> String {
        do {
            return try RepositoryIdentityAlgorithm.normalize(remoteURL: raw)
        } catch RepositoryRemoteError.missingRemote {
            throw RepositoryIdentityError.missingRemote
        } catch RepositoryRemoteError.invalidRemote(let value) {
            throw RepositoryIdentityError.invalidRemote(value)
        }
    }

    public static func repoID(normalizedRemote: String) -> String {
        RepositoryIdentityAlgorithm.repoID(normalizedRemote: normalizedRemote)
    }
}

public enum RepositoryIdentityError: Error, CustomStringConvertible, Equatable {
    case notGitRepository(String)
    case missingRemote
    case invalidRemote(String)
    case gitFailed(String)

    public var description: String {
        switch self {
        case .notGitRepository(let path): return "Git 저장소가 아님: \(path)"
        case .missingRemote: return "Git remote가 없어 canonical repoId를 만들 수 없음"
        case .invalidRemote(let value): return "Git remote 형식이 잘못됨: \(value)"
        case .gitFailed(let command): return "git 명령 실패: \(command)"
        }
    }
}

/// Result of proving a ledger object against the repository tree at one exact commit.
/// Promotion callers must require `.exact`; a working-tree file alone is never provenance.
public enum RepositoryObjectProvenance: Sendable, Equatable {
    case exact
    case worldOutsideWorktree
    case commitUnavailable
    case missingAtCommit
    case malformedAtCommit
    case mismatchedAtCommit
}

public enum GitRepositoryInspector {
    public static func inspect(cwd: String) throws -> RepositoryIdentity {
        guard let worktree = git(["rev-parse", "--show-toplevel"], cwd: cwd) else {
            throw RepositoryIdentityError.notGitRepository(cwd)
        }
        let remotes = (git(["remote"], cwd: worktree) ?? "")
            .split(separator: "\n").map(String.init).sorted()
        guard let remoteName = remotes.contains("origin") ? "origin" : remotes.first,
              let remoteURL = git(["remote", "get-url", remoteName], cwd: worktree) else {
            throw RepositoryIdentityError.missingRemote
        }
        guard let commit = git(["rev-parse", "HEAD"], cwd: worktree) else {
            throw RepositoryIdentityError.gitFailed("rev-parse HEAD")
        }
        let commonRaw = git(["rev-parse", "--git-common-dir"], cwd: worktree) ?? ".git"
        let common = commonRaw.hasPrefix("/")
            ? commonRaw
            : URL(fileURLWithPath: worktree).appendingPathComponent(commonRaw).standardizedFileURL.path
        let branch = git(["symbolic-ref", "--quiet", "--short", "HEAD"], cwd: worktree)
        let remoteHead = git(
            ["symbolic-ref", "--quiet", "--short", "refs/remotes/\(remoteName)/HEAD"],
            cwd: worktree)
        let defaultBranch = remoteHead?.hasPrefix(remoteName + "/") == true
            ? String(remoteHead!.dropFirst(remoteName.count + 1))
            : remoteHead
        return try RepositoryIdentity(
            remoteName: remoteName,
            remoteURL: remoteURL,
            worktreePath: worktree,
            gitCommonDirectory: common,
            currentBranch: branch,
            defaultBranch: defaultBranch,
            sourceCommit: commit)
    }

    /// Returns the repository identity for a `.wiki` root when it is repo-owned.
    public static func inspect(worldRoot: String) -> RepositoryIdentity? {
        let root = URL(fileURLWithPath: worldRoot).standardizedFileURL
        let candidate = root.lastPathComponent == ".wiki"
            ? root.deletingLastPathComponent().path
            : root.path
        return try? inspect(cwd: candidate)
    }

    /// Proves that the exact source object was tracked at the provenance commit. `nil` means
    /// the world cannot be related to the supplied repository checkout; `false` is a hard miss.
    public static func contains(
        object: LedgerObject,
        worldRoot: URL,
        repository: RepositoryIdentity,
        commit: String
    ) -> Bool? {
        switch provenance(
            object: object, worldRoot: worldRoot, repository: repository, commit: commit
        ) {
        case .exact: return true
        case .worldOutsideWorktree: return nil
        default: return false
        }
    }

    /// Reads the object bytes from Git, not from the working tree, and proves that they decode
    /// to the exact immutable object supplied by the caller.
    public static func provenance(
        object: LedgerObject,
        worldRoot: URL,
        repository: RepositoryIdentity,
        commit: String
    ) -> RepositoryObjectProvenance {
        // 심볼릭 링크를 **양쪽 다** 푼 뒤 비교한다. `standardizedFileURL` 은 `..`·`.` 만
        // 정리하고 링크는 그대로 두는데, worktree 경로는 git 이 `rev-parse --show-toplevel`
        // 로 이미 실경로를 돌려준다. 그래서 world 를 링크 경로로 등록해 두면 같은 디렉터리
        // 인데도 접두어 비교가 어긋나 `worldOutsideWorktree`(= 봉쇄 실패) 로 떨어진다.
        //
        // 이 Mac 의 bare+worktree 배치가 정확히 그 형태다:
        //   world root  …/swift-app-mono/main/.wiki        (main 은 심볼릭 링크)
        //   git toplevel …/swift-app-mono/.worktrees/main  (실경로)
        // 그 결과 repo world 를 거친 프로모션 영수증이 전부 위반으로 떴다 — 변조가 아니라
        // 경로 표기 차이였다. 봉쇄는 "같은 디렉터리인가"를 물어야지 "같은 문자열인가"가 아니다.
        let worktree = URL(fileURLWithPath: repository.worktreePath)
            .resolvingSymlinksInPath().standardizedFileURL.path
        let root = worldRoot.resolvingSymlinksInPath().standardizedFileURL.path
        guard root == worktree || root.hasPrefix(worktree + "/") else {
            return .worldOutsideWorktree
        }
        guard gitExitStatus(["cat-file", "-e", "\(commit)^{commit}"], cwd: worktree) == 0 else {
            return .commitUnavailable
        }
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents(
            in: TimeZone(identifier: "UTC")!, from: object.published)
        let relativeWorld = root == worktree ? "" : String(root.dropFirst(worktree.count + 1)) + "/"
        let path = relativeWorld + "objects/"
            + String(format: "%04d/%02d/", components.year ?? 0, components.month ?? 0)
            + object.id + ".md"
        guard let result = runGit(["show", "\(commit):\(path)"], cwd: worktree) else {
            return .missingAtCommit
        }
        guard result.status == 0 else { return .missingAtCommit }
        guard let text = String(data: result.data, encoding: .utf8),
              let parsed = LedgerObject.parse(text),
              parsed.storedSHA == LedgerObject.hash(parsed.object.body),
              !LedgerObject.isContentID(parsed.object.id)
                || parsed.object.contentID() == parsed.object.id else {
            return .malformedAtCommit
        }
        return parsed.object == object ? .exact : .mismatchedAtCommit
    }

    private static func git(_ arguments: [String], cwd: String) -> String? {
        guard let result = runGit(arguments, cwd: cwd), result.status == 0 else { return nil }
        let value = String(data: result.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func gitExitStatus(_ arguments: [String], cwd: String) -> Int32? {
        runGit(arguments, cwd: cwd)?.status
    }

    /// Git metadata calls are local and tiny, but a broken credential helper or filesystem can
    /// still hang. Polling keeps this synchronous Core API simple while enforcing a hard cutoff.
    private static func runGit(
        _ arguments: [String],
        cwd: String,
        timeout: TimeInterval = 10
    ) -> (status: Int32, data: Data)? {
        let result = CommandKitSync.run(
            "/usr/bin/env",
            ["git", "-C", cwd] + arguments,
            timeout: timeout
        )
        if result.exitCode == 127, result.stdout.isEmpty { return nil }
        return (result.exitCode, Data(result.stdout.utf8))
    }
}

/// Joins worktree paths to a canonical repository identity without redirecting writes to
/// another checkout. Git continues to own the tracked `.wiki/objects` set per branch.
public struct RepositoryContext: Sendable, Equatable {
    public let identity: RepositoryIdentity
    public let world: LedgerWorld

    public init(identity: RepositoryIdentity, world: LedgerWorld) {
        self.identity = identity
        self.world = world
    }

    public static func resolve(cwd: String, world: LedgerWorld) -> RepositoryContext? {
        guard let identity = try? GitRepositoryInspector.inspect(cwd: cwd) else { return nil }
        let wiki = URL(fileURLWithPath: world.rootPath).standardizedFileURL
        let repo = URL(fileURLWithPath: identity.worktreePath).standardizedFileURL
        guard wiki.path == repo.appendingPathComponent(".wiki").path
                || wiki.path.hasPrefix(repo.path + "/") else { return nil }
        return RepositoryContext(identity: identity, world: world)
    }

    /// Resolves an explicitly opened checkout to its own `.wiki` snapshot. A registered main
    /// worktree may provide the logical display name, but never replaces the execution path.
    public static func resolve(cwd: String, config: LedgerConfig) -> RepositoryContext? {
        guard let identity = try? GitRepositoryInspector.inspect(cwd: cwd) else { return nil }
        let wiki = URL(fileURLWithPath: identity.worktreePath)
            .appendingPathComponent(".wiki", isDirectory: true).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: wiki.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }

        let configured = config.effectiveWorlds
        let exact = configured.first {
            URL(fileURLWithPath: $0.rootPath).standardizedFileURL.path == wiki.path
        }
        let canonical = configured.first {
            GitRepositoryInspector.inspect(worldRoot: $0.rootPath)?.repoId == identity.repoId
        }
        let baseName = exact?.name ?? canonical?.name
            ?? URL(fileURLWithPath: identity.worktreePath).lastPathComponent
        let name: String
        if exact != nil {
            name = baseName
        } else {
            let executionLabel = identity.currentBranch
                ?? String(identity.sourceCommit.prefix(12))
            name = "\(baseName) · \(executionLabel)"
        }
        return RepositoryContext(
            identity: identity,
            world: LedgerWorld(name: name, rootPath: wiki.path))
    }
}

/// Deterministic launch-path precedence shared by GUI tests and runtime wiring.
public enum RepositoryLaunchContext {
    public static let environmentKey = "KNOWLEDGE_BASE_WIKI_REPOSITORY_PATH"

    public static func explicitPath(
        arguments: [String],
        environment: [String: String],
        bundledSourceDirectory: String?,
        currentDirectory: String
    ) -> String? {
        for flag in ["--repository-path", "--path"] {
            if let index = arguments.firstIndex(of: flag), index + 1 < arguments.count {
                return (arguments[index + 1] as NSString).expandingTildeInPath
            }
        }
        if let value = environment[environmentKey], !value.isEmpty {
            return (value as NSString).expandingTildeInPath
        }
        // SASourceDirectory is ship provenance (CLI rebuild path), NOT the user's open
        // repository. Auto-binding it pins Dock-launched GUI onto agent ship worktrees
        // (/tmp or …/.worktrees/…) and can hang on git locks during concurrent worktree ops.
        // Keep the parameter for call-site compatibility; ignore it for repository binding.
        _ = bundledSourceDirectory
        let cwdExpanded = (currentDirectory as NSString).expandingTildeInPath
        if isEphemeralPath(cwdExpanded) {
            return nil
        }
        return (try? GitRepositoryInspector.inspect(cwd: cwdExpanded)) == nil
            ? nil : cwdExpanded
    }

    /// Paths that must not auto-bind GUI repository context (ship sandboxes, temp FS).
    /// Explicit CLI `--repository-path` / env still allow these for tests.
    public static func isEphemeralPath(_ path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let markers = [
            "/tmp/",
            "/private/tmp/",
            "/var/folders/",
            "/TemporaryItems/",
            "/CoreSimulator/",
            "/.worktrees/",
        ]
        if markers.contains(where: { standardized.contains($0) }) {
            return true
        }
        // Exact /tmp roots
        if standardized == "/tmp" || standardized == "/private/tmp" {
            return true
        }
        return false
    }
}
