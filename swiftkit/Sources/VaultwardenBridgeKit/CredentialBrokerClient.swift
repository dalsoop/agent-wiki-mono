#if os(macOS)
import Foundation
import Network

public enum VaultCredentialBrokerError: Error, LocalizedError, Equatable, Sendable {
    case unavailable
    case timedOut
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Vaultwarden Client 자격증명 브로커를 사용할 수 없습니다."
        case .timedOut: "Vaultwarden Client 응답 시간이 초과됐습니다."
        case .invalidResponse: "Vaultwarden Client 응답 형식이 올바르지 않습니다."
        }
    }
}

public struct VaultCredentialBrokerClient: Sendable {
    public let socketPath: String
    public let timeout: TimeInterval

    public init(
        socketURL: URL = VaultCredentialBrokerPaths.socketURL(),
        timeout: TimeInterval = 15
    ) {
        socketPath = socketURL.path
        self.timeout = timeout
    }

    public func request(_ request: VaultCredentialRequest) async throws -> VaultCredentialResponse {
        try await exchange(request)
    }

    /// op=search 메타 전용(비밀번호 없음). 다중 Google 계정 등 domain-only 실패 시 후보 좁히기.
    public func search(_ request: VaultCredentialRequest) async throws -> VaultSearchResponse {
        var req = request
        if req.op == nil {
            req = VaultCredentialRequest(
                id: request.id,
                requestingApp: request.requestingApp,
                domain: request.domain,
                username: request.username,
                op: "search",
                query: request.query ?? request.domain,
                itemId: request.itemId
            )
        }
        return try await exchange(req)
    }

    /// op=session — GUI 가 unlocked 일 때 메모리 세션(userKey+토큰) 이관.
    /// CLI·agent-vault dual-entry 정본 경로. 실패 시 호출부가 키체인/Touch ID 로 폴백.
    public func exportSession(
        requestingApp: String
    ) async throws -> VaultSessionExportResponse {
        let req = VaultCredentialRequest(
            requestingApp: requestingApp,
            domain: "session",
            op: "session"
        )
        return try await exchange(req)
    }

    private func exchange<T: Decodable & Sendable>(_ request: VaultCredentialRequest) async throws -> T {
        let payload = try VaultCredentialCodec.encodeLine(request)
        let box = CredentialExchangeBox(socketPath: socketPath, payload: payload, timeout: timeout)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                box.start(as: T.self, continuation: continuation)
            }
        } onCancel: {
            box.cancel()
        }
    }
}

/// NWConnection 기반 1회 교환. 응답 타입은 호출 측이 지정(credentials / search).
private final class CredentialExchangeBox: @unchecked Sendable {
    private let queue = DispatchQueue(label: "vaultwarden.credential-broker.client")
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

    func start<T: Decodable & Sendable>(as type: T.Type, continuation: CheckedContinuation<T, any Error>) {
        lock.withLock {
            resume = { result in
                switch result {
                case .success(let data):
                    do {
                        let value = try VaultCredentialCodec.decode(type, from: data)
                        continuation.resume(returning: value)
                    } catch {
                        continuation.resume(throwing: VaultCredentialBrokerError.invalidResponse)
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendRequest()
            case .failed, .cancelled:
                self.finish(.failure(VaultCredentialBrokerError.unavailable))
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(.failure(VaultCredentialBrokerError.timedOut))
        }
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    private func sendRequest() {
        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            if error != nil {
                self?.finish(.failure(VaultCredentialBrokerError.unavailable))
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
                self.finish(.failure(VaultCredentialBrokerError.invalidResponse))
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
