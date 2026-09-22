import XCTest
import Foundation
@testable import JSONLJournalKit
@testable import CommandKit

final class JSONLJournalKitTests: XCTestCase {
    struct TestItem: Codable, Sendable, Equatable {
        let id: String
        let count: Int
        let timestamp: Date
    }

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("JSONLJournalKitTests_\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true) } catch { _ = error }
    }

    override func tearDown() {
        if let tempDir = tempDir {
            try? FileManager.default.removeItem(at: tempDir)
        }
        super.tearDown()
    }

    func testSingleAppendAndReadTail() throws {
        let file = tempDir.appendingPathComponent("single.jsonl").path
        let journal = JSONLJournal<TestItem>(path: file)

        let now = Date()
        let item1 = TestItem(id: "item1", count: 1, timestamp: now)
        let item2 = TestItem(id: "item2", count: 2, timestamp: now.addingTimeInterval(1))
        let item3 = TestItem(id: "item3", count: 3, timestamp: now.addingTimeInterval(2))

        XCTAssertTrue(journal.append(item1))
        XCTAssertTrue(journal.append(item2))
        XCTAssertTrue(journal.append(item3))

        let tailChronological = journal.readTail(limit: 2, chronological: true)
        XCTAssertEqual(tailChronological.count, 2)
        XCTAssertEqual(tailChronological[0].id, "item2")
        XCTAssertEqual(tailChronological[1].id, "item3")

        let tailReverse = journal.readTail(limit: 2, chronological: false)
        XCTAssertEqual(tailReverse.count, 2)
        XCTAssertEqual(tailReverse[0].id, "item3")
        XCTAssertEqual(tailReverse[1].id, "item2")
    }

    func testBatchAppend() throws {
        let file = tempDir.appendingPathComponent("batch.jsonl").path
        let journal = JSONLJournal<TestItem>(path: file)

        let items = (0..<10).map { i in
            TestItem(id: "batch_\(i)", count: i, timestamp: Date())
        }
        XCTAssertTrue(journal.append(contentsOf: items))

        let read = journal.readTail(limit: 5, chronological: true)
        XCTAssertEqual(read.count, 5)
        XCTAssertEqual(read.map(\.count), [5, 6, 7, 8, 9])
    }

    func testTornAndCorruptLinesSkipped() throws {
        let file = tempDir.appendingPathComponent("corrupt.jsonl").path
        let journal = JSONLJournal<TestItem>(path: file)

        let item1 = TestItem(id: "valid1", count: 100, timestamp: Date())
        let item2 = TestItem(id: "valid2", count: 200, timestamp: Date())

        journal.append(item1)

        // 손상 라인 (미완성 JSON 및 쓰레기 바이트) 수동 주입
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: file))
        handle.seekToEndOfFile()
        handle.write(Data("{\"id\": \"broken\", \"count\":\n".utf8))
        handle.write(Data("RANDOM_GARBAGE_BYTES_NO_JSON\n".utf8))
        try handle.close()

        journal.append(item2)

        let read = journal.readTail(limit: 10, chronological: true)
        XCTAssertEqual(read.count, 2)
        XCTAssertEqual(read[0].id, "valid1")
        XCTAssertEqual(read[1].id, "valid2")
    }

    func testConcurrentWrites() async throws {
        let file = tempDir.appendingPathComponent("concurrent.jsonl").path
        let journal = JSONLJournal<TestItem>(path: file)

        let count = 50
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    let item = TestItem(id: "task_\(i)", count: i, timestamp: Date())
                    _ = journal.append(item)
                }
            }
        }

        let read = journal.readTail(limit: count, chronological: true)
        XCTAssertEqual(read.count, count)
        let ids = Set(read.map(\.id))
        XCTAssertEqual(ids.count, count)
    }

    func testCommandJournalIntegration() throws {
        let logFile = tempDir.appendingPathComponent("commands.jsonl").path
        let customJournal = CommandJournal(path: logFile)

        customJournal.record(
            tool: "agent-lint-catalog",
            command: "agent-lint-catalog check --fast",
            exitCode: 0,
            durationMs: 42.5,
            sessionId: "test-session-123",
            workingDirectory: "/tmp",
            actor: "test-agent"
        )

        let entries = customJournal.recent(limit: 10)
        XCTAssertEqual(entries.count, 1)
        let entry = entries[0]
        XCTAssertEqual(entry.tool, "agent-lint-catalog")
        XCTAssertEqual(entry.command, "agent-lint-catalog check --fast")
        XCTAssertEqual(entry.exitCode, 0)
        XCTAssertEqual(entry.durationMs, 42.5)
        XCTAssertEqual(entry.sessionId, "test-session-123")
        XCTAssertEqual(entry.workingDirectory, "/tmp")
        XCTAssertEqual(entry.actor, "test-agent")
        XCTAssertTrue(entry.isSuccess)
    }
}
