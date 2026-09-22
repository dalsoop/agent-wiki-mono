import XCTest
@testable import AppPathsKit

final class SelfHealingDocumentStoreTests: XCTestCase {

    struct SampleState: Codable, Equatable {
        var count: Int
        var message: String
    }

    private var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("selfhealing-tests-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            XCTFail("Failed to create tempDir: \(error)")
        }
    }

    override func tearDown() {
        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            _ = error
        }
        super.tearDown()
    }

    func testMutateTransaction() throws {
        let fileURL = tempDir.appendingPathComponent("state.json")
        let store = SelfHealingDocumentStore<SampleState>(
            url: fileURL,
            default: SampleState(count: 0, message: "init")
        )

        // mutate 트랜잭션 1회차
        try store.mutate { state in
            state.count = 10
            state.message = "first"
        }

        let loaded1 = try store.loadOrSelfHeal()
        XCTAssertEqual(loaded1, SampleState(count: 10, message: "first"))

        // mutate 트랜잭션 2회차
        let returnedResult = try store.mutate { state -> String in
            state.count += 5
            return "done-\(state.count)"
        }

        XCTAssertEqual(returnedResult, "done-15")
        let loaded2 = try store.loadOrSelfHeal()
        XCTAssertEqual(loaded2, SampleState(count: 15, message: "first"))
    }

    func testBoundedQuarantinePruning() throws {
        let fileURL = tempDir.appendingPathComponent("state.json")
        let store = SelfHealingDocumentStore<SampleState>(
            url: fileURL,
            default: SampleState(count: 0, message: "init")
        )

        // 손상된 파일을 생성하고 격리(quarantineCorruptedFile)를 8회 연속 유발
        for i in 1...8 {
            let corruptData = "bad-data-round-\(i)-\(UUID().uuidString)"
            try Data(corruptData.utf8).write(to: fileURL)
            store.quarantineCorruptedFile(at: fileURL)
            // 타임스탬프 중복 방지 및 수정시각 차등을 위해 마이크로초 딜레이
            Thread.sleep(forTimeInterval: 0.002)
        }

        // 디렉터리 내 격리 파일 목록 확인
        let entries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let corruptFiles = entries.filter { $0.hasPrefix("state.json.corrupt.") }

        // Bounded Quarantine 기본값은 5이므로, 최대 5개까지만 유지되어야 함
        XCTAssertEqual(corruptFiles.count, 5, "Bounded quarantine should retain at most 5 files, but found \(corruptFiles.count)")
    }

    func testPruneQuarantinedFilesDirect() throws {
        let fileURL = tempDir.appendingPathComponent("data.json")

        // 6개의 임의 격리 파일 생성
        for i in 1...6 {
            let corruptURL = tempDir.appendingPathComponent("data.json.corrupt.\(1000 + i)")
            try Data("corrupt-\(i)".utf8).write(to: corruptURL)
            Thread.sleep(forTimeInterval: 0.001)
        }

        var entries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        XCTAssertEqual(entries.filter { $0.hasPrefix("data.json.corrupt.") }.count, 6)

        // maxKeep: 3으로 정리 호출
        let removed = SelfHealingDocumentStore<SampleState>.pruneQuarantinedFiles(at: fileURL, maxKeep: 3)
        XCTAssertEqual(removed, 3)

        entries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let remaining = entries.filter { $0.hasPrefix("data.json.corrupt.") }
        XCTAssertEqual(remaining.count, 3)
    }

    func testFailClosedOnUnrecoverableCorruption() throws {
        let fileURL = tempDir.appendingPathComponent("corrupted.json")
        let store = SelfHealingDocumentStore<SampleState>(
            url: fileURL,
            default: SampleState(count: 0, message: "default")
        )

        // 원본 파일은 완전히 깨진 JSON이고 .bak 파일은 없는 상태
        try Data("broken-corrupt-data".utf8).write(to: fileURL)

        XCTAssertTrue(store.isCorruptedAndUnrecoverable())

        // Fail-Closed: mutate는 빈 상태로 덮어쓰지 않고 corruptUnrecoverable 에러를 throw해야 함
        XCTAssertThrowsError(try store.mutate { state in
            state.count = 999
        }) { error in
            guard let storeError = error as? SelfHealingStoreError,
                  case .corruptUnrecoverable = storeError else {
                return XCTFail("Expected corruptUnrecoverable error, got \(error)")
            }
        }

        // 원본 파일이 빈 기본값으로 덮어써지지 않았는지 확인
        let rawData = try Data(contentsOf: fileURL)
        XCTAssertEqual(String(decoding: rawData, as: UTF8.self), "broken-corrupt-data")
    }

    func testSaveGuardsValidBackupWhenSourceCorrupted() throws {
        let fileURL = tempDir.appendingPathComponent("guarded.json")
        let store = SelfHealingDocumentStore<SampleState>(url: fileURL)

        // 1. 정상 상태 저장 (이것이 향후 .bak이 됨)
        let original = SampleState(count: 100, message: "good-backup")
        try store.save(original)

        let next = SampleState(count: 200, message: "next")
        try store.save(next) // 이제 .bak 에는 count 100 이 들어감

        let bakDataBefore = try Data(contentsOf: store.bakURL)
        let bakDecodedBefore = try JSONDecoder().decode(SampleState.self, from: bakDataBefore)
        XCTAssertEqual(bakDecodedBefore, original)

        // 2. 원본 파일을 인위적으로 손상시킴
        try Data("malformed-data".utf8).write(to: fileURL)

        // 3. 새 데이터를 save()할 때, 손상된 원본이 정상이었던 .bak을 덮어써서 파괴하지 않아야 함
        let freshValue = SampleState(count: 300, message: "fresh")
        try store.save(freshValue)

        // 4. 유효한 백업이 여전히 보존되었는지 확인
        let bakDataAfter = try Data(contentsOf: store.bakURL)
        let bakDecodedAfter = try JSONDecoder().decode(SampleState.self, from: bakDataAfter)
        XCTAssertEqual(bakDecodedAfter, original, "Valid backup was overwritten by corrupted source file!")

        // 5. 손상된 원본은 .corrupt 로 격리되었는지 확인
        let entries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        let corruptFiles = entries.filter { $0.hasPrefix("guarded.json.corrupt.") }
        XCTAssertFalse(corruptFiles.isEmpty, "Corrupted source was not quarantined upon save!")
    }
}
