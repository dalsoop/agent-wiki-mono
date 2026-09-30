import Foundation
import CommandKit

/// 저장소 world 경로 해석 및 main 슬롯 쓰기 방어 규칙.
///
/// 1. 저장소 world 경로 해석:
///    등록 경로가 bare+worktree 저장소의 worktree 안(`<repo>/.worktrees/<slot>/.wiki`)이면,
///    명령을 실행한 cwd가 같은 저장소의 다른 worktree 안일 때는 그 worktree의 `.wiki`로 푼다
///    (`git rev-parse --show-toplevel` + `--git-common-dir`로 같은 저장소인지 판정).
///    cwd가 저장소 밖이면 등록 경로(main 슬롯)를 읽기 전용으로만 쓴다.
/// 2. main 슬롯(`git worktree list`에서 main 브랜치를 쥔 worktree)의 `.wiki`에 쓰기가 일어나려 하면 거절한다
///    — 사유: "저장소 위키는 전용 worktree 에서 쓰고 커밋·MR 로 들인다", exit 1.
///    읽기(show/search/context/verify)는 그대로 허용.
public enum RepositoryWorldResolution {
    public static let mainBranchRef = "refs/heads/main"
    public static let writeRefusalReason = "저장소 위키는 전용 worktree 에서 쓰고 커밋·MR 로 들인다"

    /// 주어진 rootPath가 git worktree 내의 .wiki(저장소 world)인지 판정.
    public static func isRepositoryWorld(rootPath: String) -> Bool {
        let expanded = (rootPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardizedFileURL
        guard url.lastPathComponent == ".wiki" || url.path.contains("/.wiki/") else {
            return false
        }
        return gitWorktreeInfo(path: rootPath) != nil
    }

    /// 주어진 경로에서 git toplevel(worktree root)과 git common dir(공유 bare/메타데이터 저장소) 경로를 구한다.
    public static func gitWorktreeInfo(path: String) -> (worktree: String, commonDir: String)? {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).resolvingSymlinksInPath().standardizedFileURL
        let repoDir = url.lastPathComponent == ".wiki" ? url.deletingLastPathComponent().path : url.path

        guard let toplevelRes = runGit(["rev-parse", "--show-toplevel"], cwd: repoDir),
              toplevelRes.status == 0,
              let toplevelStr = String(data: toplevelRes.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !toplevelStr.isEmpty else {
            return nil
        }

        let worktreeURL = URL(fileURLWithPath: toplevelStr).resolvingSymlinksInPath().standardizedFileURL

        guard let commonRes = runGit(["rev-parse", "--git-common-dir"], cwd: worktreeURL.path),
              commonRes.status == 0,
              let commonRaw = String(data: commonRes.data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !commonRaw.isEmpty else {
            return nil
        }

        let commonURL = commonRaw.hasPrefix("/")
            ? URL(fileURLWithPath: commonRaw).resolvingSymlinksInPath().standardizedFileURL
            : worktreeURL.appendingPathComponent(commonRaw).resolvingSymlinksInPath().standardizedFileURL

        return (worktreeURL.path, commonURL.path)
    }

    /// git worktree list --porcelain 을 통해 main 브랜치(refs/heads/main)를 쥔 worktree 경로를 구한다.
    public static func mainSlotWorktree(fromCommonDir commonDir: String) -> String? {
        guard let result = runGit(["worktree", "list", "--porcelain"], cwd: commonDir),
              result.status == 0,
              let text = String(data: result.data, encoding: .utf8) else {
            return nil
        }

        var currentWorktree: String?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            switch trimmed {
            case let l where l.hasPrefix("worktree "):
                currentWorktree = String(l.dropFirst("worktree ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            case let l where l.hasPrefix("branch "):
                let branch = String(l.dropFirst("branch ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
                if branch == mainBranchRef, let wt = currentWorktree {
                    return URL(fileURLWithPath: wt).resolvingSymlinksInPath().standardizedFileURL.path
                }
            case "":
                currentWorktree = nil
            default:
                break
            }
        }
        return nil
    }

    /// 주어진 경로의 worktree가 main 슬롯인지 판정.
    public static func isMainSlot(path: String) -> Bool {
        guard let info = gitWorktreeInfo(path: path) else { return false }
        guard let mainSlot = mainSlotWorktree(fromCommonDir: info.commonDir) else { return false }
        return info.worktree == mainSlot
    }

    /// 저장소 world 경로를 cwd에 맞춰 해석한다.
    ///
    /// - 등록 경로가 bare+worktree 저장소의 worktree 안이면, cwd가 같은 저장소의 다른 worktree 안일 때는
    ///   그 worktree의 `.wiki`로 푼다.
    /// - cwd가 저장소 밖이면 등록 경로(main 슬롯)를 그대로 둔다.
    public static func resolve(world: LedgerWorld, cwd: String) -> LedgerWorld {
        guard isRepositoryWorld(rootPath: world.rootPath),
              let worldInfo = gitWorktreeInfo(path: world.rootPath),
              let cwdInfo = gitWorktreeInfo(path: cwd),
              worldInfo.commonDir == cwdInfo.commonDir else {
            return world
        }

        let resolvedWiki = URL(fileURLWithPath: cwdInfo.worktree)
            .appendingPathComponent(".wiki", isDirectory: true).standardizedFileURL.path
        return LedgerWorld(name: world.name, rootPath: resolvedWiki, display: world.display)
    }

    /// 여러 world 목록을 주어진 cwd 기준으로 해석한다.
    public static func resolve(worlds: [LedgerWorld], cwd: String) -> [LedgerWorld] {
        worlds.map { resolve(world: $0, cwd: cwd) }
    }

    /// 쓰기 권한을 검사한다.
    ///
    /// 저장소 world인 경우:
    /// - cwd가 저장소 밖이면 거절
    /// - cwd가 main 슬롯이면 거절
    /// - 대상 world root가 main 슬롯이면 거절
    /// 거절 시 사유 메시지 반환, 쓰기 허용 시 nil 반환.
    public static func checkWriteDenial(rootPath: String, cwd: String) -> String? {
        guard isRepositoryWorld(rootPath: rootPath),
              let worldInfo = gitWorktreeInfo(path: rootPath) else {
            return nil
        }

        guard let mainSlot = mainSlotWorktree(fromCommonDir: worldInfo.commonDir) else {
            return nil
        }

        guard let cwdInfo = gitWorktreeInfo(path: cwd),
              cwdInfo.commonDir == worldInfo.commonDir else {
            // cwd가 저장소 밖임
            return writeRefusalReason
        }

        if cwdInfo.worktree == mainSlot {
            // cwd가 main 슬롯임
            return writeRefusalReason
        }

        if worldInfo.worktree == mainSlot {
            // 쓰기 대상 자체가 main 슬롯임
            return writeRefusalReason
        }

        return nil
    }

    public static func checkWriteDenial(world: LedgerWorld, cwd: String) -> String? {
        checkWriteDenial(rootPath: world.rootPath, cwd: cwd)
    }

    public static func validateWrite(world: LedgerWorld, cwd: String) throws {
        if let denial = checkWriteDenial(world: world, cwd: cwd) {
            throw RepositoryWorldWriteError.refused(denial)
        }
    }

    public static func validateWrite(rootPath: String, cwd: String) throws {
        if let denial = checkWriteDenial(rootPath: rootPath, cwd: cwd) {
            throw RepositoryWorldWriteError.refused(denial)
        }
    }

    private static let gitTimeoutSeconds: TimeInterval = 10

    private static func runGit(
        _ arguments: [String],
        cwd: String
    ) -> (status: Int32, data: Data)? {
        let result = CommandKitSync.run(
            "/usr/bin/env",
            ["git", "-C", cwd] + arguments,
            timeout: gitTimeoutSeconds
        )
        if result.exitCode == 127, result.stdout.isEmpty { return nil }
        return (result.exitCode, Data(result.stdout.utf8))
    }
}

public enum RepositoryWorldWriteError: Error, LocalizedError, Equatable {
    case refused(String)

    public var errorDescription: String? {
        switch self {
        case .refused(let reason): return reason
        }
    }
}
