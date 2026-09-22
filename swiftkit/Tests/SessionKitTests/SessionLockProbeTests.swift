import Foundation
import XCTest
@testable import SessionKit

final class SessionLockProbeTests: XCTestCase {
    func testLockFileURLForAntigravity() {
        let home = URL(fileURLWithPath: "/custom/home")
        let url = SessionLockProbe.lockFileURL(runtime: .agy, sessionID: "test-uuid-1234", home: home)
        XCTAssertEqual(
            url?.path,
            "/custom/home/.gemini/antigravity-cli/presence/test-uuid-1234.lock"
        )
    }

    func testInspectReturnsUnlockedWhenNoFileExists() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lock-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let probe = SessionLockProbe()
        let status = probe.inspect(runtime: .agy, sessionID: "absent-session", home: tempDir)
        XCTAssertEqual(status, .unlocked)
    }

    func testInspectReturnsOrphanedWhenFileExistsWithoutHolder() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lock-test-\(UUID().uuidString)")
        let presenceDir = tempDir.appendingPathComponent(".gemini/antigravity-cli/presence", isDirectory: true)
        try FileManager.default.createDirectory(at: presenceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockFile = presenceDir.appendingPathComponent("dummy-session.lock")
        try Data().write(to: lockFile)

        let probe = SessionLockProbe()
        let status = probe.inspect(runtime: .agy, sessionID: "dummy-session", home: tempDir)
        XCTAssertEqual(status, .orphaned(lockPath: lockFile.path))

        // Test auto-reclaim
        let reclaimed = probe.reclaimIfNeeded(runtime: .agy, sessionID: "dummy-session", home: tempDir)
        XCTAssertTrue(reclaimed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockFile.path))
    }

    func testCleanAllOrphanedLocksRemovesUnheldLocks() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lock-clean-\(UUID().uuidString)")
        let agyPresence = tempDir.appendingPathComponent(".gemini/antigravity-cli/presence", isDirectory: true)
        let claudeIde = tempDir.appendingPathComponent(".claude/ide", isDirectory: true)
        try FileManager.default.createDirectory(at: agyPresence, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeIde, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create 2 orphaned locks
        try Data().write(to: agyPresence.appendingPathComponent("orphan-1.lock"))
        try Data().write(to: claudeIde.appendingPathComponent("999999.lock")) // non-existent PID

        let probe = SessionLockProbe()
        let cleaned = probe.cleanAllOrphanedLocks(home: tempDir)
        XCTAssertEqual(cleaned, 2)
    }

    func testInspectAndReclaimStoppedProcessLock() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lock-stop-\(UUID().uuidString)")
        let presenceDir = tempDir.appendingPathComponent(".gemini/antigravity-cli/presence", isDirectory: true)
        try FileManager.default.createDirectory(at: presenceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockFile = presenceDir.appendingPathComponent("stopped-session.lock")
        try Data().write(to: lockFile)

        // Spawn a process holding the lock file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec 3>\"$1\"; sleep 60", "sh", lockFile.path]
        try process.run()
        let pid = process.processIdentifier
        defer {
            kill(pid, SIGKILL)
        }

        // Give process a moment to open the file descriptor, then stop it
        Thread.sleep(forTimeInterval: 0.1)
        kill(pid, SIGSTOP)
        Thread.sleep(forTimeInterval: 0.05)

        let probe = SessionLockProbe()
        let status = probe.inspect(runtime: .agy, sessionID: "stopped-session", home: tempDir)
        
        switch status {
        case .stopped(let holdingPID, _):
            XCTAssertEqual(holdingPID, pid)
        default:
            XCTFail("Expected .stopped status, got: \(status)")
        }

        // Auto-reclaim should kill the stopped process and remove the lock file
        let reclaimed = probe.reclaimIfNeeded(runtime: .agy, sessionID: "stopped-session", home: tempDir)
        XCTAssertTrue(reclaimed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: lockFile.path))

        // Process should now be dead
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(kill(pid, 0), -1) // ESRCH
    }

    func testInspectActiveProcessDoesNotKill() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lock-active-\(UUID().uuidString)")
        let presenceDir = tempDir.appendingPathComponent(".gemini/antigravity-cli/presence", isDirectory: true)
        try FileManager.default.createDirectory(at: presenceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockFile = presenceDir.appendingPathComponent("active-session.lock")
        try Data().write(to: lockFile)

        // Spawn an active process holding the lock file
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "exec 3>\"$1\"; sleep 60", "sh", lockFile.path]
        try process.run()
        let pid = process.processIdentifier
        defer {
            kill(pid, SIGKILL)
        }

        Thread.sleep(forTimeInterval: 0.1)

        let probe = SessionLockProbe()
        let status = probe.inspect(runtime: .agy, sessionID: "active-session", home: tempDir)

        switch status {
        case .active(let holdingPID, _):
            XCTAssertEqual(holdingPID, pid)
        default:
            XCTFail("Expected .active status, got: \(status)")
        }

        // Active process must NOT be reclaimed/killed
        let reclaimed = probe.reclaimIfNeeded(runtime: .agy, sessionID: "active-session", home: tempDir)
        XCTAssertFalse(reclaimed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: lockFile.path))

        // Process must still be alive
        XCTAssertEqual(kill(pid, 0), 0)
    }
}
