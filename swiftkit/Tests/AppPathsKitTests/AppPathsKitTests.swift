import XCTest
@testable import AppPathsKit

final class AppPathsKitTests: XCTestCase {
    func testApplicationSupportRoot() {
        let paths = AppPaths.applicationSupport("MyApp")
        XCTAssertTrue(paths.root.path.hasSuffix("Application Support/MyApp"))
        XCTAssertEqual(paths.stateFile.lastPathComponent, "state.json")
        XCTAssertEqual(paths.settingsFile.lastPathComponent, "settings.json")
        XCTAssertEqual(paths.sqliteFile.lastPathComponent, "app.sqlite")
    }

    func testHomeDotDir() {
        let paths = AppPaths.homeDotDir("myapp")
        XCTAssertEqual(paths.root.lastPathComponent, ".myapp")
    }

    struct Model: Codable, Equatable { var count: Int; var name: String }

    func testStoreRoundTripAndDefault() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apppathskit-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
        let store = JSONStateStore<Model>(url: tmp)

        // 파일 없음 → 기본값.
        XCTAssertEqual(store.load(default: Model(count: 0, name: "d")), Model(count: 0, name: "d"))
        XCTAssertNil(try store.loadIfPresent())

        // save → load 라운드트립.
        let value = Model(count: 7, name: "x")
        try store.save(value)
        XCTAssertEqual(store.load(default: Model(count: 0, name: "d")), value)
        XCTAssertEqual(try store.loadIfPresent(), value)

        try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent())
    }

    struct Revisioned: RevisionedJSON, Equatable {
        var revision: UInt64
        var name: String
        init() {
            revision = 0
            name = ""
        }
        init(revision: UInt64, name: String) {
            self.revision = revision
            self.name = name
        }
    }

    func testLockedRevisionRoundTripAndConflict() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lockedjson-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tmp)
            try? FileManager.default.removeItem(at: tmp.appendingPathExtension("lock"))
        }
        let store = LockedRevisionJSONStore<Revisioned>(url: tmp, default: Revisioned())
        var first = Revisioned(revision: 0, name: "a")
        try store.save(&first)
        XCTAssertEqual(first.revision, 1)
        XCTAssertEqual(try store.load().name, "a")

        var stale = try store.load()
        var next = try store.load()
        next.name = "b"
        try store.save(&next)
        stale.name = "stale"
        XCTAssertThrowsError(try store.save(&stale)) { error in
            guard case LockedJSONStoreError.conflict = error else {
                return XCTFail("expected conflict, got \(error)")
            }
        }
        XCTAssertEqual(try store.load().name, "b")
    }

    func testLockedRevisionCorruptIsNeverEmpty() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("lockedjson-bad-\(UUID().uuidString).json")
        defer {
            try? FileManager.default.removeItem(at: tmp)
            try? FileManager.default.removeItem(at: tmp.appendingPathExtension("lock"))
        }
        try Data("not-json".utf8).write(to: tmp)
        XCTAssertThrowsError(try LockedRevisionJSONStore<Revisioned>(url: tmp, default: Revisioned()).load())
    }

    func testDurableLayoutBundleIDAndSqlite() throws {
        XCTAssertEqual(DurableAppLayout.bundleID(slug: "memo-vault"), "net.ranode.memo-vault")
        XCTAssertEqual(DurableAppLayout.bundleID(slug: "net.ranode.memo-vault"), "net.ranode.memo-vault")
        let home = URL(fileURLWithPath: "/Users/x")
        let sqlite = DurableAppLayout.sqliteURL(slug: "memo-vault", home: home)
        XCTAssertEqual(
            sqlite.path,
            "/Users/x/Library/Application Support/net.ranode.memo-vault/app.sqlite"
        )
        XCTAssertEqual(
            DurableAppLayout.tildePath(sqlite, home: home),
            "~/Library/Application Support/net.ranode.memo-vault/app.sqlite"
        )
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("app.sqlite")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }
        try DurableAppLayout.ensureDatabase(at: tmp)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmp.path))
    }

    func testIso8601DateRoundTrip() throws {
        struct Dated: Codable, Equatable { var when: Date }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apppathskit-iso-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("state.json")
        defer { try? FileManager.default.removeItem(at: tmp.deletingLastPathComponent()) }
        let store = JSONStateStore<Dated>.iso8601(url: tmp)
        let value = Dated(when: Date(timeIntervalSince1970: 1_700_000_000))
        try store.save(value)
        XCTAssertEqual(try store.loadIfPresent(), value)
        let raw = try String(contentsOf: tmp, encoding: .utf8)
        XCTAssertTrue(raw.contains("2023-"))
    }

    func testCorruptFileQuarantineOnLoad() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apppathskit-corrupt-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("state.json")
        let corruptContent = "not-json"
        try Data(corruptContent.utf8).write(to: fileURL)

        let store = JSONStateStore<Model>(url: fileURL)
        let fallback = Model(count: 99, name: "fallback")

        // load(default:) 호출 시 손상 파일이 격리되고 fallback이 반환되어야 함.
        let loaded = store.load(default: fallback)
        XCTAssertEqual(loaded, fallback)

        // .corrupt. 파일이 생성되었는지 확인
        let entries = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        let corruptFiles = entries.filter { $0.contains(".corrupt.") }
        XCTAssertEqual(corruptFiles.count, 1)

        // 격리된 파일의 내용이 손상된 원본 데이터와 일치하는지 확인
        let quarantinedURL = tmpDir.appendingPathComponent(corruptFiles[0])
        let quarantinedContent = try String(contentsOf: quarantinedURL, encoding: .utf8)
        XCTAssertEqual(quarantinedContent, corruptContent)

        // backupCorrupt: false 설정 시 격리 파일이 추가 생성되지 않는지 확인
        let loadedWithoutBackup = store.load(default: fallback, backupCorrupt: false)
        XCTAssertEqual(loadedWithoutBackup, fallback)
        let entriesAfter = try FileManager.default.contentsOfDirectory(atPath: tmpDir.path)
        XCTAssertEqual(entriesAfter.filter { $0.contains(".corrupt.") }.count, 1)
    }

    func testLoadStrict() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apppathskit-strict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("state.json")
        let store = JSONStateStore<Model>(url: fileURL)

        // 1. 파일이 없을 때 throw
        XCTAssertThrowsError(try store.loadStrict()) { error in
            guard let storeError = error as? JSONStateStoreError,
                  case .fileNotFound(let url) = storeError else {
                return XCTFail("Expected JSONStateStoreError.fileNotFound, got \(error)")
            }
            XCTAssertEqual(url, fileURL)
        }

        // 2. 파일이 손상되었을 때 ("not-json") throw
        try Data("not-json".utf8).write(to: fileURL)
        XCTAssertThrowsError(try store.loadStrict())

        // 3. 정상 파일일 때 정상 반환
        let expected = Model(count: 42, name: "valid")
        try store.save(expected)
        let loaded = try store.loadStrict()
        XCTAssertEqual(loaded, expected)
    }

    func testQuarantineCorruptedFileHelper() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apppathskit-helper-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let fileURL = tmpDir.appendingPathComponent("bad.json")
        let corruptData = "bad-data-12345"
        try Data(corruptData.utf8).write(to: fileURL)

        let quarantinedURL = quarantineCorruptedFile(at: fileURL)
        XCTAssertNotNil(quarantinedURL)
        guard let dest = quarantinedURL else { return }
        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertTrue(dest.lastPathComponent.contains(".corrupt."))
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), corruptData)

        // 존재하지 않는 파일에 대한 격리 시도 시 nil 반환
        let nonExistentURL = tmpDir.appendingPathComponent("none.json")
        XCTAssertNil(quarantineCorruptedFile(at: nonExistentURL))
    }

    func testSavePreservesSymlink() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("apppathskit-symlink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let targetURL = tmpDir.appendingPathComponent("physical_target.json")
        let initialModel = Model(count: 1, name: "initial")
        let initialStore = JSONStateStore<Model>(url: targetURL)
        try initialStore.save(initialModel)

        let symlinkURL = tmpDir.appendingPathComponent("symlink_pointer.json")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: targetURL)

        // 심링크가 정상 생성되었는지 확인
        let destination = try FileManager.default.destinationOfSymbolicLink(atPath: symlinkURL.path)
        XCTAssertFalse(destination.isEmpty)

        // 심링크 URL을 통해 save() 호출
        let symlinkStore = JSONStateStore<Model>(url: symlinkURL)
        let updatedModel = Model(count: 42, name: "updated_through_symlink")
        try symlinkStore.save(updatedModel)

        // 1. 심링크 노드 자체가 파일로 치환되지 않고 심링크로 유지되었는지 확인 (Symlink Preservation)
        let destinationAfterSave = try? FileManager.default.destinationOfSymbolicLink(atPath: symlinkURL.path)
        XCTAssertNotNil(destinationAfterSave, "Symlink was severed and turned into a regular file!")

        // 2. 물리적 대상 파일에 새 데이터가 원자적으로 저장되었는지 확인
        let loadedFromPhysical = try initialStore.loadStrict()
        XCTAssertEqual(loadedFromPhysical, updatedModel)

        // 3. 심링크를 통한 로드도 최신 데이터를 반환하는지 확인
        let loadedFromSymlink = try symlinkStore.loadStrict()
        XCTAssertEqual(loadedFromSymlink, updatedModel)
    }
}
