import Foundation

public protocol GujoStoreHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GujoStoreHTTPClient {}
