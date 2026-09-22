import XCTest
import CryptoKit
@testable import ContentAddressedAssetKit

final class AssetStoreTests: XCTestCase {
    private var tempDirectory: URL?
    private var objectsDirectory: URL?
    private var store: AssetStore?

    override func setUpWithError() throws {
        try super.setUpWithError()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContentAddressedAssetKitTests-\(UUID().uuidString)")
        let objects = temp.appendingPathComponent("objects")
        try FileManager.default.createDirectory(at: objects, withIntermediateDirectories: true)
        tempDirectory = temp
        objectsDirectory = objects
        store = AssetStore(rootDirectory: objects)
    }

    override func tearDownWithError() throws {
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        objectsDirectory = nil
        store = nil
        try super.tearDownWithError()
    }

    func testStoreFileGeneratesCorrectHashAndSidecar() throws {
        guard let tempDirectory = tempDirectory,
              let objectsDirectory = objectsDirectory,
              let store = store else {
            XCTFail("AssetStore test fixture not initialized")
            return
        }

        guard let testContent = "Hello Content-Addressed Storage!".data(using: .utf8) else {
            XCTFail("Failed to encode test string")
            return
        }

        let sampleFileURL = tempDirectory.appendingPathComponent("sample.txt")
        try testContent.write(to: sampleFileURL)

        let expectedDigest = SHA256.hash(data: testContent)
        let expectedHash = expectedDigest.map { String(format: "%02x", $0) }.joined()

        let media = MediaMetadata(durationSeconds: 12.5, peer: "peer-node-1", extra: ["tag": "test"])
        let asset = try store.store(fileURL: sampleFileURL, media: media)

        XCTAssertEqual(asset.hash, expectedHash)
        XCTAssertEqual(asset.sizeBytes, Int64(testContent.count))
        XCTAssertEqual(asset.originalName, "sample.txt")
        XCTAssertEqual(asset.media, media)
        XCTAssertEqual(asset.id, expectedHash)

        // Verify stored asset file
        let storedFileURL = objectsDirectory.appendingPathComponent("\(expectedHash).txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: storedFileURL.path))

        // Verify sidecar JSON file
        let sidecarURL = objectsDirectory.appendingPathComponent("\(expectedHash).json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarURL.path))

        // Verify lookup and exists
        XCTAssertTrue(store.exists(hash: expectedHash))
        let lookedUpURL = store.lookup(hash: expectedHash)
        XCTAssertEqual(lookedUpURL?.standardizedFileURL, storedFileURL.standardizedFileURL)

        // Verify metadata retrieval
        let retrievedMetadata = try store.metadata(hash: expectedHash)
        XCTAssertEqual(retrievedMetadata.hash, asset.hash)
        XCTAssertEqual(retrievedMetadata.sizeBytes, asset.sizeBytes)
        XCTAssertEqual(retrievedMetadata.originalName, asset.originalName)
        XCTAssertEqual(retrievedMetadata.media, asset.media)
    }

    func testStoreIdempotencyDoesNotOverwrite() throws {
        guard let tempDirectory = tempDirectory,
              let store = store else {
            XCTFail("AssetStore test fixture not initialized")
            return
        }

        guard let testContent = "Idempotent Asset Data".data(using: .utf8) else {
            XCTFail("Failed to encode test string")
            return
        }

        let sampleFileURL = tempDirectory.appendingPathComponent("photo.png")
        try testContent.write(to: sampleFileURL)

        let firstAsset = try store.store(fileURL: sampleFileURL)
        let firstCreatedAt = firstAsset.createdAt

        // Wait a slight amount to ensure timestamps would differ if recreated
        Thread.sleep(forTimeInterval: 0.05)

        // Store same file again
        let secondAsset = try store.store(fileURL: sampleFileURL)

        XCTAssertEqual(firstAsset.hash, secondAsset.hash)
        XCTAssertEqual(firstAsset, secondAsset)
        // Verify original object was returned without overwriting createdAt
        XCTAssertEqual(firstCreatedAt.timeIntervalSince1970, secondAsset.createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testLookupAndMetadataForNonExistentHash() throws {
        guard let store = store else {
            XCTFail("AssetStore test fixture not initialized")
            return
        }

        let dummyHash = String(repeating: "a", count: 64)
        XCTAssertFalse(store.exists(hash: dummyHash))
        XCTAssertNil(store.lookup(hash: dummyHash))

        XCTAssertThrowsError(try store.metadata(hash: dummyHash)) { error in
            guard let storeError = error as? AssetStoreError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            XCTAssertEqual(storeError, .metadataNotFound(dummyHash))
        }
    }
}
