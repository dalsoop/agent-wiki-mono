import XCTest
import ReleaseReceiptKit
@testable import GujoStoreOpsCore

final class ReceiptIngestTests: XCTestCase {
    private var tempDir: URL = URL(fileURLWithPath: NSTemporaryDirectory())

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("receipt-ingest-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
        try super.tearDownWithError()
    }

    func testValidateValidReceipt() throws {
        let fileURL = tempDir.appendingPathComponent("release-receipt.json")
        let json = """
        {
          "$schema": "https://gujo.ai/schemas/release-receipt-v1.json",
          "appSlug": "screencapture",
          "bundleID": "net.ranode.screencapture",
          "version": "1.0.0",
          "buildNumber": 1,
          "artifact": {
            "filename": "screencapture-1.0.0.dmg",
            "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "sizeBytes": 10485760,
            "contentType": "application/x-apple-diskimage"
          },
          "notary": {
            "submissionID": "00000000-1111-2222-3333-444455556666",
            "notarizedAt": "2026-09-09T04:00:00Z",
            "teamID": "TEAM123"
          },
          "createdAt": "2026-09-09T04:00:00Z"
        }
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let service = ReceiptIngestService()
        let receipt = try service.validateReceipt(at: fileURL)

        XCTAssertEqual(receipt.appSlug, "screencapture")
        XCTAssertEqual(receipt.bundleID, "net.ranode.screencapture")
        XCTAssertEqual(receipt.version, "1.0.0")
        XCTAssertEqual(receipt.artifact.sha256, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(receipt.artifact.sizeBytes, 10485760)
        XCTAssertEqual(receipt.notary.submissionID, "00000000-1111-2222-3333-444455556666")
    }

    func testRejectInvalidSHA256() throws {
        let fileURL = tempDir.appendingPathComponent("bad-sha.json")
        let json = """
        {
          "appSlug": "test",
          "bundleID": "com.example.test",
          "version": "1.0.0",
          "artifact": {
            "filename": "test.dmg",
            "sha256": "not-a-valid-sha256",
            "sizeBytes": 100,
            "contentType": "application/octet-stream"
          },
          "notary": {
            "submissionID": "00000000-1111-2222-3333-444455556666",
            "notarizedAt": "2026-09-09T04:00:00Z"
          },
          "createdAt": "2026-09-09T04:00:00Z"
        }
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let service = ReceiptIngestService()
        XCTAssertThrowsError(try service.validateReceipt(at: fileURL)) { error in
            guard case StoreOpsError.invalidReceipt(let msg) = error else {
                return XCTFail("Expected invalidReceipt error, got \(error)")
            }
            XCTAssertTrue(msg.contains("SHA-256"))
        }
    }

    func testRejectInvalidSize() throws {
        let fileURL = tempDir.appendingPathComponent("bad-size.json")
        let json = """
        {
          "appSlug": "test",
          "bundleID": "com.example.test",
          "version": "1.0.0",
          "artifact": {
            "filename": "test.dmg",
            "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "sizeBytes": 0,
            "contentType": "application/octet-stream"
          },
          "notary": {
            "submissionID": "00000000-1111-2222-3333-444455556666",
            "notarizedAt": "2026-09-09T04:00:00Z"
          },
          "createdAt": "2026-09-09T04:00:00Z"
        }
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let service = ReceiptIngestService()
        XCTAssertThrowsError(try service.validateReceipt(at: fileURL)) { error in
            guard case StoreOpsError.invalidReceipt(let msg) = error else {
                return XCTFail("Expected invalidReceipt error, got \(error)")
            }
            XCTAssertTrue(msg.contains("크기"))
        }
    }

    func testRejectInvalidNotaryID() throws {
        let fileURL = tempDir.appendingPathComponent("bad-notary.json")
        let json = """
        {
          "appSlug": "test",
          "bundleID": "com.example.test",
          "version": "1.0.0",
          "artifact": {
            "filename": "test.dmg",
            "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "sizeBytes": 1000,
            "contentType": "application/octet-stream"
          },
          "notary": {
            "submissionID": "not-a-uuid",
            "notarizedAt": "2026-09-09T04:00:00Z"
          },
          "createdAt": "2026-09-09T04:00:00Z"
        }
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        let service = ReceiptIngestService()
        XCTAssertThrowsError(try service.validateReceipt(at: fileURL)) { error in
            guard case StoreOpsError.invalidReceipt(let msg) = error else {
                return XCTFail("Expected invalidReceipt error, got \(error)")
            }
            XCTAssertTrue(msg.contains("UUID"))
        }
    }

    func testIngestReceiptViaMockSession() async throws {
        let fileURL = tempDir.appendingPathComponent("release-receipt.json")
        let json = """
        {
          "$schema": "https://gujo.ai/schemas/release-receipt-v1.json",
          "appSlug": "screencapture",
          "bundleID": "net.ranode.screencapture",
          "version": "1.0.0",
          "artifact": {
            "filename": "screencapture-1.0.0.dmg",
            "sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            "sizeBytes": 10485760,
            "contentType": "application/x-apple-diskimage"
          },
          "notary": {
            "submissionID": "00000000-1111-2222-3333-444455556666",
            "notarizedAt": "2026-09-09T04:00:00Z"
          },
          "createdAt": "2026-09-09T04:00:00Z"
        }
        """
        try json.write(to: fileURL, atomically: true, encoding: .utf8)

        // Mock URLProtocol
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/ops/v1/receipts/ingest")
            XCTAssertEqual(request.httpMethod, "POST")

            let responseJSON = Data("""
            {
              "ok": true,
              "result": {
                "store_product_id": 42,
                "gujo_product_id": 888,
                "bundle_id": "net.ranode.screencapture",
                "version": "1.0.0",
                "release_id": 10,
                "is_active": true,
                "artifact_sha256": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                "artifact_size": 10485760,
                "notary_submission_id": "00000000-1111-2222-3333-444455556666",
                "external_download_url": "https://gitlab.ranode.net/app.dmg",
                "readiness_score": 100,
                "purchasable": true,
                "summary": "릴리스 v1.0.0 등록 완료"
              }
            }
            """.utf8)

            let targetURL = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(
                url: targetURL,
                statusCode: 201,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) ?? HTTPURLResponse()
            return (response, responseJSON)
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let opsURL = URL(string: "https://ops.example.com") ?? URL(fileURLWithPath: "/")
        let client = StoreOpsClient(
            mode: .opsAPI,
            opsBaseURL: opsURL,
            session: session,
            bearerToken: "test-token"
        )

        let service = ReceiptIngestService()
        let result = try await service.ingest(at: fileURL, client: client)

        XCTAssertTrue(result.ok)
        XCTAssertEqual(result.storeProductId, 42)
        XCTAssertEqual(result.version, "1.0.0")
        XCTAssertTrue(result.isActive)
        XCTAssertTrue(result.purchasable)
        XCTAssertEqual(result.readinessScore, 100)
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            XCTFail("No request handler set")
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
