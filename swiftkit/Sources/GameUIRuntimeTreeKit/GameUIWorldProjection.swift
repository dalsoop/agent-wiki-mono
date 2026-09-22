import Foundation

/// A renderer-owned projection seam for world-space UI such as unit health bars.
public protocol GameUIWorldProjection: Sendable {
    func project(worldPoint: GameUIPoint) -> GameUIPoint?
}

public struct GameUIIdentityProjection: GameUIWorldProjection {
    public init() {}

    public func project(worldPoint: GameUIPoint) -> GameUIPoint? {
        worldPoint
    }
}
