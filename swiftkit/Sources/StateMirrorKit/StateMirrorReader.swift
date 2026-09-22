import Foundation

public struct StateMirrorEnvelope<State: Decodable & Sendable>: Decodable, Sendable {
    public let app: String
    public let updatedAt: String
    public let state: State
}

public enum StateMirrorReadError: Error, Equatable {
    case missing(String)
    case malformed(String)
}

public extension StateMirror {
    static func read<State: Decodable & Sendable>(
        app: String,
        as type: State.Type
    ) throws -> StateMirrorEnvelope<State> {
        try read(url: URL(fileURLWithPath: path(app: app)), as: type)
    }

    static func read<State: Decodable & Sendable>(
        url: URL,
        as type: State.Type
    ) throws -> StateMirrorEnvelope<State> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StateMirrorReadError.missing(url.path)
        }
        do {
            return try JSONDecoder().decode(
                StateMirrorEnvelope<State>.self,
                from: Data(contentsOf: url)
            )
        } catch {
            throw StateMirrorReadError.malformed(error.localizedDescription)
        }
    }
}
