import Foundation
#if canImport(FoundationNetworking)
// Linux/Windows 의 swift-corelibs-foundation 은 URLRequest·URLSession·HTTPURLResponse 를
// 별도 모듈 FoundationNetworking 으로 분리한다(Apple 플랫폼은 Foundation 에 통합). 이 import 가
// 없으면 Linux 에서 "cannot find 'URLRequest'" 로 컴파일 실패한다.
import FoundationNetworking
#endif

/// 최소 HTTP 주입 seam — 테스트에서 목으로 대체 가능한 공용 클라이언트 추상화.
/// agent-vault / env-vault / infisical(InfisicalKit) 등이 각자 동일하게 정의하던 것을 하나로 묶었다.
public protocol HTTPClient: Sendable {
    func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (status: Int, data: Data)
}

/// URLSession 기반 기본 구현.
public struct URLSessionHTTPClient: HTTPClient {
    public init() {}
    public func send(method: String, url: URL, headers: [String: String], body: Data?) async throws -> (status: Int, data: Data) {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        let (data, resp) = try await URLSession.shared.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }
}
