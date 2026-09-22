import XCTest
import CryptoKit
@testable import ReleaseReceiptKit

final class ReceiptVerifierTests: XCTestCase {
    var tempDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptVerifierTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    func testVerifySuccess() throws {
        let content = "Hello, world! Release artifact sample content."
        let data = Data(content.utf8)
        let fileURL = tempDirectory.appendingPathComponent("release-1.0.0.zip")
        try data.write(to: fileURL)

        let digest = SHA256.hash(data: data)
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

        let receipt = ReleaseReceipt(
            appSlug: "test-app",
            bundleID: "com.test.app",
            version: "1.0.0",
            artifact: ArtifactReceipt(
                filename: "release-1.0.0.zip",
                sha256: sha256Hex,
                sizeBytes: Int64(data.count),
                contentType: "application/zip"
            ),
            notary: NotaryReceipt(submissionID: "sub-1", notarizedAt: Date())
        )

        let result = try ReceiptVerifier.verify(receipt: receipt, artifactURL: fileURL)
        XCTAssertTrue(result.isValid)
        XCTAssertEqual(result.computedSHA256, sha256Hex)
        XCTAssertEqual(result.computedSizeBytes, Int64(data.count))
        XCTAssertTrue(result.errors.isEmpty)
    }

    func testVerifyFileNotFound() throws {
        let missingURL = tempDirectory.appendingPathComponent("missing.zip")
        let receipt = ReleaseReceipt(
            appSlug: "test-app",
            bundleID: "com.test.app",
            version: "1.0.0",
            artifact: ArtifactReceipt(
                filename: "missing.zip",
                sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                sizeBytes: 100,
                contentType: "application/zip"
            ),
            notary: NotaryReceipt(submissionID: "sub-1", notarizedAt: Date())
        )

        XCTAssertThrowsError(try ReceiptVerifier.verify(receipt: receipt, artifactURL: missingURL)) { error in
            guard case ReceiptVerificationError.fileNotFound(let url) = error else {
                XCTFail("Expected fileNotFound error, got: \(error)")
                return
            }
            XCTAssertEqual(url.standardizedFileURL.path, missingURL.standardizedFileURL.path)
        }
    }

    func testVerifySizeMismatch() throws {
        let content = "Small content"
        let data = Data(content.utf8)
        let fileURL = tempDirectory.appendingPathComponent("size-mismatch.zip")
        try data.write(to: fileURL)

        let digest = SHA256.hash(data: data)
        let sha256Hex = digest.map { String(format: "%02x", $0) }.joined()

        let receipt = ReleaseReceipt(
            appSlug: "test-app",
            bundleID: "com.test.app",
            version: "1.0.0",
            artifact: ArtifactReceipt(
                filename: "size-mismatch.zip",
                sha256: sha256Hex,
                sizeBytes: Int64(data.count) + 50, // Intentional mismatch
                contentType: "application/zip"
            ),
            notary: NotaryReceipt(submissionID: "sub-1", notarizedAt: Date())
        )

        XCTAssertThrowsError(try ReceiptVerifier.verify(receipt: receipt, artifactURL: fileURL)) { error in
            guard case ReceiptVerificationError.sizeMismatch(let expected, let actual) = error else {
                XCTFail("Expected sizeMismatch error, got: \(error)")
                return
            }
            XCTAssertEqual(expected, Int64(data.count) + 50)
            XCTAssertEqual(actual, Int64(data.count))
        }
    }

    func testVerifyHashMismatch() throws {
        let content = "Actual file content"
        let data = Data(content.utf8)
        let fileURL = tempDirectory.appendingPathComponent("hash-mismatch.zip")
        try data.write(to: fileURL)

        let forgedHash = "0000000000000000000000000000000000000000000000000000000000000000"

        let receipt = ReleaseReceipt(
            appSlug: "test-app",
            bundleID: "com.test.app",
            version: "1.0.0",
            artifact: ArtifactReceipt(
                filename: "hash-mismatch.zip",
                sha256: forgedHash,
                sizeBytes: Int64(data.count),
                contentType: "application/zip"
            ),
            notary: NotaryReceipt(submissionID: "sub-1", notarizedAt: Date())
        )

        XCTAssertThrowsError(try ReceiptVerifier.verify(receipt: receipt, artifactURL: fileURL)) { error in
            guard case ReceiptVerificationError.hashMismatch(let expected, _) = error else {
                XCTFail("Expected hashMismatch error, got: \(error)")
                return
            }
            XCTAssertEqual(expected, forgedHash)
        }
    }

    func testVerifyInvalidHashFormat() throws {
        let content = "Some content"
        let data = Data(content.utf8)
        let fileURL = tempDirectory.appendingPathComponent("invalid-hash.zip")
        try data.write(to: fileURL)

        let receipt = ReleaseReceipt(
            appSlug: "test-app",
            bundleID: "com.test.app",
            version: "1.0.0",
            artifact: ArtifactReceipt(
                filename: "invalid-hash.zip",
                sha256: "not-a-valid-sha256",
                sizeBytes: Int64(data.count),
                contentType: "application/zip"
            ),
            notary: NotaryReceipt(submissionID: "sub-1", notarizedAt: Date())
        )

        XCTAssertThrowsError(try ReceiptVerifier.verify(receipt: receipt, artifactURL: fileURL)) { error in
            guard case ReceiptVerificationError.invalidReceiptHashFormat(let hash) = error else {
                XCTFail("Expected invalidReceiptHashFormat error, got: \(error)")
                return
            }
            XCTAssertEqual(hash, "not-a-valid-sha256")
        }
    }

    func testNonStrictModeCollectsErrors() throws {
        let content = "File content"
        let data = Data(content.utf8)
        let fileURL = tempDirectory.appendingPathComponent("non-strict.zip")
        try data.write(to: fileURL)

        let receipt = ReleaseReceipt(
            appSlug: "test-app",
            bundleID: "com.test.app",
            version: "1.0.0",
            artifact: ArtifactReceipt(
                filename: "non-strict.zip",
                sha256: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
                sizeBytes: Int64(data.count) + 100, // Size mismatch
                contentType: "application/zip"
            ),
            notary: NotaryReceipt(submissionID: "sub-1", notarizedAt: Date())
        )

        let verifier = ReceiptVerifier()
        let result = try verifier.verify(receipt: receipt, artifactURL: fileURL, strict: false)

        XCTAssertFalse(result.isValid)
        XCTAssertEqual(result.errors.count, 2) // Size mismatch + Hash mismatch
    }

    func testCaseInsensitiveHashComparison() throws {
        let content = "Case insensitive test content"
        let data = Data(content.utf8)
        let fileURL = tempDirectory.appendingPathComponent("case-test.zip")
        try data.write(to: fileURL)

        let digest = SHA256.hash(data: data)
        let upperHex = digest.map { String(format: "%02X", $0) }.joined()

        let receipt = ReleaseReceipt(
            appSlug: "test-app",
            bundleID: "com.test.app",
            version: "1.0.0",
            artifact: ArtifactReceipt(
                filename: "case-test.zip",
                sha256: upperHex, // Uppercase in receipt
                sizeBytes: Int64(data.count),
                contentType: "application/zip"
            ),
            notary: NotaryReceipt(submissionID: "sub-1", notarizedAt: Date())
        )

        let result = try ReceiptVerifier.verify(receipt: receipt, artifactURL: fileURL)
        XCTAssertTrue(result.isValid)
    }
}
