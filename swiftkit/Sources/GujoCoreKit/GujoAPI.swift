import Foundation

public protocol GujoAPI: Sendable {
    func library() async throws -> [LibraryItem]
    func productDetail(id: Int) async throws -> ProductDetailResponse
    func contentAsset(id: Int, path: String) async throws -> Data
    /// Fetches the shared product-content CSS (api-key) used to style thumbnail_html / body_html.
    func productContentCss() async throws -> String
    /// Downloads the bundle zip to a temp file and returns its URL.
    func downloadBundle(id: Int) async throws -> URL
}
