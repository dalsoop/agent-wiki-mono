import XCTest
import CommandKit
@testable import WorktreeKit

/// git 호출을 흉내 내는 목 러너 — (launchPath + args) 키로 응답.
struct MockGit: CommandRunning {
    var responses: [String: CommandResult] = [:]
    var defaultResult = CommandResult(stdout: "", stderr: "", exitCode: 0)
    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        responses[([launchPath] + arguments).joined(separator: " ")] ?? defaultResult
    }
}

final class PorcelainParseTests: XCTestCase {
    func testParsesWorktreesWithBranchAndDetached() {
        let text = """
        worktree /ws/repo/main
        HEAD aaaa
        branch refs/heads/main

        worktree /ws/repo/.worktrees/feat-x
        HEAD bbbb
        branch refs/heads/feat/x

        worktree /ws/repo/.worktrees/detached
        HEAD cccc
        detached

        """
        let e = WorktreeKit.parsePorcelain(text)
        XCTAssertEqual(e.count, 3)
        XCTAssertEqual(e[0].branch, "refs/heads/main")
        XCTAssertEqual(e[1].path, "/ws/repo/.worktrees/feat-x")
        XCTAssertEqual(e[1].sha, "bbbb")
        XCTAssertNil(e[2].branch)   // detached
    }
}

final class WorktreeJudgmentTests: XCTestCase {
    private func info(merged: Bool, dirty: Bool, fresh: Bool, main: Bool = false) -> WorktreeInfo {
        WorktreeInfo(repo: "r", gitDir: "/g", path: "/p", branch: "refs/heads/f", sha: "s",
                     flags: .init(isMerged: merged, isDirty: dirty, isFresh: fresh, isMainWorktree: main))
    }

    func testRemovable_onlyWhenMergedCleanNotFreshNotMain() {
        XCTAssertTrue(info(merged: true, dirty: false, fresh: false).removable)
        XCTAssertFalse(info(merged: false, dirty: false, fresh: false).removable) // 안 머지됨
        XCTAssertFalse(info(merged: true, dirty: true, fresh: false).removable)   // dirty
        XCTAssertFalse(info(merged: true, dirty: false, fresh: true).removable)   // 신선(24h)
        XCTAssertFalse(info(merged: true, dirty: false, fresh: false, main: true).removable) // main 보호
    }

    func testDirtyMerged_protectedCategory() {
        XCTAssertTrue(info(merged: true, dirty: true, fresh: false).dirtyMerged)
        XCTAssertFalse(info(merged: true, dirty: false, fresh: false).dirtyMerged)
    }
}

final class WorktreeKitActionTests: XCTestCase {
    func testResolveBase_fallsBackToMaster() async {
        var mock = MockGit()
        mock.responses["/usr/bin/git --git-dir /g rev-parse -q --verify origin/main"] =
            CommandResult(stdout: "", stderr: "", exitCode: 1)   // main 없음
        let base = await WorktreeKit(runner: mock).resolveBase(gitDir: "/g")
        XCTAssertEqual(base, "origin/master")
    }

    func testRemove_refusesNonRemovable() async {
        let w = WorktreeInfo(repo: "r", gitDir: "/g", path: "/p", branch: "refs/heads/f", sha: "s",
                             flags: .init(isMerged: false, isDirty: false, isFresh: false, isMainWorktree: false))
        let r = await WorktreeKit(runner: MockGit()).remove(w)
        XCTAssertFalse(r.ok)   // removable 아님 → 거부
    }

    func testRemove_removableDeletesWorktreeAndBranch() async {
        let w = WorktreeInfo(repo: "r", gitDir: "/g", path: "/p", branch: "refs/heads/feat/x", sha: "s",
                             flags: .init(isMerged: true, isDirty: false, isFresh: false, isMainWorktree: false))
        var mock = MockGit()
        mock.responses["/usr/bin/git --git-dir /g worktree remove /p --force"] =
            CommandResult(stdout: "", stderr: "", exitCode: 0)
        let r = await WorktreeKit(runner: mock).remove(w)
        XCTAssertTrue(r.ok, r.message)
    }

    func testWorktrees_judgesMergedCleanAsRemovable() async {
        var mock = MockGit()
        let g = "/usr/bin/git --git-dir /g"
        mock.responses["\(g) rev-parse -q --verify origin/main"] = CommandResult(stdout: "ok", stderr: "", exitCode: 0)
        mock.responses["\(g) worktree list --porcelain"] = CommandResult(
            stdout: "worktree /ws/repo/main\nHEAD m\nbranch refs/heads/main\n\nworktree /ws/x\nHEAD s1\nbranch refs/heads/feat/x\n\n",
            stderr: "", exitCode: 0)
        mock.responses["\(g) merge-base --is-ancestor s1 origin/main"] = CommandResult(stdout: "", stderr: "", exitCode: 0) // 머지됨
        mock.responses["/usr/bin/git -C /ws/x status --short"] = CommandResult(stdout: "", stderr: "", exitCode: 0)          // clean
        let ws = await WorktreeKit(runner: mock, freshWindowHours: 0).worktrees(gitDir: "/g", repo: "repo")
        let x = ws.first { $0.path == "/ws/x" }
        XCTAssertEqual(x?.isMerged, true)
        XCTAssertEqual(x?.isDirty, false)
        XCTAssertEqual(x?.removable, true)
        XCTAssertEqual(ws.first { $0.isMainWorktree }?.path, "/ws/repo/main")
    }
}
