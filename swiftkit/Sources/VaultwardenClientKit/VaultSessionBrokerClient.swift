#if os(macOS)
import Foundation
import Network

/// Vaultwarden Client 의 credential-broker 소켓에 `op=session` 을 보내
/// GUI 메모리 세션을 가져온다. BridgeKit 타입 복제 없이 JSON 만 맞춘다.
public struct VaultSessionBrokerClient: Sendable {
    public enum BrokerError: Error, LocalizedError, Sendable {
        case unavailable
        case locked
        case denied
        case invalidResponse
        case timedOut

        public var errorDescription: String? {
            switch self {
            case .unavailable: "Vaultwarden Client 세션 브로커에 연결할 수 없습니다"
            case .locked: "볼트가 잠겨 있습니다 — Client 에서 잠금해제하세요"
            case .denied: "세션 이관이 거부됐습니다"
            case .invalidResponse: "세션 브로커 응답이 올바르지 않습니다"
            case .timedOut: "세션 브로커 응답 시간 초과"
            }
        }
    }

    public let socketPath: String
    public let timeout: TimeInterval

    public init(
        socketPath: String = VaultClientSessionGate.sessionBrokerSocketPath(),
        timeout: TimeInterval = 5
    ) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    public func fetchSession(requestingApp: String) async throws -> VaultSessionMaterial {
        let body: [String: Any] = [
            "id": UUID().uuidString,
            "requestingApp": requestingApp,
            "domain": "session",
            "op": "session",
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        var line = payload
        line.append(0x0A)

        let data = try await Self.exchange(socketPath: socketPath, payload: line, timeout: timeout)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = obj["status"] as? String else {
            throw BrokerError.invalidResponse
        }
        switch status {
        case "locked": throw BrokerError.locked
        case "denied": throw BrokerError.denied
        case "unavailable": throw BrokerError.unavailable
        case "success": break
        default: throw BrokerError.invalidResponse
        }
        guard let b64 = obj["userKeyBase64"] as? String,
              let raw = Data(base64Encoded: b64),
              let identity = obj["identity"] as? String,
              let api = obj["api"] as? String,
              let label = obj["label"] as? String,
              let email = obj["email"] as? String,
              let kdf = obj["kdf"] as? Int,
              let iterations = obj["iterations"] as? Int else {
            throw BrokerError.invalidResponse
        }
        let endpoint = ServerEndpoint(identity: identity, api: api, label: label)
        return VaultSessionMaterial(
            userKeyRaw: raw,
            accessToken: obj["accessToken"] as? String,
            refreshToken: obj["refreshToken"] as? String,
            endpoint: endpoint,
            email: email,
            kdf: kdf,
            iterations: iterations
        )
    }

    private static func exchange(socketPath: String, payload: Data, timeout: TimeInterval) async throws -> Data {
        let box = ExchangeBox(socketPath: socketPath, payload: payload, timeout: timeout)
        return try await withCheckedThrowingContinuation { cont in
            box.start(continuation: cont)
        }
    }
}

private final class ExchangeBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "vaultwarden.session-broker.client")
    private let connection: NWConnection
    private let payload: Data
    private let timeout: TimeInterval
    private let lock = NSLock()
    private var finished = false
    private var resume: ((Result<Data, any Error>) -> Void)?

    init(socketPath: String, payload: Data, timeout: TimeInterval) {
        connection = NWConnection(to: .unix(path: socketPath), using: .tcp)
        self.payload = payload
        self.timeout = timeout
    }

    func start(continuation: CheckedContinuation<Data, any Error>) {
        lock.withLock {
            resume = { result in
                switch result {
                case .success(let data): continuation.resume(returning: data)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.send()
            case .failed, .cancelled:
                self.finish(.failure(VaultSessionBrokerClient.BrokerError.unavailable))
            default: break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(VaultSessionBrokerClient.BrokerError.timedOut))
        }
    }

    private func send() {
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.finish(.failure(VaultSessionBrokerClient.BrokerError.unavailable))
            } else {
                self?.receive(buffer: Data())
            }
        })
    }

    private func receive(buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let newline = buffer.firstIndex(of: 0x0A) {
                self.finish(.success(Data(buffer[..<newline])))
            } else if complete || error != nil {
                self.finish(.failure(VaultSessionBrokerClient.BrokerError.invalidResponse))
            } else {
                self.receive(buffer: buffer)
            }
        }
    }

    private func finish(_ result: Result<Data, any Error>) {
        let callback = lock.withLock { () -> ((Result<Data, any Error>) -> Void)? in
            guard !finished else { return nil }
            finished = true
            defer { resume = nil }
            return resume
        }
        connection.cancel()
        callback?(result)
    }
}
#endif
