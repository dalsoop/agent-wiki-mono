import XCTest
@testable import FastDiskIOKit

final class FastStorageGCTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("fast-storage-gc-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    func testPruneTemporaryFilesByExtensionAndPrefix() throws {
        let fileManager = FileManager.default
        let tmpFile = tempDirectory.appendingPathComponent("cache.tmp")
        let swpFile = tempDirectory.appendingPathComponent("document.swp")
        let prefixTmpFile = tempDirectory.appendingPathComponent(".tmp-upload-123")
        let regularFile = tempDirectory.appendingPathComponent("important.json")

        try Data("temp-data".utf8).write(to: tmpFile)
        try Data("swap-data".utf8).write(to: swpFile)
        try Data("prefix-temp-data".utf8).write(to: prefixTmpFile)
        try Data("keep-data".utf8).write(to: regularFile)

        let options = FastStorageGCOptions(
            maxTemporaryAge: 0, // 즉시 만료
            dryRun: false
        )

        let report = try FastStorageGC.pruneTemporaryFiles(
            at: tempDirectory.path,
            options: options,
            fileManager: fileManager
        )

        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.prunedFiles.count, 3)
        XCTAssertFalse(fileManager.fileExists(atPath: tmpFile.path))
        XCTAssertFalse(fileManager.fileExists(atPath: swpFile.path))
        XCTAssertFalse(fileManager.fileExists(atPath: prefixTmpFile.path))
        XCTAssertTrue(fileManager.fileExists(atPath: regularFile.path))
        XCTAssertGreaterThan(report.reclaimedBytes, 0)
    }

    func testPruneTemporaryFilesByAge() throws {
        let fileManager = FileManager.default
        let oldFile = tempDirectory.appendingPathComponent("old.tmp")
        let freshFile = tempDirectory.appendingPathComponent("fresh.tmp")

        try Data("old".utf8).write(to: oldFile)
        try Data("fresh".utf8).write(to: freshFile)

        let twoDaysAgo = Date().addingTimeInterval(-172800)
        try fileManager.setAttributes([.modificationDate: twoDaysAgo], ofItemAtPath: oldFile.path)

        let options = FastStorageGCOptions(
            maxTemporaryAge: 86400, // 24시간
            dryRun: false
        )

        let report = try FastStorageGC.pruneTemporaryFiles(
            at: tempDirectory.path,
            options: options,
            fileManager: fileManager
        )

        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.prunedFiles.count, 1)
        XCTAssertEqual(report.prunedFiles.first, oldFile.path)
        XCTAssertFalse(fileManager.fileExists(atPath: oldFile.path))
        XCTAssertTrue(fileManager.fileExists(atPath: freshFile.path))
    }

    func testPruneOrphanSessions() throws {
        let fileManager = FileManager.default
        // 1. 확실히 사망한 PID 세션 디렉터리 (예: 9999999)
        let deadSessionDir = tempDirectory.appendingPathComponent("session-9999999")
        try fileManager.createDirectory(at: deadSessionDir, withIntermediateDirectories: true)
        let deadDataFile = deadSessionDir.appendingPathComponent("state.log")
        try Data("dead-session-state".utf8).write(to: deadDataFile)

        // 2. 현재 생존 중인 프로세스 PID 세션 디렉터리
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let aliveSessionDir = tempDirectory.appendingPathComponent("session-\(currentPID)")
        try fileManager.createDirectory(at: aliveSessionDir, withIntermediateDirectories: true)
        let aliveDataFile = aliveSessionDir.appendingPathComponent("state.log")
        try Data("alive-session-state".utf8).write(to: aliveDataFile)

        let options = FastStorageGCOptions(
            dryRun: false
        )

        let report = try FastStorageGC.pruneOrphanSessions(
            at: tempDirectory.path,
            options: options,
            fileManager: fileManager
        )

        XCTAssertTrue(report.isClean)
        XCTAssertEqual(report.prunedDirectories.count, 1)
        XCTAssertEqual(report.prunedDirectories.first, deadSessionDir.path)
        XCTAssertFalse(fileManager.fileExists(atPath: deadSessionDir.path))
        XCTAssertTrue(fileManager.fileExists(atPath: aliveSessionDir.path))
    }

    func testPruneEmptyDirectories() throws {
        let fileManager = FileManager.default
        let emptyParent = tempDirectory.appendingPathComponent("emptyParent")
        let emptyChild = emptyParent.appendingPathComponent("emptyChild")
        let nonEmptyDir = tempDirectory.appendingPathComponent("nonEmpty")

        try fileManager.createDirectory(at: emptyChild, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: nonEmptyDir, withIntermediateDirectories: true)
        try Data("content".utf8).write(to: nonEmptyDir.appendingPathComponent("file.txt"))

        let pruned = try FastStorageGC.pruneEmptyDirectories(
            at: tempDirectory.path,
            dryRun: false,
            fileManager: fileManager
        )

        XCTAssertTrue(pruned.contains(emptyChild.path))
        XCTAssertTrue(pruned.contains(emptyParent.path))
        XCTAssertFalse(fileManager.fileExists(atPath: emptyParent.path))
        XCTAssertTrue(fileManager.fileExists(atPath: nonEmptyDir.path))
    }

    func testDryRunDoesNotRemoveFiles() throws {
        let fileManager = FileManager.default
        let tmpFile = tempDirectory.appendingPathComponent("test.tmp")
        try Data("dry-run-data".utf8).write(to: tmpFile)

        let options = FastStorageGCOptions(
            maxTemporaryAge: 0,
            dryRun: true
        )

        let report = try FastStorageGC.collectGarbage(
            at: tempDirectory.path,
            options: options,
            fileManager: fileManager
        )

        XCTAssertEqual(report.prunedFiles.count, 1)
        XCTAssertTrue(fileManager.fileExists(atPath: tmpFile.path))
    }
}
