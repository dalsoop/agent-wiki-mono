import Foundation
import StateRootKit

public struct LoopOpenRequest: Codable, Equatable, Sendable {
    public var loopID: String
    public var requestedAt: String
}

public struct LoopOpenRequestStore: Sendable {
    public enum StoreError: Error { case emptyLoopID }
    public let root: String
    public var path: String { (root as NSString).appendingPathComponent(".open-request.json") }

    public init(root: String = StateRootKit.path("loops")) {
        self.root = (root as NSString).expandingTildeInPath
    }

    public func write(loopID: String, at: Date = Date()) throws {
        guard !loopID.isEmpty else { throw StoreError.emptyLoopID }
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let request = LoopOpenRequest(
            loopID: loopID,
            requestedAt: ISO8601DateFormatter().string(from: at)
        )
        try JSONEncoder().encode(request).write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public func read() throws -> LoopOpenRequest? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try JSONDecoder().decode(LoopOpenRequest.self, from: data)
    }
}
