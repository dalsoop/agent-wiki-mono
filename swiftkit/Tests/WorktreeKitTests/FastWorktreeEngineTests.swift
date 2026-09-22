import XCTest
import CommandKit
import os
@testable import WorktreeKit

private actor CallRecorder {
    private(set) var calls: [String] = []
    func record(_ call: String) {
        calls.append(call)
    }
}

private struct TestMockGitRunner: CommandRunning {
    let recorder: CallRecorder
    var handler: @Sendable (String, [String]) -> CommandResult

    init(
        recorder: CallRecorder = CallRecorder(),
        handler: @escaping @Sendable (String, [String]) -> CommandResult = { _, _ in CommandResult(stdout: "", stderr: "", exitCode: 0) }
    ) {
        self.recorder = recorder
        self.handler = handler
    }

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        let fullCmd = ([launchPath] + arguments).joined(separator: " ")
        await recorder.record(fullCmd)
        return handler(launchPath, arguments)
    }
}

final class FastWorktreeEngineTests: XCTestCase {
    private var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create tempDir: \(error)")
        }
    }

    override func tearDown() {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    // MARK: - 1. isLinkedWorktree & 0ms 재사용 테스트

    func testIsLinkedWorktree_detectsLinkedWorktreeFile() throws {
        let wtPath = tempDir.appendingPathComponent("wt-feature")
        try FileManager.default.createDirectory(at: wtPath, withIntermediateDirectories: true)

        let dotGit = wtPath.appendingPathComponent(".git")
        let gitDirContent = "gitdir: /var/repo/.bare/worktrees/wt-feature\n"
        try gitDirContent.write(to: dotGit, atomically: true, encoding: .utf8)

        XCTAssertTrue(FastWorktreeEngine.isLinkedWorktree(at: wtPath.path))
        XCTAssertTrue(FastWorktreeEngine.isLinkedWorktree(at: wtPath))
        XCTAssertTrue(FastWorktreeEngine.isLinkedWorktree(at: dotGit.path))
    }

    func testIsLinkedWorktree_rejectsPrimaryRepoDirectory() throws {
        let repoPath = tempDir.appendingPathComponent("primary-repo")
        let dotGitDir = repoPath.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: dotGitDir, withIntermediateDirectories: true)

        // .git이 디렉터리인 경우 primary repo이므로 false
        XCTAssertFalse(FastWorktreeEngine.isLinkedWorktree(at: repoPath.path))
    }

    func testIsLinkedWorktree_rejectsNonGitDirectory() throws {
        let emptyDir = tempDir.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)

        XCTAssertFalse(FastWorktreeEngine.isLinkedWorktree(at: emptyDir.path))
        XCTAssertFalse(FastWorktreeEngine.isLinkedWorktree(at: tempDir.appendingPathComponent("non-existent").path))
    }

    func testInspectLinkedWorktree_parsesGitDirAndBranch() throws {
        let wtPath = tempDir.appendingPathComponent("wt-feature")
        let mockBareWorktree = tempDir.appendingPathComponent("bare-worktree")
        try FileManager.default.createDirectory(at: wtPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mockBareWorktree, withIntermediateDirectories: true)

        let dotGit = wtPath.appendingPathComponent(".git")
        try "gitdir: \(mockBareWorktree.path)\n".write(to: dotGit, atomically: true, encoding: .utf8)

        let headFile = mockBareWorktree.appendingPathComponent("HEAD")
        try "ref: refs/heads/feature/fast-engine\n".write(to: headFile, atomically: true, encoding: .utf8)

        let info = FastWorktreeEngine.inspectLinkedWorktree(at: wtPath.path)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.path, wtPath.path)
        XCTAssertEqual(info?.gitDir, mockBareWorktree.path)
        XCTAssertEqual(info?.branch, "feature/fast-engine")
        XCTAssertNil(info?.headCommit)
    }

    func testInspectLinkedWorktree_parsesDetachedCommit() throws {
        let wtPath = tempDir.appendingPathComponent("wt-detached")
        let mockBareWorktree = tempDir.appendingPathComponent("bare-detached")
        try FileManager.default.createDirectory(at: wtPath, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mockBareWorktree, withIntermediateDirectories: true)

        let dotGit = wtPath.appendingPathComponent(".git")
        try "gitdir: \(mockBareWorktree.path)\n".write(to: dotGit, atomically: true, encoding: .utf8)

        let headFile = mockBareWorktree.appendingPathComponent("HEAD")
        let commitSha = "a1b2c3d4e5f60718293041526374859607182930"
        try "\(commitSha)\n".write(to: headFile, atomically: true, encoding: .utf8)

        let info = FastWorktreeEngine.inspectLinkedWorktree(at: wtPath.path)
        XCTAssertNotNil(info)
        XCTAssertNil(info?.branch)
        XCTAssertEqual(info?.headCommit, commitSha)
    }

    func testPrepareWorktree_reusedExistingReturns0msWithoutCallingGit() async throws {
        let wtPath = tempDir.appendingPathComponent("wt-existing")
        try FileManager.default.createDirectory(at: wtPath, withIntermediateDirectories: true)
        let dotGit = wtPath.appendingPathComponent(".git")
        try "gitdir: /fake/bare/wt-existing\n".write(to: dotGit, atomically: true, encoding: .utf8)

        let recorder = CallRecorder()
        let runner = TestMockGitRunner(recorder: recorder) { _, _ in
            XCTFail("0ms 재사용 시 Git 명령이 호출되면 안 됩니다.")
            return CommandResult(stdout: "", stderr: "", exitCode: 1)
        }

        let engine = FastWorktreeEngine(runner: runner)
        let req = FastWorktreeRequest(
            repoPath: tempDir.path,
            targetPath: wtPath.path,
            branch: "feature/existing",
            reuseIfLinked: true
        )

        let result = try await engine.prepareWorktree(req)

        XCTAssertTrue(result.reusedExisting)
        XCTAssertEqual(result.durationMs, 0.0)
        XCTAssertEqual(result.path, wtPath.path)

        let calls = await recorder.calls
        XCTAssertTrue(calls.isEmpty, "Git 명령 호출이 전혀 없어야 함")
    }

    // MARK: - 2. 분기 전략 모델링 테스트

    func testPrepareWorktree_executesStandardStrategy() async throws {
        let wtPath = tempDir.appendingPathComponent("wt-new-standard")
        let recorder = CallRecorder()
        let runner = TestMockGitRunner(recorder: recorder) { _, _ in
            CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = FastWorktreeEngine(runner: runner)
        let req = FastWorktreeRequest(
            repoPath: tempDir.path,
            targetPath: wtPath.path,
            branch: "feat/standard",
            baseRef: "origin/main",
            strategy: .standard,
            reuseIfLinked: true
        )

        let result = try await engine.prepareWorktree(req)

        XCTAssertFalse(result.reusedExisting)
        XCTAssertEqual(result.strategyUsed, .standard)

        let calls = await recorder.calls
        XCTAssertTrue(calls.contains {
            $0.contains("worktree add --no-track -b feat/standard \(wtPath.path) origin/main")
        }, "표준 worktree add 명령이 올바르게 실행되어야 함: \(calls)")
    }

    func testPrepareWorktree_executesNoCheckoutStrategy() async throws {
        let wtPath = tempDir.appendingPathComponent("wt-no-checkout")
        let recorder = CallRecorder()
        let runner = TestMockGitRunner(recorder: recorder) { _, _ in
            CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = FastWorktreeEngine(runner: runner)
        let req = FastWorktreeRequest(
            repoPath: tempDir.path,
            targetPath: wtPath.path,
            branch: "feat/fast",
            baseRef: "origin/main",
            strategy: .noCheckout,
            reuseIfLinked: true
        )

        let result = try await engine.prepareWorktree(req)

        XCTAssertFalse(result.reusedExisting)
        XCTAssertEqual(result.strategyUsed, .noCheckout)

        let calls = await recorder.calls
        XCTAssertTrue(calls.contains {
            $0.contains("worktree add --no-checkout --no-track -b feat/fast \(wtPath.path) origin/main")
        }, "--no-checkout 플래그가 포함되어야 함: \(calls)")
    }

    func testPrepareWorktree_executesSparseCheckoutStrategy() async throws {
        let wtPath = tempDir.appendingPathComponent("wt-sparse")
        let recorder = CallRecorder()
        let runner = TestMockGitRunner(recorder: recorder) { _, _ in
            CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = FastWorktreeEngine(runner: runner)
        let req = FastWorktreeRequest(
            repoPath: tempDir.path,
            targetPath: wtPath.path,
            branch: "feat/sparse",
            baseRef: "origin/main",
            strategy: .sparseCheckout(paths: ["swiftkit", "apps/terminal"], cone: true),
            reuseIfLinked: true
        )

        let result = try await engine.prepareWorktree(req)

        XCTAssertFalse(result.reusedExisting)
        XCTAssertEqual(result.strategyUsed, .sparseCheckout(paths: ["swiftkit", "apps/terminal"], cone: true))

        let calls = await recorder.calls
        XCTAssertTrue(calls.contains { $0.contains("worktree add --no-checkout") }, "1단계: no-checkout 생성")
        XCTAssertTrue(calls.contains { $0.contains("sparse-checkout set --cone swiftkit apps/terminal") }, "2단계: sparse-checkout set")
        XCTAssertTrue(calls.contains { $0.contains("-C \(wtPath.path) checkout") }, "3단계: checkout")
    }

    func testPrepareWorktree_executesAPFSCoWStrategy() async throws {
        let warmWorktree = tempDir.appendingPathComponent("warm-wt")
        try FileManager.default.createDirectory(at: warmWorktree, withIntermediateDirectories: true)
        try "file content".write(to: warmWorktree.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)

        // warm wt 내에 .git 파일이 있어도 대상에는 복제되지 않아야 함
        try "gitdir: /fake".write(to: warmWorktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)

        let targetWt = tempDir.appendingPathComponent("cow-wt")
        let recorder = CallRecorder()
        let runner = TestMockGitRunner(recorder: recorder) { _, _ in
            CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = FastWorktreeEngine(runner: runner)
        let req = FastWorktreeRequest(
            repoPath: tempDir.path,
            targetPath: targetWt.path,
            branch: "feat/cow",
            baseRef: "origin/main",
            strategy: .apfsCoW(sourceWorktreePath: warmWorktree.path),
            reuseIfLinked: true
        )

        let result = try await engine.prepareWorktree(req)

        XCTAssertFalse(result.reusedExisting)
        XCTAssertEqual(result.strategyUsed, .apfsCoW(sourceWorktreePath: warmWorktree.path))

        // Package.swift 파일이 대상 워크트리로 복제되었는지 확인
        let clonedPackage = targetWt.appendingPathComponent("Package.swift")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clonedPackage.path))
        XCTAssertEqual(try String(contentsOf: clonedPackage, encoding: .utf8), "file content")

        let calls = await recorder.calls
        XCTAssertTrue(calls.contains { $0.contains("worktree add --no-checkout") })
        XCTAssertTrue(calls.contains { $0.contains("-C \(targetWt.path) reset --quiet") })
    }

    // MARK: - 3. Git index.lock 경합 및 자동 재시도 테스트

    final class AttemptCounter: Sendable {
        private let countState = OSAllocatedUnfairLock(initialState: 0)
        var count: Int { countState.withLock { $0 } }
        func incrementAndGet() -> Int {
            countState.withLock {
                $0 += 1
                return $0
            }
        }
    }

    func testLockContentionRetry_retriesAndSucceeds() async throws {
        let wtPath = tempDir.appendingPathComponent("wt-retry-success")
        let attemptCounter = AttemptCounter()

        let runner = TestMockGitRunner { _, args in
            if args.contains("worktree") && args.contains("add") {
                let current = attemptCounter.incrementAndGet()
                if current == 1 {
                    // 첫 번째 시도: index.lock 충돌 에러 발생
                    return CommandResult(
                        stdout: "",
                        stderr: "fatal: Unable to create '/repo/.git/index.lock': File exists.",
                        exitCode: 128
                    )
                }
                // 두 번째 시도: 성공
                return CommandResult(stdout: "Preparing worktree", stderr: "", exitCode: 0)
            }
            return CommandResult(stdout: "", stderr: "", exitCode: 0)
        }

        let engine = FastWorktreeEngine(runner: runner)
        let req = FastWorktreeRequest(
            repoPath: tempDir.path,
            targetPath: wtPath.path,
            branch: "feat/retry",
            strategy: .noCheckout,
            maxRetries: 3,
            retryBaseDelay: 0.01
        )

        let result = try await engine.prepareWorktree(req)

        XCTAssertFalse(result.reusedExisting)
        XCTAssertEqual(attemptCounter.count, 2, "index.lock 경합 후 재시도하여 2번째에 성공해야 함")
    }

    func testLockContentionExhausted_throwsExhaustedRetries() async {
        let wtPath = tempDir.appendingPathComponent("wt-retry-fail")

        let runner = TestMockGitRunner { _, _ in
            CommandResult(
                stdout: "",
                stderr: "fatal: Another git process seems to be running in this repository (index.lock)",
                exitCode: 128
            )
        }

        let engine = FastWorktreeEngine(runner: runner)
        let req = FastWorktreeRequest(
            repoPath: tempDir.path,
            targetPath: wtPath.path,
            branch: "feat/fail",
            strategy: .standard,
            maxRetries: 2,
            retryBaseDelay: 0.01
        )

        do {
            _ = try await engine.prepareWorktree(req)
            XCTFail("재시도 소진 시 에러를 던져야 함")
        } catch FastWorktreeError.exhaustedRetries(let attempts, let lastError) {
            XCTAssertEqual(attempts, 2)
            XCTAssertTrue(lastError.contains("index.lock"))
        } catch {
            XCTFail("예상치 못한 에러: \(error)")
        }
    }

    func testWorktreeKitConvenienceAccessors() throws {
        let kit = WorktreeKit()
        XCTAssertNotNil(kit.fastEngine)

        let wtPath = tempDir.appendingPathComponent("wt-kit-check")
        try FileManager.default.createDirectory(at: wtPath, withIntermediateDirectories: true)
        let dotGit = wtPath.appendingPathComponent(".git")
        try "gitdir: /bare/wt".write(to: dotGit, atomically: true, encoding: .utf8)

        XCTAssertTrue(kit.isLinkedWorktree(at: wtPath.path))
    }
}
