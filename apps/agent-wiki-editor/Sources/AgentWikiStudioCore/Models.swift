import Foundation

/// `agent-wiki list --json` 한 행. full CLI 의 `JRow`/`ListResult` 응답 모양을 그대로 따른다.
public struct WikiRecord: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String?
    public let author: String
    public let published: String
    public let batch: String?

    public init(id: String, title: String?, author: String, published: String, batch: String?) {
        self.id = id
        self.title = title
        self.author = author
        self.published = published
        self.batch = batch
    }
}

struct WikiListResult: Decodable {
    let objects: [WikiRecord]
    let note: String
}

struct WikiListEnvelope: Decodable {
    let ok: Bool
    let result: WikiListResult
}
