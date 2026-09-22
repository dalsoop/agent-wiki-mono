import XCTest
@testable import WorktreeKit

final class WorktreeLockCoordinatorTests: XCTestCase {
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

    func testLockContentionDetector_identifiesLockErrors() {
        XCTAssertTrue(WorktreeLockContentionDetector.isLockContention("fatal: Unable to create '/path/to/.bare/index.lock': File exists."))
        let lockRefMsg = "error: cannot lock ref 'refs/heads/feature': " +
            "Unable to create '...lock': File exists"
        XCTAssertTrue(WorktreeLockContentionDetector.isLockContention(lockRefMsg))
        XCTAssertTrue(WorktreeLockContentionDetector.isLockContention("fatal: Another git process seems to be running in this repository"))
        XCTAssertTrue(WorktreeLockContentionDetector.isLockContention("fatal: Unable to create '/path/worktrees/feat.lock': File exists."))
        XCTAssertTrue(WorktreeLockContentionDetector.isLockContention("fatal: Resource temporarily unavailable"))

        // 일반 오류는 lock contention이 아님
        XCTAssertFalse(WorktreeLockContentionDetector.isLockContention("fatal: invalid reference: origin/nonexistent"))
        XCTAssertFalse(WorktreeLockContentionDetector.isLockContention("fatal: not a git repository (or any of the parent directories): .git"))
        XCTAssertFalse(WorktreeLockContentionDetector.isLockContention(""))
    }

    func testBackoffDelayIncreasesWithAttempt() {
        let delay0 = WorktreeLockCoordinator.backoffDelay(attempt: 0, baseDelay: 0.1)
        let delay1 = WorktreeLockCoordinator.backoffDelay(attempt: 1, baseDelay: 0.1)
        let delay2 = WorktreeLockCoordinator.backoffDelay(attempt: 2, baseDelay: 0.1)

        XCTAssertGreaterThan(delay0, 0.1)
        XCTAssertGreaterThan(delay1, delay0 - 0.05) // 지터 편차 감안
        XCTAssertGreaterThan(delay2, delay1 - 0.05)
    }

    func testFileLockAcquisitionAndRelease() async throws {
        let coordinator = WorktreeLockCoordinator()
        let lockPath = tempDir.appendingPathComponent("test.lock").path

        let result = try await coordinator.withLock(lockPath: lockPath, timeout: 5.0) {
            XCTAssertTrue(FileManager.default.fileExists(atPath: lockPath))
            return 42
        }

        XCTAssertEqual(result, 42)
    }

    func testInProcessLockSerialization() async throws {
        let coordinator = WorktreeLockCoordinator()
        let lockPath = tempDir.appendingPathComponent("concurrent.lock").path

        actor ExecutionTracker {
            private(set) var activeCount = 0
            private(set) var maxConcurrent = 0

            func enter() {
                activeCount += 1
                if activeCount > maxConcurrent {
                    maxConcurrent = activeCount
                }
            }

            func leave() {
                activeCount -= 1
            }
        }

        let tracker = ExecutionTracker()

        // 3개의 비동기 작업이 동일 락 파일로 동시에 요청
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<3 {
                group.addTask {
                    try await coordinator.withLock(lockPath: lockPath, timeout: 10.0) {
                        await tracker.enter()
                        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
                        await tracker.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        let maxConcurrent = await tracker.maxConcurrent
        XCTAssertEqual(maxConcurrent, 1, "동일 락 경로에 대해서는 절대 동시에 2개 이상 실행되면 안 됨 (직렬화 보장)")
    }
}
