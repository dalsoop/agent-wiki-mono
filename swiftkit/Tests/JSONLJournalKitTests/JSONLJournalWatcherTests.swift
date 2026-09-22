import XCTest
import Foundation
import os
@testable import JSONLJournalKit
@testable import CommandKit

final class JSONLJournalWatcherTests: XCTestCase {
    private struct SafeArray<T: Sendable>: Sendable {
        private let state = os.OSAllocatedUnfairLock(initialState: [T]())

        func append(_ element: T) {
            state.withLock { $0.append(element) }
        }

        var elements: [T] {
            state.withLock { $0 }
        }

        var count: Int {
            state.withLock { $0.count }
        }
    }

    func testLiveTailStreamAppendedRecords() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("commands-\(UUID().uuidString).jsonl")
        let journal = JSONLJournal<CommandTraceRecord>(path: fileURL.path)
        let watcher = JSONLJournalWatcher(journal: journal)

        let stream = watcher.liveTail()
        let received = SafeArray<CommandTraceRecord>()

        let consumerTask = Task {
            for await record in stream {
                received.append(record)
                if received.count >= 2 {
                    break
                }
            }
        }

        // 짧은 대기 후 2건 순차 append
        try await Task.sleep(for: .milliseconds(100))

        let record1 = CommandTraceRecord(
            tool: "agent-lint-catalog",
            command: "agent-lint-catalog check",
            exitCode: 0,
            durationMs: 35.0
        )
        let record2 = CommandTraceRecord(
            tool: "swift",
            command: "swift build",
            exitCode: 0,
            durationMs: 1500.0
        )

        XCTAssertTrue(journal.append(record1))
        XCTAssertTrue(journal.append(record2))

        // 스트림 수신 대기 (최대 1.5초)
        for _ in 0..<15 {
            if received.count >= 2 { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        consumerTask.cancel()

        XCTAssertEqual(received.count, 2, "kqueue watcher는 실시간 append 이벤트를 놓치지 않고 수신해야 합니다.")
        let items = received.elements
        XCTAssertEqual(items[0].tool, "agent-lint-catalog")
        XCTAssertEqual(items[1].tool, "swift")
    }

    func testTornWriteLineSplitAndMerge() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("torn-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("torn-\(UUID().uuidString).jsonl")
        let journal = JSONLJournal<CommandTraceRecord>(path: fileURL.path)
        let watcher = JSONLJournalWatcher(journal: journal)

        let stream = watcher.liveTail()
        let received = SafeArray<CommandTraceRecord>()

        let consumerTask = Task {
            for await record in stream {
                received.append(record)
                if received.count >= 1 {
                    break
                }
            }
        }

        try await Task.sleep(for: .milliseconds(100))

        let targetRecord = CommandTraceRecord(
            tool: "torn-test-tool",
            command: "run-long-task --with-arguments",
            exitCode: 0,
            durationMs: 88.0,
            sessionId: "torn-session-999"
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var fullData = try encoder.encode(targetRecord)
        fullData.append(0x0A) // 개행 포함

        // 바이트 청크를 중간에서 두 조각으로 분할
        let splitIndex = fullData.count / 2
        let part1 = fullData.subdata(in: 0..<splitIndex)
        let part2 = fullData.subdata(in: splitIndex..<fullData.count)

        // 1. 개행 없는 불완전 라인(part1) 먼저 기록
        let handle = try FileHandle(forWritingTo: fileURL)
        handle.seekToEndOfFile()
        handle.write(part1)
        try handle.synchronize()

        // 잠시 대기: kqueue 이벤트가 발생해도 개행이 없으므로 remainderData에 저장되고 yield되지 않아야 함
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(received.count, 0, "개행 없는 불완전 라인은 yield되지 않고 remainderData 버퍼에 대기해야 합니다.")

        // 2. 나머지 조각(part2) 기록 (개행 포함)
        handle.write(part2)
        try handle.synchronize()
        try handle.close()

        // 병합 및 디코딩 완료 대기
        for _ in 0..<15 {
            if received.count >= 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }

        consumerTask.cancel()

        XCTAssertEqual(received.count, 1, "분할 유입된 청크가 remainderData와 결합되어 정상 레코드로 복원되어야 합니다.")
        let merged = received.elements.first
        XCTAssertEqual(merged?.tool, "torn-test-tool")
        XCTAssertEqual(merged?.command, "run-long-task --with-arguments")
        XCTAssertEqual(merged?.sessionId, "torn-session-999")
    }
}
