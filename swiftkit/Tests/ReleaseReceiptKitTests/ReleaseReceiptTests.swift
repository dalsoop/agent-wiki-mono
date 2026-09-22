import XCTest
@testable import ReleaseReceiptKit

final class ReleaseReceiptTests: XCTestCase {
    func testReceiptInitializationAndDefaults() {
        let artifact = ArtifactReceipt(
            filename: "sample-app-1.0.0.zip",
            sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            sizeBytes: 1024,
            contentType: "application/zip"
        )
        let notary = NotaryReceipt(
            submissionID: "2efe8182-1234-4567-89ab-cdef01234567",
            notarizedAt: Date(timeIntervalSince1970: 1700000000),
            teamID: "TEAM12345"
        )
        let sparkle = SparkleReceipt(ed25519Signature: "sig1234567890abcdef")

        let receipt = ReleaseReceipt(
            appSlug: "my-app",
            bundleID: "com.example.myapp",
            version: "1.0.0",
            buildNumber: 42,
            artifact: artifact,
            notary: notary,
            sparkle: sparkle
        )

        XCTAssertEqual(receipt.schema, "https://gujo.ai/schemas/release-receipt-v1.json")
        XCTAssertEqual(receipt.appSlug, "my-app")
        XCTAssertEqual(receipt.bundleID, "com.example.myapp")
        XCTAssertEqual(receipt.version, "1.0.0")
        XCTAssertEqual(receipt.buildNumber, 42)
        XCTAssertEqual(receipt.artifact.filename, "sample-app-1.0.0.zip")
        XCTAssertEqual(receipt.artifact.sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(receipt.notary.teamID, "TEAM12345")
        XCTAssertEqual(receipt.sparkle?.ed25519Signature, "sig1234567890abcdef")
    }

    func testCodableRoundTrip() throws {
        let fixedDate = Date(timeIntervalSince1970: 1715000000)
        let artifact = ArtifactReceipt(
            filename: "gujo-cloud-apps.dmg",
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            sizeBytes: 52428800,
            contentType: "application/x-apple-diskimage"
        )
        let notary = NotaryReceipt(
            submissionID: "sub-123",
            notarizedAt: fixedDate,
            teamID: "APPLE123"
        )
        let receipt = ReleaseReceipt(
            appSlug: "gujo-cloud-apps",
            bundleID: "ai.gujo.apps",
            version: "2.1.0",
            buildNumber: 105,
            artifact: artifact,
            notary: notary,
            sparkle: nil,
            createdAt: fixedDate
        )

        let data = try receipt.toJSONData()
        let decoded = try ReleaseReceipt.from(jsonData: data)

        XCTAssertEqual(receipt.schema, decoded.schema)
        XCTAssertEqual(receipt.appSlug, decoded.appSlug)
        XCTAssertEqual(receipt.bundleID, decoded.bundleID)
        XCTAssertEqual(receipt.version, decoded.version)
        XCTAssertEqual(receipt.buildNumber, decoded.buildNumber)
        XCTAssertEqual(receipt.artifact, decoded.artifact)
        XCTAssertEqual(receipt.notary.submissionID, decoded.notary.submissionID)
        XCTAssertEqual(receipt.notary.teamID, decoded.notary.teamID)
        XCTAssertNil(decoded.sparkle)
        XCTAssertEqual(receipt.notary.notarizedAt.timeIntervalSince1970, decoded.notary.notarizedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(receipt.createdAt.timeIntervalSince1970, decoded.createdAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDecodingWithDollarSchemaAndStandardSchema() throws {
        let jsonWithDollar = """
        {
            "$schema": "https://custom.org/schema.json",
            "appSlug": "test-app",
            "bundleID": "com.test.app",
            "version": "1.0.0",
            "artifact": {
                "filename": "test.zip",
                "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "sizeBytes": 100,
                "contentType": "application/zip"
            },
            "notary": {
                "submissionID": "sub-1",
                "notarizedAt": "2026-09-01T12:00:00Z"
            },
            "createdAt": "2026-09-01T12:00:00Z"
        }
        """

        let receipt = try ReleaseReceipt.from(jsonString: jsonWithDollar)
        XCTAssertEqual(receipt.schema, "https://custom.org/schema.json")
        XCTAssertEqual(receipt.appSlug, "test-app")
    }

    func testArtifactSHA256Validation() {
        let validArtifact = ArtifactReceipt(
            filename: "file.zip",
            sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            sizeBytes: 10,
            contentType: "application/zip"
        )
        XCTAssertTrue(validArtifact.isValidSHA256)

        let shortHash = ArtifactReceipt(
            filename: "file.zip",
            sha256: "ba7816bf",
            sizeBytes: 10,
            contentType: "application/zip"
        )
        XCTAssertFalse(shortHash.isValidSHA256)

        let nonHexHash = ArtifactReceipt(
            filename: "file.zip",
            sha256: "ga7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015az",
            sizeBytes: 10,
            contentType: "application/zip"
        )
        XCTAssertFalse(nonHexHash.isValidSHA256)
    }
}
