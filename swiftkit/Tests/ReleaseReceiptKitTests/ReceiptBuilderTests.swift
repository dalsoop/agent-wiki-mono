import XCTest
@testable import ReleaseReceiptKit

final class ReceiptBuilderTests: XCTestCase {
    var tempDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReceiptBuilderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        try super.tearDownWithError()
    }

    func testBuilderCreatesReceiptSuccessfully() throws {
        let fixedDate = Date(timeIntervalSince1970: 1715000000)
        let receipt = try ReceiptBuilder()
            .setAppSlug("app-demo")
            .setBundleID("ai.gujo.demo")
            .setVersion("1.5.0")
            .setBuildNumber(50)
            .setArtifact(
                filename: "app-demo-1.5.0.zip",
                sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                sizeBytes: 2048,
                contentType: "application/zip"
            )
            .setNotary(submissionID: "sub-99", notarizedAt: fixedDate, teamID: "TEAM1")
            .setSparkle(ed25519Signature: "sig123")
            .setCreatedAt(fixedDate)
            .build()

        XCTAssertEqual(receipt.appSlug, "app-demo")
        XCTAssertEqual(receipt.bundleID, "ai.gujo.demo")
        XCTAssertEqual(receipt.version, "1.5.0")
        XCTAssertEqual(receipt.buildNumber, 50)
        XCTAssertEqual(receipt.artifact.filename, "app-demo-1.5.0.zip")
        XCTAssertEqual(receipt.notary.submissionID, "sub-99")
        XCTAssertEqual(receipt.sparkle?.ed25519Signature, "sig123")
    }

    func testBuilderThrowsOnMissingRequiredFields() {
        // Missing all
        XCTAssertThrowsError(try ReceiptBuilder().build()) { error in
            guard case ReceiptBuilderError.missingRequiredField(let field) = error else {
                XCTFail("Expected missingRequiredField, got: \(error)")
                return
            }
            XCTAssertEqual(field, "appSlug")
        }

        // Missing artifact
        XCTAssertThrowsError(
            try ReceiptBuilder()
                .setAppSlug("app")
                .setBundleID("com.app")
                .setVersion("1.0.0")
                .build()
        ) { error in
            guard case ReceiptBuilderError.missingRequiredField(let field) = error else {
                XCTFail("Expected missingRequiredField, got: \(error)")
                return
            }
            XCTAssertEqual(field, "artifact")
        }
    }

    func testBuilderSetsArtifactFromFile() throws {
        let sampleContent = "Sample artifact binary or archive payload"
        let data = Data(sampleContent.utf8)
        let artifactFile = tempDirectory.appendingPathComponent("sample-1.0.0.zip")
        try data.write(to: artifactFile)

        let receipt = try ReceiptBuilder()
            .setAppSlug("sample-app")
            .setBundleID("com.example.sample")
            .setVersion("1.0.0")
            .setArtifact(from: artifactFile)
            .setNotary(submissionID: "notary-sub-100")
            .build()

        XCTAssertEqual(receipt.artifact.filename, "sample-1.0.0.zip")
        XCTAssertEqual(receipt.artifact.sizeBytes, Int64(data.count))
        XCTAssertEqual(receipt.artifact.contentType, "application/zip")
        XCTAssertTrue(receipt.artifact.isValidSHA256)
    }

    func testBuildAndWriteAtomically() throws {
        let sampleContent = "Atomic write testing payload"
        let data = Data(sampleContent.utf8)
        let artifactFile = tempDirectory.appendingPathComponent("app.dmg")
        try data.write(to: artifactFile)

        let receiptOutputURL = tempDirectory
            .appendingPathComponent("nested")
            .appendingPathComponent("receipt.json")

        let receipt = try ReceiptBuilder()
            .setAppSlug("dmg-app")
            .setBundleID("com.example.dmgapp")
            .setVersion("2.0.0")
            .setArtifact(from: artifactFile)
            .setNotary(submissionID: "sub-200")
            .buildAndWrite(to: receiptOutputURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptOutputURL.path))

        let loadedReceipt = try ReleaseReceipt.from(fileURL: receiptOutputURL)
        XCTAssertEqual(receipt.appSlug, loadedReceipt.appSlug)
        XCTAssertEqual(receipt.bundleID, loadedReceipt.bundleID)
        XCTAssertEqual(receipt.version, loadedReceipt.version)
        XCTAssertEqual(receipt.artifact, loadedReceipt.artifact)
        XCTAssertEqual(receipt.notary.submissionID, loadedReceipt.notary.submissionID)
        XCTAssertEqual(receipt.notary.notarizedAt.timeIntervalSince1970, loadedReceipt.notary.notarizedAt.timeIntervalSince1970, accuracy: 0.005)
        XCTAssertEqual(receipt.createdAt.timeIntervalSince1970, loadedReceipt.createdAt.timeIntervalSince1970, accuracy: 0.005)

        // End-to-end: verify using ReceiptVerifier
        let verifyResult = try ReceiptVerifier.verify(receipt: loadedReceipt, artifactURL: artifactFile)
        XCTAssertTrue(verifyResult.isValid)
    }

    func testStaticCreateHelper() throws {
        let content = "Factory test content"
        let data = Data(content.utf8)
        let artifactFile = tempDirectory.appendingPathComponent("factory.pkg")
        try data.write(to: artifactFile)

        let receipt = try ReceiptBuilder()
            .setAppSlug("factory-app")
            .setBundleID("com.factory.app")
            .setVersion("3.0.0")
            .setBuildNumber(300)
            .setArtifact(from: artifactFile)
            .setNotary(submissionID: "sub-300", teamID: "TEAM300")
            .setSparkle(ed25519Signature: "sig-300")
            .build()

        XCTAssertEqual(receipt.appSlug, "factory-app")
        XCTAssertEqual(receipt.version, "3.0.0")
        XCTAssertEqual(receipt.buildNumber, 300)
        XCTAssertEqual(receipt.artifact.contentType, "application/x-newton-compatible-pkg")
        XCTAssertEqual(receipt.notary.teamID, "TEAM300")
        XCTAssertEqual(receipt.sparkle?.ed25519Signature, "sig-300")
    }

    func testInferContentType() {
        XCTAssertEqual(ReceiptBuilder.inferContentType(for: URL(fileURLWithPath: "app.zip")), "application/zip")
        XCTAssertEqual(ReceiptBuilder.inferContentType(for: URL(fileURLWithPath: "app.dmg")), "application/x-apple-diskimage")
        XCTAssertEqual(ReceiptBuilder.inferContentType(for: URL(fileURLWithPath: "app.pkg")), "application/x-newton-compatible-pkg")
        XCTAssertEqual(ReceiptBuilder.inferContentType(for: URL(fileURLWithPath: "app.tar.gz")), "application/gzip")
        XCTAssertEqual(ReceiptBuilder.inferContentType(for: URL(fileURLWithPath: "app.json")), "application/json")
        XCTAssertEqual(ReceiptBuilder.inferContentType(for: URL(fileURLWithPath: "app.unknown")), "application/octet-stream")
    }
}
