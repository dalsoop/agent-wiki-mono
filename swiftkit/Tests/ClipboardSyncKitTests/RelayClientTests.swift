import ClipboardSyncKit
import Foundation
import Testing

@Suite("RelayClient HTTP contract", .serialized)
struct RelayClientTests {
    @Test func vaultUploadAndChangesUseServerWireFormat() async throws {
        let log = LockedRequests()
        TestURLProtocol.handler = { request in
            log.append(request)
            switch request.url!.path {
            case "/v1/vaults":
                return (201, #"{"vaultId":"v","deviceId":"mac","token":"t"}"#)
            case "/v1/envelopes":
                return (200, #"{"cursors":["1"]}"#)
            case "/v1/changes":
                return (200, #"{"envelopes":[],"nextCursor":"1"}"#)
            default: return (404, #"{}"#)
            }
        }
        let client = RelayClient(baseURL: URL(string: "https://relay.test")!, session: testSession())

        let owner = try await client.createVault(deviceId: "mac", deviceName: "Mac")
        _ = try await client.upload(token: owner.token, envelopes: [fixtureEnvelope])
        let page = try await client.changes(token: owner.token, cursor: nil, limit: 200)

        #expect(owner.vaultId == "v")
        #expect(page.nextCursor == "1")
        #expect(log.paths == ["/v1/vaults", "/v1/envelopes", "/v1/changes"])
        #expect(log.authorizationHeaders == [nil, "Bearer t", "Bearer t"])
    }

    @Test func status401IsTypedAsUnauthorized() async {
        TestURLProtocol.handler = { _ in (401, #"{"code":"unauthorized","message":"no"}"#) }
        let client = RelayClient(baseURL: URL(string: "https://relay.test")!, session: testSession())

        await #expect(throws: RelayError.unauthorized) {
            _ = try await client.changes(token: "bad", cursor: nil, limit: 200)
        }
    }

    private var fixtureEnvelope: EncryptedEnvelope {
        EncryptedEnvelope(
            vaultId: "v", clipId: "c", updatedAt: 1, operation: .upsert,
            nonce: "AAAAAAAAAAAAAAAA", ciphertext: "AAAAAAAAAAAAAAAAAAAAAA==")
    }

    private func testSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class LockedRequests: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
    var paths: [String] { lock.withLock { requests.map { $0.url!.path } } }
    var authorizationHeaders: [String?] {
        lock.withLock { requests.map { $0.value(forHTTPHeaderField: "Authorization") } }
    }
}

private final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: @Sendable (URLRequest) -> (Int, String) = { _ in (500, "{}") }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
