import Foundation
import Network

public final class SwiftLanServer: @unchecked Sendable {
    private let deviceId: String
    private let groupKeyProvider: @Sendable () async -> Data?
    private let exchange: @Sendable ([EncryptedEnvelope]) async -> [EncryptedEnvelope]
    private let queue = DispatchQueue(label: "clipboard-sync-lan-server")
    private var listener: NWListener?

    public init(
        deviceId: String,
        groupKeyProvider: @escaping @Sendable () async -> Data?,
        exchange: @escaping @Sendable ([EncryptedEnvelope]) async -> [EncryptedEnvelope]
    ) {
        self.deviceId = deviceId
        self.groupKeyProvider = groupKeyProvider
        self.exchange = exchange
    }

    public func start(advertise: Bool = false) async throws -> NWEndpoint.Port {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        if advertise {
            listener.service = NWListener.Service(
                name: "clipboard-sync-\(deviceId)", type: "_clipboard-sync._tcp")
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            let gate = ListenerStartGate(continuation)
            listener.stateUpdateHandler = { state in gate.handle(state: state, listener: listener) }
            listener.start(queue: queue)
        }
    }

    public func stop() { listener?.cancel(); listener = nil }

    private func accept(_ connection: NWConnection) {
        let state = NWServerReceiveState(connection: connection) { [weak self] data in
            guard let self else { return }
            Task { await self.respond(connection: connection, requestData: data) }
        }
        connection.stateUpdateHandler = { status in state.handle(status) }
        connection.start(queue: queue)
    }

    private func respond(connection: NWConnection, requestData: Data) async {
        let result: (Int, Data)
        do {
            let body = try requestBody(requestData)
            let request = try JSONDecoder().decode(SwiftLanExchangeRequest.self, from: body)
            guard request.protocolVersion == 1,
                  request.responderDeviceId == deviceId,
                  let key = await groupKeyProvider(),
                  SwiftLanAuthenticator.matches(
                    request.proof,
                    SwiftLanAuthenticator.requestProof(
                        key: key, challenge: request.challenge,
                        requester: request.requesterDeviceId, responder: deviceId))
            else { throw SwiftLanError.authentication }
            let response = SwiftLanExchangeResponse(
                responderDeviceId: deviceId,
                proof: SwiftLanAuthenticator.responseProof(
                    key: key, challenge: request.challenge,
                    requester: request.requesterDeviceId, responder: deviceId),
                envelopes: await exchange(request.envelopes))
            result = (200, try JSONEncoder().encode(response))
        } catch SwiftLanError.authentication {
            result = (403, Data("{}".utf8))
        } catch {
            result = (400, Data("{}".utf8))
        }
        let reason = result.0 == 200 ? "OK" : result.0 == 403 ? "Forbidden" : "Bad Request"
        let header = Data("HTTP/1.1 \(result.0) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(result.1.count)\r\nConnection: close\r\n\r\n".utf8)
        connection.send(content: header + result.1, isComplete: true, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func requestBody(_ data: Data) throws -> Data {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: delimiter),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8),
              header.hasPrefix("POST /v1/sync HTTP/1.1")
        else { throw SwiftLanError.invalidResponse }
        return Data(data[range.upperBound...])
    }
}

public final class SwiftLanDiscovery: @unchecked Sendable {
    private let browser = NWBrowser(for: .bonjour(type: "_clipboard-sync._tcp", domain: nil), using: .tcp)
    private let queue = DispatchQueue(label: "clipboard-sync-lan-browser")
    private let ownDeviceId: String
    private let lock = NSLock()
    private var found: [String: SwiftLanPeer] = [:]

    public init(deviceId: String) { ownDeviceId = deviceId }
    public var peers: [SwiftLanPeer] { lock.withLock { Array(found.values) } }

    public func start() {
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            var next: [String: SwiftLanPeer] = [:]
            for result in results {
                guard case .service(let name, _, _, _) = result.endpoint,
                      name.hasPrefix("clipboard-sync-") else { continue }
                let id = String(name.dropFirst("clipboard-sync-".count))
                if id != ownDeviceId { next[id] = SwiftLanPeer(deviceId: id, endpoint: result.endpoint) }
            }
            lock.withLock { found = next }
        }
        browser.start(queue: queue)
    }

    public func stop() { browser.cancel(); lock.withLock { found = [:] } }
}

private final class ListenerStartGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NWEndpoint.Port, any Error>?
    init(_ continuation: CheckedContinuation<NWEndpoint.Port, any Error>) { self.continuation = continuation }
    func handle(state: NWListener.State, listener: NWListener) {
        switch state {
        case .ready:
            finish(.success(listener.port!))
        case .failed(let error): finish(.failure(error))
        case .cancelled: finish(.failure(SwiftLanError.unavailable))
        default: break
        }
    }
    private func finish(_ result: Result<NWEndpoint.Port, any Error>) {
        let value = lock.withLock { () -> CheckedContinuation<NWEndpoint.Port, any Error>? in
            defer { continuation = nil }; return continuation
        }
        value?.resume(with: result)
    }
}

private final class NWServerReceiveState: @unchecked Sendable {
    private let connection: NWConnection
    private let complete: @Sendable (Data) -> Void
    private let lock = NSLock()
    private var buffer = Data()
    init(connection: NWConnection, complete: @escaping @Sendable (Data) -> Void) {
        self.connection = connection; self.complete = complete
    }
    func handle(_ state: NWConnection.State) { if case .ready = state { receive() } }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { lock.withLock { buffer.append(data) } }
            let snapshot = lock.withLock { buffer }
            if requestIsComplete(snapshot) { complete(snapshot) }
            else if error != nil || isComplete { connection.cancel() }
            else { receive() }
        }
    }
    private func requestIsComplete(_ data: Data) -> Bool {
        let delimiter = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: delimiter),
              let header = String(data: data[..<range.lowerBound], encoding: .utf8) else { return false }
        let length = header.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? -1
        return length >= 0 && data.count - range.upperBound >= length
    }
}
