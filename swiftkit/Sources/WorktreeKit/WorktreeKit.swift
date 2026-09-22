import Foundation
import CommandKit
import FastDiskIOKit

/// 워크스페이스 git worktree 위생의 SSOT. 지금까지 흩어져 있던 로직 —
/// `~/.codex/tools/workspace_git_cleanup.sh`(bash), AgentSSOT `GitLifecycleScanner`(스크립트
/// 위임 파싱), AWCT(자체 Swift) — 을 하나의 kit 으로 모은다. git 호출은 `CommandRunning`
/// 으로 주입해 테스트에서 목킹한다.
///
/// 판정 규칙(bash 정본 이식):
/// - base = origin/main (없으면 origin/master)
/// - 워크트리 브랜치가 base 에 merge-base --is-ancestor → 머지됨
/// - `git -C <wt> status --short` 비어있음 → clean
/// - 생성 24h 이내 신선 워크트리는 removable 판정 제외(빈 신규 오삭제 방지)
/// - removable = 머지됨 · clean · not-fresh   /   dirtyMerged = 머지됨 · dirty(보호)
public struct WorktreeInfo: Sendable, Equatable, Codable, Hashable {
    public let repo: String        // bare 상위 디렉토리 이름
    public let gitDir: String      // <repo>/.bare
    public let path: String        // 워크트리 경로
    public let branch: String?     // refs/heads/… 없으면 detached
    public let sha: String
    public let isMerged: Bool
    public let isDirty: Bool
    public let isFresh: Bool        // 생성 24h 이내
    public let isMainWorktree: Bool

    public var removable: Bool { isMerged && !isDirty && !isFresh && !isMainWorktree }
    public var dirtyMerged: Bool { isMerged && isDirty && !isMainWorktree }

    public struct Flags: Sendable, Equatable, Hashable {
        public var isMerged: Bool
        public var isDirty: Bool
        public var isFresh: Bool
        public var isMainWorktree: Bool

        public init(isMerged: Bool, isDirty: Bool, isFresh: Bool, isMainWorktree: Bool) {
            self.isMerged = isMerged
            self.isDirty = isDirty
            self.isFresh = isFresh
            self.isMainWorktree = isMainWorktree
        }
    }

    public init(repo: String, gitDir: String, path: String, branch: String?, sha: String,
                flags: Flags) {
        self.repo = repo; self.gitDir = gitDir; self.path = path; self.branch = branch
        self.sha = sha; self.isMerged = flags.isMerged; self.isDirty = flags.isDirty
        self.isFresh = flags.isFresh; self.isMainWorktree = flags.isMainWorktree
    }
}

public struct WorktreeKit: Sendable {
    let runner: any CommandRunning
    let now: @Sendable () -> Date
    let freshWindowHours: Double

    public init(runner: any CommandRunning = ProcessCommandRunner(),
                freshWindowHours: Double = 24,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.runner = runner
        self.freshWindowHours = freshWindowHours
        self.now = now
    }

    /// 대규모 모노레포를 위한 고속 워크트리 엔진 인스턴스.
    public var fastEngine: FastWorktreeEngine {
        FastWorktreeEngine(runner: runner)
    }

    /// 특정 경로가 이미 연결된 워크트리(.git 파일 존재)인지 즉시 판별 (0ms).
    public func isLinkedWorktree(at path: String) -> Bool {
        FastWorktreeEngine.isLinkedWorktree(at: path)
    }

    // MARK: 열거

    /// 한 bare repo(<repo>/.bare)의 워크트리들을 판정과 함께 반환.
    public func worktrees(gitDir: String, repo: String) async -> [WorktreeInfo] {
        let base = await resolveBase(gitDir: gitDir)
        let porcelain = await git(gitDir, ["worktree", "list", "--porcelain"]).stdout
        var out: [WorktreeInfo] = []
        // bare 저장소 자신은 작업 트리가 없다 — 목록에 넣으면 dirty/머지 판정도,
        // sync 의 fast-forward 도 무의미한 대상에 대고 돈다.
        for entry in Self.parsePorcelain(porcelain) where !entry.isBare {
            let isMain = entry.path.hasSuffix("/main") || entry.branch == "refs/heads/main"
            var merged = false
            if let _ = entry.branch, !entry.sha.isEmpty {
                merged = await isAncestor(gitDir: gitDir, sha: entry.sha, base: base)
            }
            let dirty = merged ? await isDirty(path: entry.path) : false
            let fresh = isFresh(path: entry.path)
            out.append(WorktreeInfo(
                repo: repo, gitDir: gitDir, path: entry.path, branch: entry.branch,
                sha: entry.sha,
                flags: .init(isMerged: merged, isDirty: dirty, isFresh: fresh, isMainWorktree: isMain)))
        }
        return out
    }

    /// 판정 없이 경로·브랜치만 — sync 처럼 머지·dirty 여부가 필요 없는 쪽을 위한 가벼운 열거.
    ///
    /// `worktrees(gitDir:repo:)` 는 워크트리마다 `merge-base` 와 `status` 를 돌린다.
    /// 61개 워크트리에서 그것만으로 13초가 나왔다 — 세션 시작 훅에 쓸 수 없는 비용이다.
    /// 여기서는 `worktree list` 한 번으로 끝낸다.
    public func listPaths(gitDir: String, repo: String) async -> [(path: String, branch: String?)] {
        let porcelain = await git(gitDir, ["worktree", "list", "--porcelain"]).stdout
        return Self.parsePorcelain(porcelain)
            .filter { !$0.isBare }
            .map { ($0.path, $0.branch) }
    }

    /// 워크스페이스 루트들 아래 모든 `<repo>/.bare` 를 훑어 워크트리 전수 반환.
    public func scan(workspaceRoots: [String]) async -> [WorktreeInfo] {
        var out: [WorktreeInfo] = []
        for root in workspaceRoots {
            guard let subs = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for group in subs.sorted() {                 // apps / ai-tools / infra …
                let groupPath = "\(root)/\(group)"
                guard let repos = try? FileManager.default.contentsOfDirectory(atPath: groupPath) else { continue }
                for repo in repos.sorted() {
                    let bare = "\(groupPath)/\(repo)/.bare"
                    guard FileManager.default.fileExists(atPath: bare) else { continue }
                    out += await worktrees(gitDir: bare, repo: repo)
                }
            }
        }
        return out
    }

    // MARK: 액션

    public struct ActionResult: Sendable { public let ok: Bool; public let message: String }

    /// 워크트리 제거(+선택적 브랜치 삭제). removable 이 아니면 거부(force 로 우회).
    public func remove(_ w: WorktreeInfo, deleteBranch: Bool = true, force: Bool = false) async -> ActionResult {
        guard force || w.removable else {
            return ActionResult(ok: false, message: "removable 아님(머지 안 됨/dirty/신선/main): \(w.path)")
        }
        let rm = await git(w.gitDir, ["worktree", "remove", w.path, "--force"])
        guard rm.exitCode == 0 else {
            return ActionResult(ok: false, message: "worktree remove 실패: \(rm.stderr)")
        }
        if deleteBranch, let br = w.branch?.replacingOccurrences(of: "refs/heads/", with: "") {
            _ = await git(w.gitDir, ["branch", "-D", br])
        }
        return ActionResult(ok: true, message: "제거됨: \(w.path)" + (deleteBranch ? " (+브랜치)" : ""))
    }

    /// 끊긴 워크트리 등록 정리.
    public func prune(gitDir: String) async -> ActionResult {
        let r = await git(gitDir, ["worktree", "prune"])
        return ActionResult(ok: r.exitCode == 0, message: r.exitCode == 0 ? "prune 완료" : r.stderr)
    }

    /// 경로의 디스크 점유(바이트). FastDirectorySizeCalculator 위임.
    public func diskBytes(path: String) async -> Int64 {
        Int64(FastDirectorySizeCalculator.calculateSize(at: path, apparentSize: false))
    }

    // MARK: 내부 git 헬퍼

    func git(_ gitDir: String, _ args: [String]) async -> CommandResult {
        await runner.run("/usr/bin/git", ["--git-dir", gitDir] + args, timeout: 20)
    }

    func resolveBase(gitDir: String) async -> String {
        let r = await git(gitDir, ["rev-parse", "-q", "--verify", "origin/main"])
        return r.exitCode == 0 ? "origin/main" : "origin/master"
    }

    func isAncestor(gitDir: String, sha: String, base: String) async -> Bool {
        await git(gitDir, ["merge-base", "--is-ancestor", sha, base]).exitCode == 0
    }

    func isDirty(path: String) async -> Bool {
        let r = await runner.run("/usr/bin/git", ["-C", path, "status", "--short"], timeout: 20)
        return !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isFresh(path: String) -> Bool {
        // 워크트리 dir(또는 그 .git)의 생성/수정 시각 기준.
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: path)
            let created = (attrs[.creationDate] as? Date) ?? (attrs[.modificationDate] as? Date)
            guard let created else { return false }
            return now().timeIntervalSince(created) < freshWindowHours * 3600
        } catch {
            return false
        }
    }

    // MARK: porcelain 파서

    struct PorcelainEntry: Equatable {
        let path: String; let sha: String; let branch: String?
        /// bare 저장소 자신. 작업 트리가 없으므로 체크아웃·머지 대상이 아니다.
        var isBare: Bool = false
    }

    static func parsePorcelain(_ text: String) -> [PorcelainEntry] {
        var out: [PorcelainEntry] = []
        var path: String?; var sha = ""; var branch: String?; var bare = false
        func flush() {
            guard let p = path else { return }
            out.append(PorcelainEntry(path: p, sha: sha, branch: branch, isBare: bare))
            path = nil; sha = ""; branch = nil; bare = false
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let l = String(line)
            switch l {
            case "":
                flush()
            case "bare":
                bare = true
            case _ where l.hasPrefix("worktree "):
                flush()
                path = String(l.dropFirst(9))
            case _ where l.hasPrefix("HEAD "):
                sha = String(l.dropFirst(5))
            case _ where l.hasPrefix("branch "):
                branch = String(l.dropFirst(7))
            default:
                break
            }
        }
        flush()
        return out
    }
}
