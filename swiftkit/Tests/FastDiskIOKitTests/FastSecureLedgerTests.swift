import XCTest
import Foundation
@testable import FastDiskIOKit

private struct MockRecord: Codable, Sendable, Equatable {
    var id: String
    var counter: Int
    var note: String
}

final class FastSecureLedgerTests: XCTestCase {
    private var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FastSecureLedgerTests_\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testSecureLedgerRoundTripAndPermissions() throws {
        let fileURL = tempDir.appendingPathComponent("sub/ledger.json")
        let ledger = FastSecureLedger<MockRecord>(
            fileURL: fileURL,
            directoryPermissions: 0o700,
            filePermissions: 0o600,
            default: { MockRecord(id: "default", counter: 0, note: "init") }
        )

        // 파일이 없을 때 기본값 로드
        let initial = try ledger.load()
        XCTAssertEqual(initial.id, "default")
        XCTAssertFalse(ledger.exists)

        // 저장 후 확인
        let updated = MockRecord(id: "rec-1", counter: 42, note: "hello")
        try ledger.save(updated)
        XCTAssertTrue(ledger.exists)

        let loaded = try ledger.load()
        XCTAssertEqual(loaded, updated)

        // 퍼미션 검증 (파일 0600, 디렉터리 0700)
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: fileURL.deletingLastPathComponent().path)
        let dirMode = (dirAttrs[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(dirMode, 0o700)

        let fileAttrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let fileMode = (fileAttrs[.posixPermissions] as? NSNumber)?.uint16Value
        XCTAssertEqual(fileMode, 0o600)

        // mutate 트랜잭션 검증
        let mutateRes = try ledger.mutate { record in
            record.counter += 10
            return record.counter
        }
        XCTAssertEqual(mutateRes, 52)

        let reloaded = try ledger.load()
        XCTAssertEqual(reloaded.counter, 52)

        // delete 검증
        try ledger.delete()
        XCTAssertFalse(ledger.exists)
    }

    func testProcessLockAcquireAndContention() throws {
        let lockURL = tempDir.appendingPathComponent("daemon.lock")
        let lock1 = FastProcessLock(url: lockURL)
        let lock2 = FastProcessLock(url: lockURL)

        XCTAssertTrue(lock1.tryAcquire())
        XCTAssertTrue(lock1.isHeld)

        // 홀더 PID 확인
        let holderPID = lock1.currentHolderPID()
        XCTAssertEqual(holderPID, getpid())

        // lock2는 동시에 획득 불가
        XCTAssertFalse(lock2.tryAcquire())
        XCTAssertFalse(lock2.isHeld)

        // lock1 해제 후 lock2 획득 가능
        lock1.release()
        XCTAssertFalse(lock1.isHeld)

        XCTAssertTrue(lock2.tryAcquire())
        XCTAssertTrue(lock2.isHeld)
        lock2.release()
    }
}
