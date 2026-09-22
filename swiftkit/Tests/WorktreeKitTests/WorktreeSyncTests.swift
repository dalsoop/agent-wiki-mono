import XCTest
import CommandKit
@testable import WorktreeKit

final class WorktreeSyncPlannerTests: XCTestCase {
    private func status(behind: Int?, ahead: Int?,
                        upstream: Bool = true, detached: Bool = false) -> WorktreeSyncStatus {
        WorktreeSyncStatus(behind: behind, ahead: ahead, hasUpstream: upstream, isDetached: detached)
    }

    // MARK: 판정

    func testUpToDateWhenNotBehind() {
        XCTAssertEqual(WorktreeSyncPlanner.plan(status(behind: 0, ahead: 0)), .upToDate)
    }

    /// 로컬 커밋이 있어도 뒤처지지 않았으면 할 일이 없다 — 브랜치 작업 중인 정상 상태.
    func testAheadOnlyIsUpToDate() {
        XCTAssertEqual(WorktreeSyncPlanner.plan(status(behind: 0, ahead: 4)), .upToDate)
    }

    func testBehindOnlyFastForwards() {
        XCTAssertEqual(WorktreeSyncPlanner.plan(status(behind: 7, ahead: 0)), .fastForward)
    }

    /// 양쪽에 커밋이 있으면 ff 가 불가능하다. 자동으로 merge/rebase 하지 않는다.
    func testBothSidesIsDivergedNotFastForward() {
        XCTAssertEqual(WorktreeSyncPlanner.plan(status(behind: 3, ahead: 2)), .diverged)
    }

    func testNoUpstreamIsItsOwnClassNotAnError() {
        XCTAssertEqual(
            WorktreeSyncPlanner.plan(status(behind: nil, ahead: nil, upstream: false)),
            .noUpstream
        )
    }

    func testDetachedWins() {
        XCTAssertEqual(
            WorktreeSyncPlanner.plan(status(behind: 5, ahead: 0, upstream: true, detached: true)),
            .detached
        )
    }

    /// fastForward 만 실제 작업이다 — 나머지는 보고만 한다.
    func testOnlyFastForwardNeedsWork() {
        XCTAssertTrue(WorktreeSyncPlan.fastForward.needsWork)
        for plan: WorktreeSyncPlan in [.upToDate, .diverged, .noUpstream, .detached] {
            XCTAssertFalse(plan.needsWork, "\(plan) 는 자동으로 건드리면 안 된다")
        }
    }

    // MARK: ahead/behind 파싱

    func testParsesLeftRightCount() {
        let parsed = WorktreeSyncPlanner.parseAheadBehind("2\t7\n")
        XCTAssertEqual(parsed?.ahead, 2)
        XCTAssertEqual(parsed?.behind, 7)
    }

    func testParseRejectsGarbageRatherThanGuessingZero() {
        XCTAssertNil(WorktreeSyncPlanner.parseAheadBehind(""))
        XCTAssertNil(WorktreeSyncPlanner.parseAheadBehind("fatal: no upstream"))
        XCTAssertNil(WorktreeSyncPlanner.parseAheadBehind("3"))
    }

    // MARK: 실패 사유 구분

    /// 겹쳐서 막힌 것은 정상적인 보호다. 진짜 오류와 뭉치면 매번 로그를 다시 읽어야 한다.
    func testRecognisesLocalChangeBlock() {
        XCTAssertTrue(WorktreeSyncPlanner.isLocalChangeBlock(
            "error: Your local changes to the following files would be overwritten by merge:\n\tREADME.md"
        ))
        XCTAssertTrue(WorktreeSyncPlanner.isLocalChangeBlock(
            "Please commit your changes or stash them before you merge."
        ))
    }

    func testOtherFailuresAreNotLocalChangeBlocks() {
        XCTAssertFalse(WorktreeSyncPlanner.isLocalChangeBlock("fatal: Not possible to fast-forward, aborting."))
        XCTAssertFalse(WorktreeSyncPlanner.isLocalChangeBlock("fatal: could not read Username"))
        XCTAssertFalse(WorktreeSyncPlanner.isLocalChangeBlock(""))
    }
}

/// git 호출을 기록하는 러너 — "무엇을 불렀나" 를 검사하기 위한 것.
private actor CallLog {
    private(set) var calls: [String] = []
    func add(_ c: String) { calls.append(c) }
}

private struct RecordingGit: CommandRunning {
    let log: CallLog
    var responses: [String: CommandResult] = [:]
    var defaultResult = CommandResult(stdout: "", stderr: "", exitCode: 0)

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        let key = arguments.joined(separator: " ")
        await log.add(key)
        for (pattern, result) in responses where key.contains(pattern) { return result }
        return defaultResult
    }
}

final class WorktreeSyncerTests: XCTestCase {
    /// dry-run 이 merge 를 부르면 "보기만 한다" 는 약속이 깨진다.
    func testStatusNeverMerges() async {
        let log = CallLog()
        let git = RecordingGit(log: log, responses: [
            "symbolic-ref": CommandResult(stdout: "main\n", stderr: "", exitCode: 0),
            "rev-list": CommandResult(stdout: "0\t5\n", stderr: "", exitCode: 0)
        ])
        let status = await WorktreeSyncer(runner: git).status(path: "/ws/repo/main")

        XCTAssertEqual(status.behind, 5)
        XCTAssertEqual(status.ahead, 0)
        XCTAssertTrue(status.hasUpstream)
        let calls = await log.calls
        XCTAssertFalse(calls.contains { $0.contains("merge") }, "status 는 절대 merge 하지 않는다: \(calls)")
    }

    func testDetachedHeadIsDetectedFromSymbolicRefFailure() async {
        let git = RecordingGit(log: CallLog(), responses: [
            "symbolic-ref": CommandResult(stdout: "", stderr: "", exitCode: 1)
        ])
        let status = await WorktreeSyncer(runner: git).status(path: "/ws/repo/x")
        XCTAssertTrue(status.isDetached)
        XCTAssertEqual(WorktreeSyncPlanner.plan(status), .detached)
    }

    /// upstream 이 없으면 rev-list 가 실패한다 — 0 뒤처짐으로 읽으면 "최신"으로 거짓말한다.
    func testMissingUpstreamIsNotReportedAsUpToDate() async {
        let git = RecordingGit(log: CallLog(), responses: [
            "symbolic-ref": CommandResult(stdout: "feat/x\n", stderr: "", exitCode: 0),
            "rev-list": CommandResult(stdout: "", stderr: "fatal: no upstream", exitCode: 128)
        ])
        let status = await WorktreeSyncer(runner: git).status(path: "/ws/repo/x")
        XCTAssertFalse(status.hasUpstream)
        XCTAssertEqual(WorktreeSyncPlanner.plan(status), .noUpstream)
    }

    /// ff 는 `--ff-only` 로만 — 이 플래그가 빠지면 merge commit 이 생긴다.
    func testFastForwardUsesFfOnly() async {
        let log = CallLog()
        let git = RecordingGit(log: log)
        let (outcome, _) = await WorktreeSyncer(runner: git).fastForward(path: "/ws/repo/main")

        XCTAssertEqual(outcome, .fastForwarded)
        let calls = await log.calls
        XCTAssertTrue(calls.contains { $0.contains("merge --ff-only @{upstream}") }, "\(calls)")
        XCTAssertFalse(calls.contains { $0.contains("stash") }, "stash 는 남의 작업을 낚아챈다: \(calls)")
        XCTAssertFalse(calls.contains { $0.contains("reset") }, "reset 금지: \(calls)")
        XCTAssertFalse(calls.contains { $0.contains("rebase") }, "rebase 금지: \(calls)")
    }

    func testLocalChangeBlockIsDistinctFromFailure() async {
        let blocked = RecordingGit(log: CallLog(), responses: [
            "merge": CommandResult(
                stdout: "",
                stderr: "error: Your local changes to the following files would be overwritten by merge:\n\tREADME.md",
                exitCode: 1)
        ])
        let (outcome, detail) = await WorktreeSyncer(runner: blocked).fastForward(path: "/ws/x")
        XCTAssertEqual(outcome, .blockedByLocalChanges)
        XCTAssertNotNil(detail)

        let broken = RecordingGit(log: CallLog(), responses: [
            "merge": CommandResult(stdout: "", stderr: "fatal: could not read Username", exitCode: 128)
        ])
        let (outcome2, _) = await WorktreeSyncer(runner: broken).fastForward(path: "/ws/x")
        XCTAssertEqual(outcome2, .failed)
    }
}

final class BareEntryExclusionTests: XCTestCase {
    /// bare 저장소 자신은 작업 트리가 없다 — 여기에 대고 ff 하면 무의미한 실패가 쌓인다.
    /// 실측(2026-08-04): sync 목록에 `<repo>/.bare` 가 "뒤처짐" 으로 5건 올라왔다.
    func testBareRepositoryIsFlaggedAndExcludable() {
        let text = """
        worktree /ws/repo/.bare
        bare

        worktree /ws/repo/main
        HEAD aaaa
        branch refs/heads/main

        """
        let entries = WorktreeKit.parsePorcelain(text)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].isBare)
        XCTAssertFalse(entries[1].isBare)
        XCTAssertEqual(entries.filter { !$0.isBare }.map(\.path), ["/ws/repo/main"])
    }
}
