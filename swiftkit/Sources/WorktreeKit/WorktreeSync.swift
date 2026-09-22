import Foundation
import CommandKit

/// 워크트리를 upstream 최신으로 맞추는 규칙과 실행.
///
/// ## 왜 필요한가
///
/// bare+worktree 배치에서 `<repo>/main` 은 여러 세션이 공유한다. 아무도 당기지
/// 않으면 조용히 뒤처지고, **그 상태에서 빌드·출하하면 남의(또는 옛) 코드가 결과가
/// 된다.** 2026-08-04 실측: `.worktrees/main` 이 머지된 커밋을 안 가진 채로
/// `ship-app.sh` 의 canonical source 로 쓰여, 방금 머지한 수정이 빠진 앱이
/// `/Applications` 에 설치됐다. "머지 완료"와 "설치본이 그 코드"는 다른 사실이다.
///
/// ## 규칙
///
/// - **fast-forward 만 한다.** merge commit 도, rebase 도, reset 도 만들지 않는다.
/// - **미커밋 변경을 미리 이유로 삼아 건너뛰지 않는다.** 들어오는 커밋이 수정 중인
///   파일을 건드리지 않으면 git 은 ff 를 그냥 해준다. 겹칠 때만 git 이 거부하고,
///   그때는 손대지 않고 목록에 남긴다.
/// - **stash 하지 않는다.** 다른 세션이 그 순간 쓰고 있는 파일을 낚아챌 수 있다.
/// - 갈라진(diverged) 브랜치는 사람 판단이다 — 보고만 한다.
public struct WorktreeSyncStatus: Sendable, Equatable, Codable {
    /// upstream 대비 뒤처진 커밋 수. upstream 이 없으면 nil.
    public let behind: Int?
    /// upstream 에 없는 로컬 커밋 수. upstream 이 없으면 nil.
    public let ahead: Int?
    public let hasUpstream: Bool
    public let isDetached: Bool

    public init(behind: Int?, ahead: Int?, hasUpstream: Bool, isDetached: Bool) {
        self.behind = behind
        self.ahead = ahead
        self.hasUpstream = hasUpstream
        self.isDetached = isDetached
    }
}

/// sync 가 한 워크트리에 대해 내린 판정.
public enum WorktreeSyncPlan: String, Sendable, Equatable, Codable {
    /// 이미 최신 — 할 일 없음.
    case upToDate
    /// fast-forward 가능 — `--apply` 면 당긴다.
    case fastForward
    /// 로컬 커밋이 upstream 과 갈라졌다 — 사람이 판단한다. 손대지 않는다.
    case diverged
    /// upstream 이 없다(로컬 전용 브랜치). 당길 대상이 없다.
    case noUpstream
    /// detached HEAD — 브랜치가 아니라 특정 커밋에 있다. 손대지 않는다.
    case detached

    public var needsWork: Bool { self == .fastForward }
}

/// `--apply` 로 실제 실행한 결과.
public enum WorktreeSyncOutcome: String, Sendable, Equatable, Codable {
    case alreadyCurrent
    case fastForwarded
    /// git 이 ff 를 거부했다 — 들어오는 커밋이 수정 중인 파일과 겹친다.
    /// 남의 작업일 수 있으므로 손대지 않는다.
    case blockedByLocalChanges
    case skipped
    case failed
}

public struct WorktreeSyncResult: Sendable, Equatable, Codable {
    public let repo: String
    public let path: String
    public let branch: String?
    public let status: WorktreeSyncStatus
    public let plan: WorktreeSyncPlan
    /// dry-run 이면 nil.
    public let outcome: WorktreeSyncOutcome?
    public let detail: String?

    public init(repo: String, path: String, branch: String?, status: WorktreeSyncStatus,
                plan: WorktreeSyncPlan, outcome: WorktreeSyncOutcome?, detail: String?) {
        self.repo = repo
        self.path = path
        self.branch = branch
        self.status = status
        self.plan = plan
        self.outcome = outcome
        self.detail = detail
    }
}

public enum WorktreeSyncPlanner {
    /// 상태 → 판정. 순수 함수라 git 없이 검사한다.
    ///
    /// dirty 여부는 **여기 들어오지 않는다.** ff 가능 여부는 git 이 실제 파일을 보고
    /// 정하는 것이지, "더러우니까 안 된다" 로 미리 잘라낼 일이 아니다.
    public static func plan(_ status: WorktreeSyncStatus) -> WorktreeSyncPlan {
        if status.isDetached { return .detached }
        if !status.hasUpstream { return .noUpstream }
        let behind = status.behind ?? 0
        let ahead = status.ahead ?? 0
        if behind == 0 { return .upToDate }
        if ahead > 0 { return .diverged }
        return .fastForward
    }

    /// `git rev-list --left-right --count HEAD...@{upstream}` 출력 파싱.
    /// 왼쪽이 ahead(로컬만), 오른쪽이 behind(upstream 만).
    public static func parseAheadBehind(_ raw: String) -> (ahead: Int, behind: Int)? {
        let parts = raw.split(whereSeparator: { $0 == "\t" || $0 == " " || $0 == "\n" })
        guard parts.count >= 2, let a = Int(parts[0]), let b = Int(parts[1]) else { return nil }
        return (a, b)
    }

    /// git 이 ff 를 거부한 이유가 "로컬 변경과 겹쳐서" 인지 판별한다.
    ///
    /// 이 구분이 중요한 이유: 겹쳐서 막힌 것은 **정상적인 보호**이고 다음에 다시
    /// 시도하면 되지만, 그 외 실패는 진짜 오류다. 둘을 같은 실패로 뭉치면
    /// "왜 안 됐는지" 를 매번 사람이 로그에서 다시 읽어야 한다.
    public static func isLocalChangeBlock(_ stderr: String) -> Bool {
        let markers = [
            "would be overwritten by merge",
            "local changes to the following files",
            "Please commit your changes or stash them",
            "cannot pull with rebase",
            "Your local changes"
        ]
        return markers.contains { stderr.localizedCaseInsensitiveContains($0) }
    }
}

public struct WorktreeSyncer: Sendable {
    let runner: any CommandRunning
    let gitPath: String

    public init(runner: any CommandRunning = ProcessCommandRunner(),
                gitPath: String = "/usr/bin/git") {
        self.runner = runner
        self.gitPath = gitPath
    }

    /// 한 저장소의 remote 를 한 번만 당긴다. 워크트리마다 fetch 하면 같은 일을 N 번 한다.
    @discardableResult
    public func fetch(gitDir: String) async -> Bool {
        await runner.run(gitPath, ["--git-dir", gitDir, "fetch", "--prune", "--quiet", "origin"],
                         timeout: 180).exitCode == 0
    }

    public func status(path: String) async -> WorktreeSyncStatus {
        let head = await run(path, ["symbolic-ref", "--quiet", "--short", "HEAD"])
        guard head.exitCode == 0 else {
            return WorktreeSyncStatus(behind: nil, ahead: nil, hasUpstream: false, isDetached: true)
        }
        let counts = await run(path, ["rev-list", "--left-right", "--count", "HEAD...@{upstream}"])
        guard counts.exitCode == 0,
              let (ahead, behind) = WorktreeSyncPlanner.parseAheadBehind(counts.stdout) else {
            return WorktreeSyncStatus(behind: nil, ahead: nil, hasUpstream: false, isDetached: false)
        }
        return WorktreeSyncStatus(behind: behind, ahead: ahead, hasUpstream: true, isDetached: false)
    }

    /// fast-forward 실행. ff 가 아니면 git 이 스스로 거부하므로 우리가 판단을 덧붙이지 않는다.
    public func fastForward(path: String) async -> (WorktreeSyncOutcome, String?) {
        let r = await run(path, ["merge", "--ff-only", "@{upstream}"])
        if r.exitCode == 0 {
            return (.fastForwarded, nil)
        }
        let stderr = r.stderr.isEmpty ? r.stdout : r.stderr
        if WorktreeSyncPlanner.isLocalChangeBlock(stderr) {
            return (.blockedByLocalChanges, firstLine(stderr))
        }
        return (.failed, firstLine(stderr))
    }

    private func run(_ path: String, _ args: [String]) async -> CommandResult {
        await runner.run(gitPath, ["-C", path] + args, timeout: 120)
    }

    private func firstLine(_ s: String) -> String? {
        let line = s.split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        return (line?.isEmpty ?? true) ? nil : line
    }
}
