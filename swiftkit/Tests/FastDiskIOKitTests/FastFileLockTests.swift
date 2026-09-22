import FastDiskIOKit
import Foundation
import Testing

@Suite("FastFileLockTests")
struct FastFileLockTests {
    @Test("withLock blocking exclusive execution")
    func testWithLockExclusive() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fastfilelock-tests-\(UUID().uuidString)")
        let lockURL = tempDir.appendingPathComponent("test.lock")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var executed = false
        try FastFileLock.withLock(at: lockURL) {
            executed = true
            #expect(FileManager.default.fileExists(atPath: lockURL.path))
        }
        #expect(executed)
    }

    @Test("tryWithLock non-blocking contention")
    func testTryWithLockContention() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fastfilelock-tests-\(UUID().uuidString)")
        let lockURL = tempDir.appendingPathComponent("contention.lock")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lock1 = FastFileLock(url: lockURL)
        #expect(lock1.acquire(exclusive: true, nonBlocking: true))
        #expect(lock1.isHeld)

        // 다른 tryWithLock 시도 시 즉시 실패 (nil)
        let acquiredSecond = try FastFileLock.tryWithLock(at: lockURL) {
            true
        }
        #expect(acquiredSecond == nil)

        // lock1 해제
        lock1.release()
        #expect(!lock1.isHeld)

        // 해제 후 정상 획득 가능
        let acquiredAfterRelease = try FastFileLock.tryWithLock(at: lockURL) {
            true
        }
        #expect(acquiredAfterRelease != nil)
    }

    @Test("exclusive around targetURL helper")
    func testExclusiveAround() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("fastfilelock-tests-\(UUID().uuidString)")
        let targetURL = tempDir.appendingPathComponent("data.json")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var ran = false
        try FastFileLock.exclusive(around: targetURL) {
            ran = true
            #expect(FileManager.default.fileExists(atPath: targetURL.appendingPathExtension("lock").path))
        }
        #expect(ran)
    }
}
