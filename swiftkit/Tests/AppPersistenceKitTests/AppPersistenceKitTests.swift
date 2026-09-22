import XCTest
import Foundation
@testable import AppPersistenceKit

final class AppPersistenceKitTests: XCTestCase {
    struct SampleModel: Codable, Equatable {
        let id: String
        let count: Int
        let createdAt: Date
    }

    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppPersistenceTests-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true) } catch { _ = error }
    }

    override func tearDown() {
        if let dir = tempDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        super.tearDown()
    }

    func testSaveAndLoadSuccessfully() throws {
        let file = tempDirectory.appendingPathComponent("sample.json")
        let date = Date(timeIntervalSince1970: 1700000000)
        let sample = SampleModel(id: "alpha", count: 42, createdAt: date)

        let saved = try AppPersistence.save(sample, to: file)
        XCTAssertTrue(saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        let loaded: SampleModel = try AppPersistence.load(from: file)
        XCTAssertEqual(loaded, sample)

        // Write identical data -> skipped by onlyIfChanged
        let savedAgain = try AppPersistence.save(sample, to: file, onlyIfChanged: true)
        XCTAssertFalse(savedAgain)
    }

    func testLoadNonExistentThrowsOrReturnsFallback() throws {
        let file = tempDirectory.appendingPathComponent("missing.json")

        // Without fallback -> throws fileNotFound
        XCTAssertThrowsError(try AppPersistence.load(from: file, as: SampleModel.self)) { error in
            guard case AppPersistenceError.fileNotFound = error else {
                XCTFail("Expected AppPersistenceError.fileNotFound, got \(error)")
                return
            }
        }

        // With fallback -> returns fallback
        let fallback = SampleModel(id: "default", count: 0, createdAt: Date())
        let loaded = try AppPersistence.load(from: file, as: SampleModel.self, default: fallback)
        XCTAssertEqual(loaded, fallback)

        // loadIfExists -> returns nil
        let loadedIfExists: SampleModel? = try AppPersistence.loadIfExists(from: file)
        XCTAssertNil(loadedIfExists)
    }

    func testCorruptedJSONNeverSwallowed() throws {
        let file = tempDirectory.appendingPathComponent("corrupted.json")
        let badContent = "{ invalid_json_here: true, missing_quotes }"
        try badContent.write(to: file, atomically: true, encoding: .utf8)

        // Even with fallback, corrupted file must THROW and NOT silently return fallback!
        let fallback = SampleModel(id: "fallback", count: 0, createdAt: Date())
        XCTAssertThrowsError(try AppPersistence.load(from: file, as: SampleModel.self, default: fallback)) { error in
            guard case AppPersistenceError.decodeFailed(let path, let typeName, _) = error else {
                XCTFail("Expected AppPersistenceError.decodeFailed, got \(error)")
                return
            }
            XCTAssertEqual(path, file.path)
            XCTAssertTrue(typeName.contains("SampleModel"))
        }

        // loadIfExists also MUST throw on corruption, never return nil
        XCTAssertThrowsError(try AppPersistence.loadIfExists(from: file, as: SampleModel.self)) { error in
            guard case AppPersistenceError.decodeFailed = error else {
                XCTFail("Expected decodeFailed, got \(error)")
                return
            }
        }
    }

    func testSafeJSONAliasAndInMemoryDecode() throws {
        let sample = SampleModel(id: "memory", count: 7, createdAt: Date(timeIntervalSince1970: 1700000000))
        let data = try SafeJSON.encode(sample)
        XCTAssertFalse(data.isEmpty)

        let decoded: SampleModel = try SafeJSON.decode(SampleModel.self, from: data)
        XCTAssertEqual(decoded, sample)

        let badData = "broken json".data(using: .utf8)!
        XCTAssertThrowsError(try SafeJSON.decode(SampleModel.self, from: badData)) { error in
            guard case AppPersistenceError.decodeFailed = error else {
                XCTFail("Expected decodeFailed, got \(error)")
                return
            }
        }
    }
}
