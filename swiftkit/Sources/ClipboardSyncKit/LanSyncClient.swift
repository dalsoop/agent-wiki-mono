#if canImport(CryptoKit)
import CryptoKit
import Foundation
import Network

public enum SwiftLanError: Error, Equatable, Sendable {
    case unavailable
    case authentication
    case invalidResponse
}

public struct SwiftLanPeer: Sendable {
    public var deviceId: String
    public var endpoint: NWEndpoint
    public init(deviceId: String, endpoint: NWEndpoint) { self.deviceId = deviceId; self.endpoint = endpoint }
}

public struct SwiftLanExchangeRequest: Codable, Sendable {
    public var protocolVersion = 1
    public var requesterDeviceId: String
    public var responderDeviceId: String
    public var challenge: String
    public var proof: String
    public var envelopes: [EncryptedEnvelope]
}

public struct SwiftLanExchangeResponse: Codable, Sendable {
    public var responderDeviceId: String
    public var proof: String
    public var envelopes: [EncryptedEnvelope]
}

public enum SwiftLanAuthenticator {
    public static func requestProof(key: Data, challenge: String, requester: String, responder: String) -> String {
        proof(key: key, value: "v1|request|\(challenge)|\(requester)|\(responder)")
    }
    public static func responseProof(key: Data, challenge: String, requester: String, responder: String) -> String {
        proof(key: key, value: "v1|response|\(challenge)|\(requester)|\(responder)")
    }
    public static func matches(_ actual: String, _ expected: String) -> Bool {
        guard let actualData = Data(base64Encoded: actual), let expectedData = Data(base64Encoded: expected) else { return false }
        return actualData.count == expectedData.count && actualData.withUnsafeBytes { (a: UnsafeRawBufferPointer) in
            expectedData.withUnsafeBytes { (e: UnsafeRawBufferPointer) in
                var difference: UInt8 = 0
                for index in 0..<a.count { difference |= a[index] ^ e[index] }
                return difference == 0
            }
        }
    }
    private static func proof(key: Data, value: String) -> String {
        Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key)))
            .base64EncodedString()
    }
}

public final class SwiftLanSyncClient: @unchecked Sendable {
    public init() {}

    public func exchange(
        peer: SwiftLanPeer,
        requesterDeviceId: String,
        groupKey: Data,
        envelopes: [EncryptedEnvelope],
        timeout: Duration = .seconds(2)
    ) async throws -> [EncryptedEnvelope] {
        let challenge = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }).base64EncodedString()
        let value = SwiftLanExchangeRequest(
            requesterDeviceId: requesterDeviceId,
            responderDeviceId: peer.deviceId,
            challenge: challenge,
            proof: SwiftLanAuthenticator.requestProof(
                key: groupKey, challenge: challenge, requester: requesterDeviceId, responder: peer.deviceId),
            envelopes: envelopes)
        let body = try JSONEncoder().encode(value)
        let request = Data("POST /v1/sync HTTP/1.1\r\nHost: lan-peer\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        let response = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await self.roundTrip(endpoint: peer.endpoint, request: request) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw SwiftLanError.unavailable
            }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
        let message = try SwiftHTTPMessage.parse(response)
        if message.status == 403 { throw SwiftLanError.authentication }
        guard message.status == 200,
              let decoded = try? JSONDecoder().decode(SwiftLanExchangeResponse.self, from: message.body)
        else { throw SwiftLanError.invalidResponse }
        let expected = SwiftLanAuthenticator.responseProof(
            key: groupKey, challenge: challenge, requester: requesterDeviceId, responder: peer.deviceId)
        guard decoded.responderDeviceId == peer.deviceId,
              SwiftLanAuthenticator.matches(decoded.proof, expected)
        else { throw SwiftLanError.authentication }
        return decoded.envelopes
    }

    private func roundTrip(endpoint: NWEndpoint, request: Data) async throws -> Data {
        let connection = NWConnection(to: endpoint, using: .tcp)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let state = NWExchangeState(connection: connection, continuation: continuation)
                connection.stateUpdateHandler = { status in state.handle(status: status, request: request) }
                connection.start(queue: .global(qos: .userInitiated))
            }
        } onCancel: {
            connection.cancel()
        }
    }
}

public enum SwiftSyncRoute: Sendable { case lan, relay }
public struct SwiftRoutedSync<T: Sendable>: Sendable { public var value: T; public var route: SwiftSyncRoute }

public struct SwiftLanFirstRouter<T: Sendable>: Sendable {
    private let lanAttempt: @Sendable () async throws -> T
    private let relayAttempt: @Sendable () async throws -> T
    public init(
        lanAttempt: @escaping @Sendable () async throws -> T,
        relayAttempt: @escaping @Sendable () async throws -> T
    ) { self.lanAttempt = lanAttempt; self.relayAttempt = relayAttempt }
    public func sync() async throws -> SwiftRoutedSync<T> {
        do { return SwiftRoutedSync(value: try await lanAttempt(), route: .lan) }
        catch { return SwiftRoutedSync(value: try await relayAttempt(), route: .relay) }
    }
}

struct SwiftHTTPMessage {
    var status: Int
    var body: Data
    static func parse(_ data: Data) throws -> Self {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: delimiter),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8)
        else { throw SwiftLanError.invalidResponse }
        let lines = header.components(separatedBy: "\r\n")
        let status = Int(lines[0].split(separator: " ").dropFirst().first ?? "0") ?? 0
        return SwiftHTTPMessage(status: status, body: Data(data[range.upperBound...]))
    }
}

private final class NWExchangeState: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Data, any Error>?
    private var buffer = Data()
    private var sent = false
    init(connection: NWConnection, continuation: CheckedContinuation<Data, any Error>) {
        self.connection = connection; self.continuation = continuation
    }
    func handle(status: NWConnection.State, request: Data) {
        switch status {
        case .ready where !sent:
            sent = true
            connection.send(content: request, completion: .contentProcessed { [weak self] error in
                if let error { self?.finish(.failure(error)) } else { self?.receive() }
            })
        case .failed(let error): finish(.failure(error))
        case .cancelled: finish(.failure(SwiftLanError.unavailable))
        default: break
        }
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, complete, error in
            guard let self else { return }
            if let data { lock.withLock { buffer.append(data) } }
            if let error { finish(.failure(error)) }
            else if complete { finish(.success(lock.withLock { buffer })) }
            else { receive() }
        }
    }
    private func finish(_ result: Result<Data, any Error>) {
        let value = lock.withLock { () -> CheckedContinuation<Data, any Error>? in
            defer { continuation = nil }
            return continuation
        }
        connection.cancel()
        value?.resume(with: result)
    }
}
#endif
