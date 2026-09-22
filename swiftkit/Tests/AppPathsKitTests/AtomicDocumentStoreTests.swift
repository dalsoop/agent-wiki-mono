import XCTest
@testable import AppPathsKit

final class AtomicDocumentStoreTests: XCTestCase {
    private var tempDirectory: URL = FileManager.default.temporaryDirectory

    override func setUpWithError() throws {
        try super.setUpWithError()
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("AtomicDocumentStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirectory = dir
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    struct TestItem: Codable, Equatable {
        var id: String
        var counter: Int
        var tags: [String]
    }

    // MARK: - 1. 정상 읽기/쓰기 라운드트립 검증

    func testSaveAndLoadRoundTrip() throws {
        let fileURL = tempDirectory.appendingPathComponent("item.json")
        let item = TestItem(id: "item-1", counter: 42, tags: ["swift", "atomic"])

        try AtomicDocumentStore.save(item, to: fileURL)
        let loaded = try AtomicDocumentStore.load(as: TestItem.self, from: fileURL)

        XCTAssertEqual(loaded, item)
    }

    func testFileNotFoundThrows() throws {
        let fileURL = tempDirectory.appendingPathComponent("missing.json")
        XCTAssertThrowsError(try AtomicDocumentStore.load(as: TestItem.self, from: fileURL)) { error in
            guard case AtomicDocumentStoreError.fileNotFound(let url) = error else {
                XCTFail("Expected fileNotFound error, got: \(error)")
                return
            }
            XCTAssertEqual(url.standardizedFileURL.path, fileURL.standardizedFileURL.path)
        }
    }

    // MARK: - 2. Mutate 안전 트랜잭션 검증

    func testMutateTransaction() throws {
        let fileURL = tempDirectory.appendingPathComponent("mutate.json")
        let initial = TestItem(id: "mut-1", counter: 10, tags: ["a"])
        try AtomicDocumentStore.save(initial, to: fileURL)

        try AtomicDocumentStore.mutate(at: fileURL) { (item: inout TestItem) in
            item.counter += 5
            item.tags.append("b")
        }

        let updated = try AtomicDocumentStore.load(as: TestItem.self, from: fileURL)
        XCTAssertEqual(updated.counter, 15)
        XCTAssertEqual(updated.tags, ["a", "b"])
    }

    func testMutateWithDefaultOnNewFile() throws {
        let fileURL = tempDirectory.appendingPathComponent("mutate-new.json")
        let defaultVal = TestItem(id: "new-1", counter: 0, tags: [])

        try AtomicDocumentStore.mutate(at: fileURL, default: defaultVal) { (item: inout TestItem) in
            item.counter += 1
            item.tags.append("created")
        }

        let loaded = try AtomicDocumentStore.load(as: TestItem.self, from: fileURL)
        XCTAssertEqual(loaded.counter, 1)
        XCTAssertEqual(loaded.tags, ["created"])
    }

    // MARK: - 3. 100% Fail-Closed 동작 검증

    func testFailClosedOnCorruptDataPreservesOriginalFile() throws {
        let fileURL = tempDirectory.appendingPathComponent("corrupt.json")
        let corruptContent = "{\"id\": \"corrupt-1\", \"counter\": \"NOT_AN_INT\"}" // 타입 불일치 손상
        let originalBytes = try XCTUnwrap(corruptContent.data(using: .utf8))
        try originalBytes.write(to: fileURL)

        // 1. load 시 결코 조용히 기본값을 반환하거나 조용히 넘기지 않고 에러를 throw해야 함
        XCTAssertThrowsError(try AtomicDocumentStore.load(as: TestItem.self, from: fileURL)) { error in
            guard case AtomicDocumentStoreError.decodingFailed(let url, _) = error else {
                XCTFail("Expected decodingFailed, got: \(error)")
                return
            }
            XCTAssertEqual(url.standardizedFileURL.path, fileURL.standardizedFileURL.path)
        }

        // 2. 디스크의 원본 파일이 100% 바이트 단위로 보존되어 있어야 함 (삭제/빈값/격리 금지)
        let diskBytes = try Data(contentsOf: fileURL)
        XCTAssertEqual(diskBytes, originalBytes, "Fail-Closed: 원본 파일 바이트가 손상 없이 디스크에 그대로 보존되어야 합니다.")

        // 3. 임의의 격리 파일이나 .bak 백업 파일이 생겨나지 않아야 함
        let siblingFiles = try FileManager.default.contentsOfDirectory(atPath: tempDirectory.path)
        XCTAssertEqual(siblingFiles, ["corrupt.json"], "Fail-Closed: 임의 격리 파일이 생성되지 않아야 합니다.")
    }

    func testFailClosedMutateAbortsOnCorruptFileWithoutOverwriting() throws {
        let fileURL = tempDirectory.appendingPathComponent("corrupt-mutate.json")
        let corruptContent = "{ broken json content ..."
        let originalBytes = try XCTUnwrap(corruptContent.data(using: .utf8))
        try originalBytes.write(to: fileURL)

        // 파일이 존재하는데 손상된 경우 mutate(at:default:)는 기본값으로 덮어쓰지 않고 throw해야 함
        XCTAssertThrowsError(
            try AtomicDocumentStore.mutate(at: fileURL, default: TestItem(id: "fallback", counter: 0, tags: [])) { (item: inout TestItem) in
                item.counter += 999
            }
        )

        // 디스크의 원본 바이트가 그대로 유지되어야 함
        let diskBytes = try Data(contentsOf: fileURL)
        XCTAssertEqual(diskBytes, originalBytes, "Fail-Closed: 손상 파일에 대한 mutate 시도 시 결코 덮어쓰지 않고 원본을 보존해야 합니다.")
    }

    // MARK: - 4. 동시성 (Concurrency) 안전성 검증

    func testConcurrentMutations() throws {
        let fileURL = tempDirectory.appendingPathComponent("concurrent.json")
        let initial = TestItem(id: "concurrent", counter: 0, tags: [])
        try AtomicDocumentStore.save(initial, to: fileURL)

        let iterations = 20
        let group = DispatchGroup()
        let queue = DispatchQueue(label: "AtomicDocumentStoreTests.concurrent", attributes: .concurrent)

        for _ in 0..<iterations {
            group.enter()
            queue.async {
                do {
                    try AtomicDocumentStore.mutate(at: fileURL) { (item: inout TestItem) in
                        item.counter += 1
                    }
                } catch {
                    XCTFail("Concurrent mutate failed: \(error)")
                }
                group.leave()
            }
        }

        group.wait()

        let finalItem = try AtomicDocumentStore.load(as: TestItem.self, from: fileURL)
        XCTAssertEqual(finalItem.counter, iterations, "동시성: 모든 mutate 트랜잭션이 누락 없이 배타적으로 실행되어야 합니다.")
    }

    // MARK: - 5. Bound Store 검증

    func testBoundStore() throws {
        let fileURL = tempDirectory.appendingPathComponent("bound.json")
        let defaultItem = TestItem(id: "bound-def", counter: 100, tags: ["bound"])
        let bound: AtomicDocumentStore.Bound<TestItem> = AtomicDocumentStore.bound(to: fileURL, default: defaultItem)

        // 파일이 없을 때 load: 기본값 반환
        let initial = try bound.load()
        XCTAssertEqual(initial, defaultItem)

        // mutate
        try bound.mutate { item in
            item.counter += 50
        }

        let reloaded = try bound.load()
        XCTAssertEqual(reloaded.counter, 150)
    }
}
