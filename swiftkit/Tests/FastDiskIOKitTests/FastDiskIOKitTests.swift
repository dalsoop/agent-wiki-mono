import XCTest
@testable import FastDiskIOKit

final class FastDiskIOKitTests: XCTestCase {
    var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FastDiskIOKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - FastDirectoryScanner Tests

    func testDirectoryScanner() throws {
        // Create nested structure:
        // tempDir/
        //   file1.txt
        //   sub/
        //     file2.txt
        //   .git/
        //     config
        //   node_modules/
        //     package.json
        //   .build/
        //     artifact

        let file1 = tempDir.appendingPathComponent("file1.txt")
        try "hello".write(to: file1, atomically: true, encoding: .utf8)

        let subDir = tempDir.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let file2 = subDir.appendingPathComponent("file2.txt")
        try "world".write(to: file2, atomically: true, encoding: .utf8)

        let gitDir = tempDir.appendingPathComponent(".git")
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try "git config".write(to: gitDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)

        let nodeDir = tempDir.appendingPathComponent("node_modules")
        try FileManager.default.createDirectory(at: nodeDir, withIntermediateDirectories: true)
        try "{}".write(to: nodeDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)

        let buildDir = tempDir.appendingPathComponent(".build")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try "binary".write(to: buildDir.appendingPathComponent("artifact"), atomically: true, encoding: .utf8)

        let entries = try FastDirectoryScanner.scan(root: tempDir.path)
        let names = Set(entries.map(\.name))

        XCTAssertTrue(names.contains("file1.txt"))
        XCTAssertTrue(names.contains("file2.txt"))
        XCTAssertTrue(names.contains("sub"))

        // Noise directories must be skipped
        XCTAssertFalse(names.contains(".git"))
        XCTAssertFalse(names.contains("config"))
        XCTAssertFalse(names.contains("node_modules"))
        XCTAssertFalse(names.contains("package.json"))
        XCTAssertFalse(names.contains(".build"))
        XCTAssertFalse(names.contains("artifact"))

        // Verify file entry properties
        let file1Entry = try XCTUnwrap(entries.first(where: { $0.name == "file1.txt" }))
        XCTAssertEqual(file1Entry.size, 5)
        XCTAssertFalse(file1Entry.isDirectory)
        XCTAssertGreaterThan(file1Entry.inode, 0)
    }

    func testDirectoryScannerStream() async throws {
        let file1 = tempDir.appendingPathComponent("stream_file1.txt")
        try "stream1".write(to: file1, atomically: true, encoding: .utf8)

        let stream = FastDirectoryScanner.stream(root: tempDir.path)
        var streamedEntries = [FastFileEntry]()
        for await entry in stream {
            streamedEntries.append(entry)
        }

        XCTAssertTrue(streamedEntries.contains(where: { $0.name == "stream_file1.txt" }))
    }

    // MARK: - FastFileReader & MmapBuffer Tests

    func testFastFileReaderTailLines() throws {
        let fileURL = tempDir.appendingPathComponent("tail_test.txt")
        let content = "line 1\nline 2\nline 3\nline 4\nline 5\n"
        try content.write(to: fileURL, atomically: true, encoding: .utf8)

        let tail2 = try FastFileReader.readTailLines(path: fileURL.path, maxLines: 2)
        XCTAssertEqual(tail2.map(String.init), ["line 4", "line 5"])

        let tail5 = try FastFileReader.readTailLines(path: fileURL.path, maxLines: 5)
        XCTAssertEqual(tail5.map(String.init), ["line 1", "line 2", "line 3", "line 4", "line 5"])

        let tail10 = try FastFileReader.readTailLines(path: fileURL.path, maxLines: 10)
        XCTAssertEqual(tail10.map(String.init), ["line 1", "line 2", "line 3", "line 4", "line 5"])

        let tail0 = try FastFileReader.readTailLines(path: fileURL.path, maxLines: 0)
        XCTAssertTrue(tail0.isEmpty)
    }

    func testFastFileReaderAppendChunk() throws {
        let fileURL = tempDir.appendingPathComponent("append_test.txt")
        let part1 = "Initial log line.\n"
        try part1.write(to: fileURL, atomically: true, encoding: .utf8)

        let (data1, offset1) = try FastFileReader.readAppendChunk(path: fileURL.path, fromOffset: 0)
        XCTAssertEqual(String(decoding: data1, as: UTF8.self), part1)
        XCTAssertEqual(offset1, Int64(part1.utf8.count))

        // No new data
        let (dataEmpty, offsetSame) = try FastFileReader.readAppendChunk(path: fileURL.path, fromOffset: offset1)
        XCTAssertTrue(dataEmpty.isEmpty)
        XCTAssertEqual(offsetSame, offset1)

        // Append part 2
        let part2 = "Appended line.\n"
        let handle = try FileHandle(forWritingTo: fileURL)
        handle.seekToEndOfFile()
        handle.write(Data(part2.utf8))
        handle.closeFile()

        let (data2, offset2) = try FastFileReader.readAppendChunk(path: fileURL.path, fromOffset: offset1)
        XCTAssertEqual(String(decoding: data2, as: UTF8.self), part2)
        XCTAssertEqual(offset2, Int64(part1.utf8.count + part2.utf8.count))
    }

    func testFastFileReaderForEachLineAndMmap() throws {
        let fileURL = tempDir.appendingPathComponent("mmap_test.txt")
        let lines = ["Alpha", "Beta", "Gamma", "Delta"]
        let fileContent = lines.joined(separator: "\n") + "\n"
        try fileContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Test MmapBuffer directly
        let mmap = try MmapBuffer(path: fileURL.path)
        XCTAssertEqual(mmap.size, fileContent.utf8.count)
        XCTAssertNotNil(mmap.pointer)

        // Test forEachLine zero-copy iteration
        var collected = [String]()
        try FastFileReader.forEachLine(path: fileURL.path) { buf in
            let str = String(decoding: buf, as: UTF8.self)
            collected.append(str)
            return true
        }
        XCTAssertEqual(collected, lines)

        // Test early termination in forEachLine
        var partial = [String]()
        try FastFileReader.forEachLine(path: fileURL.path) { buf in
            let str = String(decoding: buf, as: UTF8.self)
            partial.append(str)
            return partial.count < 2
        }
        XCTAssertEqual(partial, ["Alpha", "Beta"])
    }

    // MARK: - FastDateParser Tests

    func testFastDateParser() {
        let fractionalStr = "2026-09-15T00:35:53.123Z"
        let fractionalDate = FastDateParser.parse(fractionalStr)
        XCTAssertNotNil(fractionalDate)

        let standardStr = "2026-09-15T00:35:53Z"
        let standardDate = FastDateParser.parse(standardStr)
        XCTAssertNotNil(standardDate)

        guard let fDate = fractionalDate, let sDate = standardDate else {
            XCTFail("Parsed dates must not be nil")
            return
        }
        let formattedFrac = FastDateParser.format(fDate, includeFractionalSeconds: true)
        XCTAssertEqual(formattedFrac, fractionalStr)

        let formattedStd = FastDateParser.format(sDate, includeFractionalSeconds: false)
        XCTAssertEqual(formattedStd, standardStr)

        XCTAssertNil(FastDateParser.parse(nil))
        XCTAssertNil(FastDateParser.parse(""))
        XCTAssertNil(FastDateParser.parse("not-a-valid-date"))
    }

    // MARK: - FastSQLiteEngine Tests

    func testFastSQLiteEngine() throws {
        let dbPath = tempDir.appendingPathComponent("engine_test.db").path
        let engine = try FastSQLiteEngine.open(path: dbPath, readOnly: false)

        try engine.exec(sql: "CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT, ratio REAL, payload BLOB);")

        let blob = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try engine.run(
            sql: "INSERT INTO items (id, title, ratio, payload) VALUES (?, ?, ?, ?);",
            binds: [1, "First Item", 3.1415, blob]
        )

        let rows = try engine.query(sql: "SELECT id, title, ratio, payload FROM items WHERE id = ?;", binds: [1])
        XCTAssertEqual(rows.count, 1)

        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.int(for: "id"), 1)
        XCTAssertEqual(row.string(for: "title"), "First Item")
        XCTAssertEqual(try XCTUnwrap(row.double(for: "ratio")), 3.1415, accuracy: 0.0001)
        XCTAssertEqual(row.data(for: "payload"), blob)

        // Read-only open
        let roEngine = try FastSQLiteEngine.open(path: dbPath, readOnly: true)
        let roRows = try roEngine.query(sql: "SELECT count(*) AS total FROM items;")
        XCTAssertEqual(roRows.first?.int(for: "total"), 1)

        // Verify write on read-only DB fails
        XCTAssertThrowsError(try roEngine.run(sql: "INSERT INTO items (id, title) VALUES (2, 'Fail');"))
    }

    // MARK: - StatIndexStore Tests

    func testStatIndexStore() throws {
        let dbPath = tempDir.appendingPathComponent("stat_index.db").path
        let store = try StatIndexStore(path: dbPath)

        let filePath = "/test/path/file.swift"
        let mtime = Date(timeIntervalSince1970: 1700000000)
        let size: Int64 = 4096

        // Before update: should be modified / not present
        XCTAssertFalse(store.isUnmodified(path: filePath, size: size, mtime: mtime))

        // Update entry
        let payload = Data("signature-payload".utf8)
        store.update(
            path: filePath,
            inode: 123456,
            size: size,
            mtime: mtime,
            lastOffset: 4096,
            payload: payload
        )

        // After update: matching size and mtime -> unmodified
        XCTAssertTrue(store.isUnmodified(path: filePath, size: size, mtime: mtime))

        // Modified size
        XCTAssertFalse(store.isUnmodified(path: filePath, size: size + 1, mtime: mtime))

        // Modified mtime
        let newMtime = mtime.addingTimeInterval(10)
        XCTAssertFalse(store.isUnmodified(path: filePath, size: size, mtime: newMtime))

        // Verify get record
        let record = try XCTUnwrap(store.get(path: filePath))
        XCTAssertEqual(record.path, filePath)
        XCTAssertEqual(record.inode, 123456)
        XCTAssertEqual(record.size, size)
        XCTAssertEqual(record.lastOffset, 4096)
        XCTAssertEqual(record.payload, payload)
    }

    // MARK: - PersistentFSEventsWatcher & EventBookmarkStore Tests

    func testEventBookmarkStore() throws {
        let bookmarkName = "test-job-\(UUID().uuidString)"
        let eventId: UInt64 = 9876543210

        try EventBookmarkStore.save(eventId: eventId, for: bookmarkName)
        let loaded = EventBookmarkStore.load(name: bookmarkName)
        XCTAssertEqual(loaded, eventId)

        // Non-existent bookmark
        XCTAssertNil(EventBookmarkStore.load(name: "non-existent-\(UUID().uuidString)"))
    }

    func testPersistentFSEventsWatcherQuery() async throws {
        // Query changes for an empty paths list
        let (emptyChanges, emptyId) = await PersistentFSEventsWatcher.queryChangesSince(
            lastEventId: 100,
            paths: []
        )
        XCTAssertTrue(emptyChanges.isEmpty)
        XCTAssertEqual(emptyId, 100)

        // Query changes on temporary directory
        let (_, latestId) = await PersistentFSEventsWatcher.queryChangesSince(
            lastEventId: 0,
            paths: [tempDir.path]
        )
        XCTAssertGreaterThan(latestId, 0)
    }

    // MARK: - FastAtomicWriter Tests

    func testFastAtomicWriterWriteIfChanged() throws {
        let fileURL = tempDir.appendingPathComponent("subfolder/atomic_test.txt")
        let data1 = Data("Initial Content".utf8)

        // 1. Initial write to non-existent file in non-existent directory -> should write and return true
        let written1 = try FastAtomicWriter.writeIfChanged(to: fileURL, data: data1)
        XCTAssertTrue(written1)
        XCTAssertEqual(try Data(contentsOf: fileURL), data1)

        // 2. Write identical content -> should skip write and return false
        let written2 = try FastAtomicWriter.writeIfChanged(to: fileURL, data: data1)
        XCTAssertFalse(written2)

        // 3. Write different content -> should write and return true
        let data2 = Data("Modified Content".utf8)
        let written3 = try FastAtomicWriter.writeIfChanged(to: fileURL, data: data2)
        XCTAssertTrue(written3)
        XCTAssertEqual(try Data(contentsOf: fileURL), data2)

        // 4. Test empty file handling
        let emptyURL = tempDir.appendingPathComponent("empty_test.txt")
        let emptyData = Data()
        let writtenEmpty1 = try FastAtomicWriter.writeIfChanged(to: emptyURL, data: emptyData)
        XCTAssertTrue(writtenEmpty1)
        let writtenEmpty2 = try FastAtomicWriter.writeIfChanged(to: emptyURL, data: emptyData)
        XCTAssertFalse(writtenEmpty2)
    }

    // MARK: - FastJSON Tests

    private struct TestModel: Codable, Equatable {
        let id: Int
        let name: String
    }

    func testFastJSONDecodeCached() throws {
        let jsonURL = tempDir.appendingPathComponent("cached_test.json")
        let initialModel = TestModel(id: 1, name: "Alpha")
        let encoder = FastJSON.defaultEncoder
        let initialData = try encoder.encode(initialModel)

        try FastAtomicWriter.writeAtomic(to: jsonURL, data: initialData)

        // Initial decode: should populate cache
        let decoded1: TestModel = try FastJSON.decodeCached(at: jsonURL)
        XCTAssertEqual(decoded1, initialModel)

        // Decode again: should hit cache ($O(1))
        let decoded2: TestModel = try FastJSON.decodeCached(at: jsonURL)
        XCTAssertEqual(decoded2, initialModel)

        // Modify file on disk with different size/content
        sleep(1) // Ensure mtime change
        let updatedModel = TestModel(id: 2, name: "Beta Modified")
        let updatedData = try encoder.encode(updatedModel)
        try FastAtomicWriter.writeAtomic(to: jsonURL, data: updatedData)

        // Decode should detect mtime/size change and return updated value
        let decoded3: TestModel = try FastJSON.decodeCached(at: jsonURL)
        XCTAssertEqual(decoded3, updatedModel)

        // Test FastJSON.writeIfChanged integration
        let unchanged = try FastJSON.writeIfChanged(updatedModel, to: jsonURL)
        XCTAssertFalse(unchanged)

        let modifiedModel = TestModel(id: 3, name: "Gamma")
        let changed = try FastJSON.writeIfChanged(modifiedModel, to: jsonURL)
        XCTAssertTrue(changed)
        let decoded4: TestModel = try FastJSON.decodeCached(at: jsonURL)
        XCTAssertEqual(decoded4, modifiedModel)
    }

    func testFastAtomicWriterPreservesPermissions() throws {
        let fileURL = tempDir.appendingPathComponent("permission_test.sh")
        let initialData = Data("#!/bin/sh\necho hi\n".utf8)
        try initialData.write(to: fileURL)

        // Set executable permission 0o755
        let mode: mode_t = 0o755
        XCTAssertEqual(Darwin.chmod(fileURL.path, mode), 0)

        // Overwrite atomically with FastAtomicWriter
        let updatedData = Data("#!/bin/sh\necho updated\n".utf8)
        try FastAtomicWriter.writeAtomic(to: fileURL.path, data: updatedData)

        var st = stat()
        XCTAssertEqual(stat(fileURL.path, &st), 0)
        XCTAssertEqual(st.st_mode & 0o7777, 0o755)
    }

    func testFastAtomicWriterExplicitPermissions() throws {
        let fileURL = tempDir.appendingPathComponent("custom_perms_payload.txt")
        let samplePayload = "sample-custom-payload-data"

        // Write with explicit 0o600 permissions
        try FastAtomicWriter.writeAtomic(to: fileURL, string: samplePayload, permissions: 0o600)

        var st = stat()
        XCTAssertEqual(stat(fileURL.path, &st), 0)
        XCTAssertEqual(st.st_mode & 0o7777, 0o600)

        // Read back to verify content
        let readBack = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertEqual(readBack, samplePayload)

        // Overwrite with Data variant using 0o644
        let updatedData = Data("updated-payload".utf8)
        try FastAtomicWriter.writeAtomic(to: fileURL, data: updatedData, permissions: 0o644)
        XCTAssertEqual(stat(fileURL.path, &st), 0)
        XCTAssertEqual(st.st_mode & 0o7777, 0o644)
    }

    func testFastFileReaderChunkCapping() throws {
        let fileURL = tempDir.appendingPathComponent("capping_test.txt")
        let largeContent = String(repeating: "abcdefghij\n", count: 1000) // 11,000 bytes
        try largeContent.write(to: fileURL, atomically: true, encoding: .utf8)

        // Read with small maxBytes: 50 bytes
        let (chunk1, offset1) = try FastFileReader.readAppendChunk(path: fileURL.path, fromOffset: 0, maxBytes: 50)
        XCTAssertEqual(chunk1.count, 50)
        XCTAssertEqual(offset1, 50)

        let (chunk2, offset2) = try FastFileReader.readAppendChunk(path: fileURL.path, fromOffset: offset1, maxBytes: 50)
        XCTAssertEqual(chunk2.count, 50)
        XCTAssertEqual(offset2, 100)
    }

    func testFastSQLiteEngineURIWithSpacesAndSpecialChars() throws {
        let spaceDir = tempDir.appendingPathComponent("Folder With Spaces #1", isDirectory: true)
        try FileManager.default.createDirectory(at: spaceDir, withIntermediateDirectories: true)
        let dbURL = spaceDir.appendingPathComponent("app state.db")

        let writer = try FastSQLiteEngine.open(path: dbURL.path, readOnly: false)
        try writer.exec(sql: "CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT);")
        try writer.run(sql: "INSERT INTO items (name) VALUES (?);", binds: ["SpaceItem"])
        writer.close()

        // Read-only open with spaces and hash in path
        let reader = try FastSQLiteEngine.open(path: dbURL.path, readOnly: true)
        let rows = try reader.query(sql: "SELECT name FROM items;")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.string(for: "name"), "SpaceItem")
        reader.close()
    }

    func testFastDirectorySizeCalculator() throws {
        let subDir = tempDir.appendingPathComponent("size_sub", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        let f1 = subDir.appendingPathComponent("f1.bin")
        let f2 = subDir.appendingPathComponent("f2.bin")
        try Data(repeating: 1, count: 5000).write(to: f1)
        try Data(repeating: 2, count: 3000).write(to: f2)

        let apparent = FastDirectorySizeCalculator.calculateSize(at: subDir.path, apparentSize: true)
        XCTAssertGreaterThanOrEqual(apparent, 8000)

        let kb = FastDirectorySizeCalculator.calculateSizeKB(at: subDir.path)
        XCTAssertGreaterThan(kb, 0)
    }

    // MARK: - FastLockfile Tests

    func testFastLockfileExclusiveAndCommit() throws {
        let targetFile = tempDir.appendingPathComponent("state.json")
        let lock1 = try FastLockfile(targetPath: targetFile.path, timeoutMs: 0)

        // Second lock attempt while lock1 is held should fail immediately with lockBusy
        XCTAssertThrowsError(try FastLockfile(targetPath: targetFile.path, timeoutMs: 0)) { error in
            guard let lockErr = error as? FastLockfile.LockError,
                  case .lockBusy = lockErr else {
                XCTFail("Expected lockBusy, got: \(error)")
                return
            }
        }

        // Commit lock1
        let payload = Data("{\"state\":\"active\"}".utf8)
        try lock1.commit(data: payload)

        // After commit, target file should exist with payload and .lock file should be gone
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetFile.path + ".lock"))
        let readData = try Data(contentsOf: targetFile)
        XCTAssertEqual(readData, payload)

        // Now another lock can be acquired
        let lock2 = try FastLockfile(targetPath: targetFile.path, timeoutMs: 100)
        lock2.rollback()
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetFile.path + ".lock"))
    }

    func testFastLockfileRollbackOnDeinit() throws {
        let targetFile = tempDir.appendingPathComponent("rollback_target.json")
        let originalData = Data("original".utf8)
        try originalData.write(to: targetFile)

        do {
            let lock = try FastLockfile(targetPath: targetFile.path, timeoutMs: 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path + ".lock"))
            // Do not commit, let lock fall out of scope
            _ = lock
        }

        // Lock deinit should automatically rollback (unlink .lock)
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetFile.path + ".lock"))
        // Target file must remain 100% untouched
        let restoredData = try Data(contentsOf: targetFile)
        XCTAssertEqual(restoredData, originalData)
    }

    func testFastLockfileWithLockHelper() throws {
        let targetFile = tempDir.appendingPathComponent("with_lock.json")

        let result = try FastLockfile.withLock(at: targetFile.path) { _ in
            let data = Data("locked content".utf8)
            return (data, 42)
        }

        XCTAssertEqual(result, 42)
        XCTAssertTrue(FileManager.default.fileExists(atPath: targetFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: targetFile.path + ".lock"))
        let content = try String(contentsOf: targetFile, encoding: .utf8)
        XCTAssertEqual(content, "locked content")
    }
}

