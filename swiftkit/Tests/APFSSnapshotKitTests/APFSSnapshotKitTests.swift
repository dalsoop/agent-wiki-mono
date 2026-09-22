import XCTest
import CommandKit
@testable import APFSSnapshotKit

import os

/// 목 명령 실행기
private final class MockCommandRunner: CommandRunning, Sendable {
    private struct State: Sendable {
        var responses: [String: (exitCode: Int32, stdout: String, stderr: String)] = [:]
        var recordedCalls: [(executable: String, args: [String])] = []
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    func setResponse(
        matching key: String,
        exitCode: Int32 = 0,
        stdout: String = "",
        stderr: String = ""
    ) {
        state.withLock {
            $0.responses[key] = (exitCode, stdout, stderr)
        }
    }

    func getRecordedCalls() -> [(executable: String, args: [String])] {
        state.withLock { $0.recordedCalls }
    }

    func run(_ launchPath: String, _ arguments: [String], timeout: TimeInterval?) async -> CommandResult {
        let (matchedExitCode, matchedStdout, matchedStderr) = state.withLock { s -> (Int32, String, String) in
            s.recordedCalls.append((launchPath, arguments))
            let key = ([launchPath] + arguments).joined(separator: " ")
            if let matched = s.responses[key] {
                return (matched.exitCode, matched.stdout, matched.stderr)
            }
            for (pattern, resp) in s.responses {
                if key.contains(pattern) {
                    return (resp.exitCode, resp.stdout, resp.stderr)
                }
            }
            return (0, "", "")
        }

        return CommandResult(
            stdout: matchedStdout,
            stderr: matchedStderr,
            exitCode: matchedExitCode
        )
    }
}

final class APFSSnapshotKitTests: XCTestCase {
    private var tempDirectory: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("apfs-kit-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if FileManager.default.fileExists(atPath: tempDirectory.path) {
            do {
                try FileManager.default.removeItem(at: tempDirectory)
            } catch {
                _ = error
            }
        }
        super.tearDown()
    }

    // MARK: - 1. Parser Tests

    func testParseCreatedSnapshotStandardOutput() throws {
        let output = """
        Created local snapshot with date: 2026-09-07-200714
        """
        let snapshot = try APFSSnapshotParser.parseCreatedSnapshot(from: output, volumePath: "/System/Volumes/Data", deviceNode: "/dev/disk3s5")
        XCTAssertEqual(snapshot.dateString, "2026-09-07-200714")
        XCTAssertEqual(snapshot.name, "com.apple.TimeMachine.2026-09-07-200714.local")
        XCTAssertEqual(snapshot.volumePath, "/System/Volumes/Data")
        XCTAssertEqual(snapshot.deviceNode, "/dev/disk3s5")
        XCTAssertNotNil(snapshot.date)
    }

    func testParseCreatedSnapshotQuotedOutput() throws {
        let output = """
        Created local snapshot 'com.apple.TimeMachine.2026-09-07-210530.local'
        """
        let snapshot = try APFSSnapshotParser.parseCreatedSnapshot(from: output, volumePath: "/")
        XCTAssertEqual(snapshot.name, "com.apple.TimeMachine.2026-09-07-210530.local")
        XCTAssertEqual(snapshot.dateString, "2026-09-07-210530")
    }

    func testParseCreatedSnapshotFailureThrows() {
        let output = "Some random error occurred"
        XCTAssertThrowsError(try APFSSnapshotParser.parseCreatedSnapshot(from: output, volumePath: "/")) { error in
            guard case APFSSnapshotError.snapshotCreationFailed = error else {
                XCTFail("Expected snapshotCreationFailed, got \(error)")
                return
            }
        }
    }

    func testParseSnapshotListMultipleEntries() {
        let output = """
        Snapshots for volume group containing disk /:
        com.apple.TimeMachine.2026-09-07-100000.local
        com.apple.TimeMachine.2026-09-07-123456.local
        com.apple.TimeMachine.2026-09-07-180000.local
        """
        let list = APFSSnapshotParser.parseSnapshotList(from: output, volumePath: "/System/Volumes/Data")
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0].dateString, "2026-09-07-100000")
        XCTAssertEqual(list[1].dateString, "2026-09-07-123456")
        XCTAssertEqual(list[2].dateString, "2026-09-07-180000")
        XCTAssertEqual(list[0].name, "com.apple.TimeMachine.2026-09-07-100000.local")
    }

    // MARK: - 2. APFSSnapshotManager Lifecycle Tests

    func testCreateLocalSnapshotRunsTmutil() async throws {
        let mockRunner = MockCommandRunner()
        mockRunner.setResponse(
            matching: "localsnapshot",
            exitCode: 0,
            stdout: "Created local snapshot with date: 2026-09-07-200714\n"
        )

        let manager = APFSSnapshotManager(runner: mockRunner)
        let snapshot = try await manager.createLocalSnapshot(volumePath: "/System/Volumes/Data")

        XCTAssertEqual(snapshot.dateString, "2026-09-07-200714")
        let calls = mockRunner.getRecordedCalls()
        XCTAssertTrue(calls.contains { $0.executable.contains("tmutil") && $0.args.contains("localsnapshot") })
    }

    func testMountSnapshotRunsMountApfsWithReadOnly() async throws {
        let mockRunner = MockCommandRunner()
        mockRunner.setResponse(matching: "mount_apfs", exitCode: 0, stdout: "")

        let manager = APFSSnapshotManager(runner: mockRunner)
        let mountPoint = tempDirectory.appendingPathComponent("mount_target", isDirectory: true)

        let snapshot = APFSSnapshot(
            name: "com.apple.TimeMachine.2026-09-07-200714.local",
            dateString: "2026-09-07-200714",
            volumePath: "/System/Volumes/Data",
            deviceNode: "/dev/disk3s5"
        )

        try await manager.mountSnapshot(snapshot, mountPoint: mountPoint, readOnly: true)

        let calls = mockRunner.getRecordedCalls()
        guard let mountCall = calls.first(where: { $0.executable.contains("mount_apfs") }) else {
            XCTFail("mount_apfs was not called")
            return
        }

        XCTAssertTrue(mountCall.args.contains("-s"))
        XCTAssertTrue(mountCall.args.contains(snapshot.name))
        XCTAssertTrue(mountCall.args.contains("-o"))
        XCTAssertTrue(mountCall.args.contains("rdonly"))
        XCTAssertTrue(mountCall.args.contains("/dev/disk3s5"))
        XCTAssertTrue(mountCall.args.contains(mountPoint.path))
    }

    func testUnmountSnapshotEscalatesToForceDiskutilOnFailure() async throws {
        let mockRunner = MockCommandRunner()
        mockRunner.setResponse(matching: "umount", exitCode: 1, stderr: "Resource busy")
        mockRunner.setResponse(matching: "diskutil unmount force", exitCode: 0, stdout: "Unmounted")

        let manager = APFSSnapshotManager(runner: mockRunner)
        let mountPoint = tempDirectory.appendingPathComponent("busy_mount", isDirectory: true)

        try await manager.unmountSnapshot(mountPoint: mountPoint, force: false)

        let calls = mockRunner.getRecordedCalls()
        XCTAssertTrue(calls.contains { $0.executable.contains("umount") })
        XCTAssertTrue(calls.contains { $0.executable.contains("diskutil") && $0.args.contains("force") })
    }

    func testDeleteLocalSnapshotRunsTmutilDelete() async throws {
        let mockRunner = MockCommandRunner()
        mockRunner.setResponse(
            matching: "deletelocalsnapshots",
            exitCode: 0,
            stdout: "Deleted local snapshot '2026-09-07-200714'\n"
        )

        let manager = APFSSnapshotManager(runner: mockRunner)
        try await manager.deleteLocalSnapshot(dateString: "2026-09-07-200714")

        let calls = mockRunner.getRecordedCalls()
        XCTAssertTrue(calls.contains {
            $0.executable.contains("tmutil") &&
            $0.args.contains("deletelocalsnapshots") &&
            $0.args.contains("2026-09-07-200714")
        })
    }

    // MARK: - 3. APFSPointInTimeSession Scoped Lifecycle Tests

    func testPointInTimeSessionGuaranteesMountAndCleanup() async throws {
        let mockRunner = MockCommandRunner()
        mockRunner.setResponse(
            matching: "localsnapshot",
            exitCode: 0,
            stdout: "Created local snapshot with date: 2026-09-07-200714\n"
        )
        mockRunner.setResponse(matching: "mount_apfs", exitCode: 0, stdout: "")
        mockRunner.setResponse(matching: "umount", exitCode: 0, stdout: "")
        mockRunner.setResponse(matching: "deletelocalsnapshots", exitCode: 0, stdout: "")

        let manager = APFSSnapshotManager(runner: mockRunner)
        let customMount = tempDirectory.appendingPathComponent("scoped_mount", isDirectory: true)

        let sessionConfig = APFSPointInTimeSessionConfiguration(
            customVolumePath: "/",
            customMountDirectory: customMount,
            cleanupSnapshotOnClose: true,
            readOnly: true
        )

        let (isMounted, mountPath, snapshotDate) = try await APFSPointInTimeSession.withSession(
            sourceURL: tempDirectory,
            configuration: sessionConfig,
            manager: manager
        ) { session in
            let isMounted = await session.isMounted
            let mountPoint = await session.mountPoint
            let activeSnapshot = await session.activeSnapshot
            return (isMounted, mountPoint?.path, activeSnapshot?.dateString)
        }

        XCTAssertTrue(isMounted)
        XCTAssertEqual(mountPath, customMount.path)
        XCTAssertEqual(snapshotDate, "2026-09-07-200714")
        let calls = mockRunner.getRecordedCalls()
        XCTAssertTrue(calls.contains { $0.args.contains("localsnapshot") })
        XCTAssertTrue(calls.contains { $0.args.contains("-s") })
        XCTAssertTrue(calls.contains { $0.executable.contains("umount") })
        XCTAssertTrue(calls.contains { $0.args.contains("deletelocalsnapshots") })
    }

    func testPointInTimeSessionCleansUpEvenWhenBlockThrows() async throws {
        let mockRunner = MockCommandRunner()
        mockRunner.setResponse(
            matching: "localsnapshot",
            exitCode: 0,
            stdout: "Created local snapshot with date: 2026-09-07-200714\n"
        )
        mockRunner.setResponse(matching: "mount_apfs", exitCode: 0, stdout: "")
        mockRunner.setResponse(matching: "umount", exitCode: 0, stdout: "")
        mockRunner.setResponse(matching: "deletelocalsnapshots", exitCode: 0, stdout: "")

        let manager = APFSSnapshotManager(runner: mockRunner)
        let customMount = tempDirectory.appendingPathComponent("throw_mount", isDirectory: true)

        let sessionConfig = APFSPointInTimeSessionConfiguration(
            customVolumePath: "/",
            customMountDirectory: customMount,
            cleanupSnapshotOnClose: true
        )

        enum TestError: Error { case intentional }

        do {
            try await APFSPointInTimeSession.withSession(
                sourceURL: tempDirectory,
                configuration: sessionConfig,
                manager: manager
            ) { _ in
                throw TestError.intentional
            }
            XCTFail("Should have thrown")
        } catch TestError.intentional {
            // Success
        }

        let calls = mockRunner.getRecordedCalls()
        XCTAssertTrue(calls.contains { $0.executable.contains("umount") }, "Snapshot must be unmounted on error")
        XCTAssertTrue(calls.contains { $0.args.contains("deletelocalsnapshots") }, "Snapshot must be deleted on error")
    }

    // MARK: - 4. Fast Change Detection (APFSSnapshotDiffEngine) Tests

    func testDiffEngineDetectsAddedModifiedDeletedFiles() throws {
        let baselineDir = tempDirectory.appendingPathComponent("baseline", isDirectory: true)
        let targetDir = tempDirectory.appendingPathComponent("target", isDirectory: true)

        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        // 1. Unmodified file
        try "unmodified content".write(to: baselineDir.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)
        try "unmodified content".write(to: targetDir.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)

        // 2. Modified file
        let modBase = baselineDir.appendingPathComponent("modified.txt")
        let modTarget = targetDir.appendingPathComponent("modified.txt")
        try "original content".write(to: modBase, atomically: true, encoding: .utf8)
        try "updated content with different size".write(to: modTarget, atomically: true, encoding: .utf8)

        // 3. Deleted file
        try "deleted file".write(to: baselineDir.appendingPathComponent("deleted.txt"), atomically: true, encoding: .utf8)

        // 4. Added file
        try "newly added file".write(to: targetDir.appendingPathComponent("added.txt"), atomically: true, encoding: .utf8)

        let report = try APFSSnapshotDiffEngine.computeDiff(baselineURL: baselineDir, targetURL: targetDir)

        XCTAssertEqual(report.addedCount, 1)
        XCTAssertEqual(report.modifiedCount, 1)
        XCTAssertEqual(report.deletedCount, 1)
        XCTAssertEqual(report.unmodifiedCount, 1)
        XCTAssertEqual(report.totalChangesCount, 3)

        XCTAssertTrue(report.changes.contains { $0.relativePath == "added.txt" && $0.kind == .added })
        XCTAssertTrue(report.changes.contains { $0.relativePath == "modified.txt" && $0.kind == .modified })
        XCTAssertTrue(report.changes.contains { $0.relativePath == "deleted.txt" && $0.kind == .deleted })
    }

    func testDiffEngineRespectsExcludes() throws {
        let baselineDir = tempDirectory.appendingPathComponent("base2", isDirectory: true)
        let targetDir = tempDirectory.appendingPathComponent("target2", isDirectory: true)

        try FileManager.default.createDirectory(at: baselineDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)

        try "log1".write(to: targetDir.appendingPathComponent("test.log"), atomically: true, encoding: .utf8)
        try "data".write(to: targetDir.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let report = try APFSSnapshotDiffEngine.computeDiff(
            baselineURL: baselineDir,
            targetURL: targetDir,
            excludes: ["test.log"]
        )

        XCTAssertEqual(report.addedCount, 1)
        XCTAssertEqual(report.changes.first?.relativePath, "file.txt")
    }

    // MARK: - 5. APFSSnapshotTransportEngine Tests

    func testTransportEngineFallbackOnFailure() async throws {
        let mockRunner = MockCommandRunner()
        mockRunner.setResponse(matching: "localsnapshot", exitCode: 1, stderr: "tmutil disabled")

        let manager = APFSSnapshotManager(runner: mockRunner)
        let engine = APFSSnapshotTransportEngine(manager: manager, allowLiveFallback: true)

        let execResult = try await engine.executeWithStaticSnapshot(sourceURL: tempDirectory) { url in
            return url.path
        }

        XCTAssertEqual(execResult.result, tempDirectory.path)
        XCTAssertTrue(execResult.usedLiveFallback)
    }
}
