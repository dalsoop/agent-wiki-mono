import Foundation

public protocol MailSendAdapter: Sendable {
    var name: String { get }
    func send(_ request: MailSendRequest) async throws -> MailSendReceipt
}

public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

public final class RecordingMailSendAdapter: MailSendAdapter, @unchecked Sendable {
    public let name: String
    private let lock = NSLock()
    public private(set) var requests: [MailSendRequest] = []
    private var results: [Result<MailSendReceipt, Error>]
    private var cursor = 0

    public init(name: String = "mock", results: [Result<MailSendReceipt, Error>] = []) {
        self.name = name
        self.results = results
    }

    public func enqueue(_ result: Result<MailSendReceipt, Error>) {
        withLock { results.append(result) }
    }

    public func send(_ request: MailSendRequest) async throws -> MailSendReceipt {
        let result: Result<MailSendReceipt, Error> = withLock {
            requests.append(request)
            let index = cursor
            cursor += 1
            if index < results.count {
                return results[index]
            }
            return .success(MailSendReceipt(providerMessageId: "mock-\(request.messageId)", provider: name))
        }
        return try result.get()
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

public final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    public struct ScriptedResponse: Sendable {
        public var status: Int
        public var body: Data
        public init(status: Int, body: Data) {
            self.status = status
            self.body = body
        }
    }

    private let lock = NSLock()
    public private(set) var requests: [URLRequest] = []
    private var responses: [ScriptedResponse]
    private let fallbackURL: URL

    public init(
        responses: [ScriptedResponse],
        fallbackURL: URL = URL(string: "https://api.resend.com/emails")!
    ) {
        self.responses = responses
        self.fallbackURL = fallbackURL
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let next: ScriptedResponse = {
            lock.lock()
            defer { lock.unlock() }
            requests.append(request)
            return responses.isEmpty
                ? ScriptedResponse(status: 200, body: Data(#"{"id":"re_scripted"}"#.utf8))
                : responses.removeFirst()
        }()
        let url = request.url ?? fallbackURL
        let response = HTTPURLResponse(
            url: url,
            statusCode: next.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (next.body, response)
    }
}
