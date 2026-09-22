import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct StaffHTTPRequest: Sendable {
    public var method: String
    public var url: URL
    public var headers: [String: String]
    public var body: Data?

    public init(method: String, url: URL, headers: [String: String], body: Data?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct StaffHTTPResponse: Sendable {
    public var status: Int
    public var data: Data

    public init(status: Int, data: Data) {
        self.status = status
        self.data = data
    }
}

/// 스텁 가능한 HTTP 전송. 실서버를 테스트에서 부르지 않는다.
public protocol StaffHTTPTransport: Sendable {
    func send(_ request: StaffHTTPRequest) async throws -> StaffHTTPResponse
}

public struct URLSessionStaffHTTP: StaffHTTPTransport {
    public var session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public func send(_ request: StaffHTTPRequest) async throws -> StaffHTTPResponse {
        var req = URLRequest(url: request.url)
        req.httpMethod = request.method
        req.httpBody = request.body
        for (key, value) in request.headers {
            req.setValue(value, forHTTPHeaderField: key)
        }
        let (data, resp) = try await session.data(for: req)
        return StaffHTTPResponse(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, data: data)
    }
}

/// 경로별 응답을 고정하는 인메모리 스텁.
public struct StubStaffHTTP: StaffHTTPTransport {
    public typealias Handler = @Sendable (StaffHTTPRequest) throws -> StaffHTTPResponse

    public let handler: Handler

    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    public func send(_ request: StaffHTTPRequest) async throws -> StaffHTTPResponse {
        try handler(request)
    }
}
