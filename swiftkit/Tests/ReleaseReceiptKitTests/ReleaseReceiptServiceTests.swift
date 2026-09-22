import XCTest
import ReleaseReceiptKit

final class ReleaseReceiptServiceTests: XCTestCase {
    var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("release-receipt-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
            } catch {
                _ = error
            }
        }
        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            _ = error
        }
        try super.tearDownWithError()
    }

    func testSHA256AndFileSizeCalculation() throws {
        let sampleFile = tempDir.appendingPathComponent("sample.dmg")
        let sampleData = Data("Antigravity Notarization Receipt Test Payload".utf8)
        try sampleData.write(to: sampleFile)

        let hash = try ReleaseReceiptService.sha256(of: sampleFile)
        let size = try ReleaseReceiptService.fileSize(of: sampleFile)
        let contentType = ReleaseReceiptService.determineContentType(for: sampleFile)

        XCTAssertEqual(size, Int64(sampleData.count))
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(contentType, "application/x-apple-diskimage")
    }

    func testSealReceiptAtomicAndImmutable() throws {
        let artifactFile = tempDir.appendingPathComponent("TestApp.dmg")
        let artifactData = Data("Test Artifact Binary Content for Receipt".utf8)
        try artifactData.write(to: artifactFile)

        let packagingDir = tempDir.appendingPathComponent("Packaging", isDirectory: true)
        let submissionID = "12345678-abcd-ef01-2345-6789abcdef01"

        let receipt = try ReleaseReceiptService.sealReceipt(options: ReleaseReceiptService.SealReceiptOptions(
            artifactURL: artifactFile,
            submissionID: submissionID,
            notarizedAt: Date(),
            teamID: "V2Z46YY386",
            appSlug: "test-app",
            bundleID: "ai.gujo.testapp",
            version: "1.2.3",
            buildNumber: 42,
            destinationDirectory: packagingDir,
            makeImmutable: true
        ))

        XCTAssertEqual(receipt.appSlug, "test-app")
        XCTAssertEqual(receipt.bundleID, "ai.gujo.testapp")
        XCTAssertEqual(receipt.version, "1.2.3")
        XCTAssertEqual(receipt.buildNumber, 42)
        XCTAssertEqual(receipt.artifact.filename, "TestApp.dmg")
        XCTAssertEqual(receipt.artifact.sizeBytes, Int64(artifactData.count))
        XCTAssertEqual(receipt.notary.submissionID, submissionID)
        XCTAssertEqual(receipt.notary.teamID, "V2Z46YY386")

        let receiptFile = packagingDir.appendingPathComponent("release-receipt.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptFile.path))

        let attrs = try FileManager.default.attributesOfItem(atPath: receiptFile.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
        XCTAssertEqual(perms & 0o777, 0o444, "영수증 파일은 반드시 0o444 읽기 전용으로 봉인되어야 함")

        let loadedReceipt = try ReleaseReceipt.from(fileURL: receiptFile)
        XCTAssertEqual(receipt.appSlug, loadedReceipt.appSlug)
        XCTAssertEqual(receipt.bundleID, loadedReceipt.bundleID)
        XCTAssertEqual(receipt.version, loadedReceipt.version)
        XCTAssertEqual(receipt.artifact.sha256, loadedReceipt.artifact.sha256)
    }

    func testSealReceiptForAppReadsPackagingInfoPlist() throws {
        let appDir = tempDir.appendingPathComponent("demo-swift", isDirectory: true)
        let packagingDir = appDir.appendingPathComponent("Packaging", isDirectory: true)
        try FileManager.default.createDirectory(at: packagingDir, withIntermediateDirectories: true)

        let infoPlistData = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleIdentifier</key>
            <string>ai.gujo.demo</string>
            <key>CFBundleShortVersionString</key>
            <string>2.0.0</string>
            <key>CFBundleVersion</key>
            <string>101</string>
            <key>CFBundleExecutable</key>
            <string>Demo</string>
        </dict>
        </plist>
        """.utf8)
        try infoPlistData.write(to: packagingDir.appendingPathComponent("Info.plist"))

        let artifactFile = tempDir.appendingPathComponent("demo-2.0.0.zip")
        try Data("fake-zip-data".utf8).write(to: artifactFile)

        let receipt = try ReleaseReceiptService.sealReceiptForApp(options: ReleaseReceiptService.SealAppOptions(
            appDir: appDir,
            bundleURL: nil,
            artifactURL: artifactFile,
            submissionID: "sub-9999",
            teamID: "V2Z46YY386",
            destinationDirectories: [packagingDir]
        ))

        XCTAssertEqual(receipt.appSlug, "demo")
        XCTAssertEqual(receipt.bundleID, "ai.gujo.demo")
        XCTAssertEqual(receipt.version, "2.0.0")
        XCTAssertEqual(receipt.buildNumber, 101)
        XCTAssertEqual(receipt.notary.submissionID, "sub-9999")

        let receiptFile = packagingDir.appendingPathComponent("release-receipt.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptFile.path))
    }
}
