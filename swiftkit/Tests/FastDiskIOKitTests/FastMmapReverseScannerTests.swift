import XCTest
@testable import FastDiskIOKit

final class FastMmapReverseScannerTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FastMmapReverseScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    private func createTempFile(content: String) throws -> String {
        let fileURL = tempDir.appendingPathComponent("test-\(UUID().uuidString).log")
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL.path
    }

    // MARK: - 1. 빈 파일 테스트 (Empty File)
    func testEmptyFile() throws {
        let path = try createTempFile(content: "")
        let scanner = try FastMmapReverseScanner(path: path)

        let lines = scanner.tailLines(limit: 10)
        XCTAssertEqual(lines, [])

        var scanCount = 0
        scanner.scanReverse(limit: 10) { _ in
            scanCount += 1
            return true
        }
        XCTAssertEqual(scanCount, 0)
    }

    // MARK: - 2. 단일 라인 테스트 (Single Line, With/Without Newline)
    func testSingleLineWithoutNewline() throws {
        let path = try createTempFile(content: "hello world")
        let scanner = try FastMmapReverseScanner(path: path)

        XCTAssertEqual(scanner.tailLines(limit: 1), ["hello world"])
        XCTAssertEqual(scanner.tailLines(limit: 5), ["hello world"])
    }

    func testSingleLineWithNewline() throws {
        let path = try createTempFile(content: "hello world\n")
        let scanner = try FastMmapReverseScanner(path: path)

        XCTAssertEqual(scanner.tailLines(limit: 1), ["hello world"])
        XCTAssertEqual(scanner.tailLines(limit: 5), ["hello world"])
    }

    // MARK: - 3. 빈 라인만 존재하는 파일 테스트
    func testEmptyLinesOnly() throws {
        let path1 = try createTempFile(content: "\n")
        let scanner1 = try FastMmapReverseScanner(path: path1)
        XCTAssertEqual(scanner1.tailLines(limit: 10), [""])

        let path2 = try createTempFile(content: "\n\n")
        let scanner2 = try FastMmapReverseScanner(path: path2)
        XCTAssertEqual(scanner2.tailLines(limit: 10), ["", ""])

        let path3 = try createTempFile(content: "\r\n\r\n")
        let scanner3 = try FastMmapReverseScanner(path: path3)
        XCTAssertEqual(scanner3.tailLines(limit: 10), ["", ""])
    }

    // MARK: - 4. 개행 종료 vs 비개행 종료 다중 라인 테스트
    func testMultiLineEndingWithNewline() throws {
        let content = "line1\nline2\nline3\n"
        let path = try createTempFile(content: content)
        let scanner = try FastMmapReverseScanner(path: path)

        XCTAssertEqual(scanner.tailLines(limit: 2), ["line2", "line3"])
        XCTAssertEqual(scanner.tailLines(limit: 3), ["line1", "line2", "line3"])
        XCTAssertEqual(scanner.tailLines(limit: 10), ["line1", "line2", "line3"])
        XCTAssertEqual(scanner.tailLines(limit: 2, reversed: true), ["line3", "line2"])
    }

    func testMultiLineEndingWithoutNewline() throws {
        let content = "line1\nline2\nline3"
        let path = try createTempFile(content: content)
        let scanner = try FastMmapReverseScanner(path: path)

        XCTAssertEqual(scanner.tailLines(limit: 2), ["line2", "line3"])
        XCTAssertEqual(scanner.tailLines(limit: 3), ["line1", "line2", "line3"])
        XCTAssertEqual(scanner.tailLines(limit: 10), ["line1", "line2", "line3"])
        XCTAssertEqual(scanner.tailLines(limit: 3, reversed: true), ["line3", "line2", "line1"])
    }

    // MARK: - 5. Windows CRLF 개행 테스트
    func testWindowsCRLFNewlines() throws {
        let content = "alpha\r\nbeta\r\ngamma\r\n"
        let path = try createTempFile(content: content)
        let scanner = try FastMmapReverseScanner(path: path)

        XCTAssertEqual(scanner.tailLines(limit: 2), ["beta", "gamma"])
        XCTAssertEqual(scanner.tailLines(limit: 3), ["alpha", "beta", "gamma"])
    }

    // MARK: - 6. Limit 0 및 음수 처리
    func testZeroAndNegativeLimit() throws {
        let content = "alpha\nbeta\ngamma\n"
        let path = try createTempFile(content: content)
        let scanner = try FastMmapReverseScanner(path: path)

        XCTAssertEqual(scanner.tailLines(limit: 0), [])
        XCTAssertEqual(scanner.tailLines(limit: -1), [])

        var called = false
        scanner.scanReverse(limit: 0) { _ in
            called = true
            return true
        }
        XCTAssertFalse(called)
    }

    // MARK: - 7. scanReverse 조기 중단 (Early Stop)
    func testScanReverseEarlyStop() throws {
        let content = "line1\nline2\nline3\nline4\nline5\n"
        let path = try createTempFile(content: content)
        let scanner = try FastMmapReverseScanner(path: path)

        var scanned: [String] = []
        scanner.scanReverse(limit: 5) { buf in
            let str = String(decoding: buf, as: UTF8.self)
            scanned.append(str)
            return scanned.count < 2 // 2개만 읽고 중단
        }

        XCTAssertEqual(scanned, ["line5", "line4"])
    }

    // MARK: - 8. 제로카피 포인터 주소 범위 검증 (Zero-Copy Pointer Verification)
    func testZeroCopyPointerRange() throws {
        let content = "first line\nsecond line\nthird line\n"
        let path = try createTempFile(content: content)
        let scanner = try FastMmapReverseScanner(path: path)

        guard let basePtr = scanner.buffer.pointer else {
            XCTFail("Buffer pointer should not be nil")
            return
        }
        let baseAddress = UInt(bitPattern: basePtr)
        let endAddress = baseAddress + UInt(scanner.buffer.size)

        scanner.scanReverse(limit: 3) { buf in
            guard let lineStart = buf.baseAddress else {
                XCTFail("Line buffer pointer should be non-nil")
                return true
            }
            let lineAddr = UInt(bitPattern: lineStart)
            XCTAssertGreaterThanOrEqual(lineAddr, baseAddress)
            XCTAssertLessThanOrEqual(lineAddr + UInt(buf.count), endAddress)
            return true
        }
    }

    // MARK: - 9. Static Convenience API 테스트
    func testStaticTailLines() throws {
        let content = "a\nb\nc\n"
        let path = try createTempFile(content: content)
        let lines = try FastMmapReverseScanner.tailLines(path: path, limit: 2)
        XCTAssertEqual(lines, ["b", "c"])
    }

    // MARK: - 10. 수만 줄 대용량 파일 역방향 스캔 검증 (Large File Stress Test)
    func testLargeFileReverseScan() throws {
        let lineCount = 50_000
        let fileURL = tempDir.appendingPathComponent("large-50k.log")

        // 50,000줄 파일 생성
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        guard let fileHandle = FileHandle(forWritingAtPath: fileURL.path) else {
            XCTFail("Failed to open file for writing")
            return
        }

        var chunk = Data()
        chunk.reserveCapacity(64 * 1024)
        for i in 1...lineCount {
            let line = "2026-09-19T00:00:00.000Z [INFO] Service worker trace log entry payload #\(i)\n"
            if let data = line.data(using: .utf8) {
                chunk.append(data)
            }
            if chunk.count >= 64 * 1024 {
                fileHandle.write(chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty {
            fileHandle.write(chunk)
        }
        fileHandle.closeFile()

        let scanner = try FastMmapReverseScanner(path: fileURL.path)

        // 마지막 100줄 추출 검증
        let tail100 = scanner.tailLines(limit: 100)
        XCTAssertEqual(tail100.count, 100)
        XCTAssertEqual(tail100.first, "2026-09-19T00:00:00.000Z [INFO] Service worker trace log entry payload #49901")
        XCTAssertEqual(tail100.last, "2026-09-19T00:00:00.000Z [INFO] Service worker trace log entry payload #50000")

        // 역순 추출 검증
        let tail5Reversed = scanner.tailLines(limit: 5, reversed: true)
        XCTAssertEqual(tail5Reversed.count, 5)
        XCTAssertEqual(tail5Reversed[0], "2026-09-19T00:00:00.000Z [INFO] Service worker trace log entry payload #50000")
        XCTAssertEqual(tail5Reversed[1], "2026-09-19T00:00:00.000Z [INFO] Service worker trace log entry payload #49999")
        XCTAssertEqual(tail5Reversed[4], "2026-09-19T00:00:00.000Z [INFO] Service worker trace log entry payload #49996")
    }
}
