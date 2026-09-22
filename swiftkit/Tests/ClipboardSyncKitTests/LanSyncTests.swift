@testable import ClipboardSyncKit
import Foundation
import Network
import Testing

@Suite("LAN direct sync")
struct LanSyncTests {
    let key = Data((0..<32).map(UInt8.init))

    @Test func matchingKeyExchangesEncryptedEnvelopeOnLoopback() async throws {
        let envelope = EncryptedEnvelope(
            vaultId: "vault", clipId: "swift", updatedAt: 1, operation: .upsert,
            nonce: "AAAAAAAAAAAAAAAA", ciphertext: "AAAAAAAAAAAAAAAAAAAAAA==")
        let server = SwiftLanServer(
            deviceId: "mac", groupKeyProvider: { self.key },
            exchange: { incoming in
                #expect(incoming == [envelope])
                return [envelope.replacing(clipId: "back")]
            })
        let port = try await server.start()
        defer { server.stop() }

        let response = try await SwiftLanSyncClient().exchange(
            peer: SwiftLanPeer(deviceId: "mac", endpoint: .hostPort(host: "127.0.0.1", port: port)),
            requesterDeviceId: "ios", groupKey: key, envelopes: [envelope], timeout: .seconds(2))

        #expect(response.map(\.clipId) == ["back"])
    }

    @Test func wrongKeyIsForbidden() async throws {
        let server = SwiftLanServer(deviceId: "mac", groupKeyProvider: { self.key }, exchange: { _ in [] })
        let port = try await server.start()
        defer { server.stop() }

        await #expect(throws: SwiftLanError.authentication) {
            _ = try await SwiftLanSyncClient().exchange(
                peer: SwiftLanPeer(deviceId: "mac", endpoint: .hostPort(host: "127.0.0.1", port: port)),
                requesterDeviceId: "ios", groupKey: Data(repeating: 8, count: 32),
                envelopes: [], timeout: .seconds(2))
        }
    }

    @Test func triesNextDiscoveredPeerAfterAuthenticationFailure() async throws {
        let wrongServer = SwiftLanServer(
            deviceId: "wrong", groupKeyProvider: { Data(repeating: 9, count: 32) }, exchange: { _ in [] })
        let rightServer = SwiftLanServer(
            deviceId: "right", groupKeyProvider: { self.key }, exchange: { _ in [] })
        let wrongPort = try await wrongServer.start()
        let rightPort = try await rightServer.start()
        defer { wrongServer.stop(); rightServer.stop() }
        let peers = [
            SwiftLanPeer(deviceId: "wrong", endpoint: .hostPort(host: "127.0.0.1", port: wrongPort)),
            SwiftLanPeer(deviceId: "right", endpoint: .hostPort(host: "127.0.0.1", port: rightPort)),
        ]

        let response: [EncryptedEnvelope] = try await firstSuccessfulLanPeer(peers) { peer in
            try await SwiftLanSyncClient().exchange(
                peer: peer, requesterDeviceId: "ios", groupKey: key,
                envelopes: [], timeout: .seconds(2))
        }

        #expect(response.isEmpty)
    }

    @Test func unavailableLANFallsBackExactlyOnce() async {
        let count = LockedCount()
        let result = try! await SwiftLanFirstRouter<String>(
            lanAttempt: { () async throws -> String in throw SwiftLanError.unavailable },
            relayAttempt: { count.increment(); return "relay" }).sync()
        #expect(result.value == "relay")
        #expect(result.route == .relay)
        #expect(count.value == 1)
    }

    @Test func silentPeerHonorsTimeout() async throws {
        let server = SwiftLanServer(
            deviceId: "silent", groupKeyProvider: { self.key },
            exchange: { _ in
                try? await Task.sleep(for: .seconds(1))
                return []
            })
        let port = try await server.start()
        defer { server.stop() }
        let clock = ContinuousClock()
        let started = clock.now

        await #expect(throws: SwiftLanError.unavailable) {
            _ = try await SwiftLanSyncClient().exchange(
                peer: SwiftLanPeer(deviceId: "silent", endpoint: .hostPort(host: "127.0.0.1", port: port)),
                requesterDeviceId: "ios", groupKey: key, envelopes: [], timeout: .milliseconds(50))
        }
        #expect(started.duration(to: clock.now) < .milliseconds(500))
    }

    @Test func matchesSharedKotlinSwiftAuthenticationVector() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appending(path: "protocols/clipboard-sync-v1/lan-auth-vector.json"))
        let fixture = try JSONDecoder().decode(LanAuthFixture.self, from: data)
        let fixtureKey = Data(base64Encoded: fixture.key)!
        #expect(SwiftLanAuthenticator.requestProof(
            key: fixtureKey, challenge: fixture.challenge,
            requester: fixture.requesterDeviceId, responder: fixture.responderDeviceId) == fixture.requestProof)
        #expect(SwiftLanAuthenticator.responseProof(
            key: fixtureKey, challenge: fixture.challenge,
            requester: fixture.requesterDeviceId, responder: fixture.responderDeviceId) == fixture.responseProof)
    }

    @Test func responderEventuallyServesItemAfterFirstTwoHundred() {
        var pager = SwiftDirtyBatchPager()
        let rows = Array(1...201)
        #expect(pager.requestLimit(pageSize: 200) == 200)
        #expect(pager.next(candidates: Array(rows.prefix(200)), pageSize: 200) == Array(1...200))
        #expect(pager.requestLimit(pageSize: 200) == 400)
        #expect(pager.next(candidates: rows, pageSize: 200) == [201])
        #expect(pager.requestLimit(pageSize: 200) == 200)
    }
}

private struct LanAuthFixture: Decodable {
    var key: String
    var challenge: String
    var requesterDeviceId: String
    var responderDeviceId: String
    var requestProof: String
    var responseProof: String
}

private final class LockedCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

private extension EncryptedEnvelope {
    func replacing(clipId: String) -> Self { var copy = self; copy.clipId = clipId; return copy }
}
