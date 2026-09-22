import Foundation

public struct GameUIPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func offsetBy(dx: Double, dy: Double) -> Self {
        .init(x: x + dx, y: y + dy)
    }
}

public struct GameUISize: Codable, Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct GameUIRect: Codable, Equatable, Sendable {
    public var origin: GameUIPoint
    public var size: GameUISize

    public init(x: Double, y: Double, width: Double, height: Double) {
        origin = .init(x: x, y: y)
        size = .init(width: width, height: height)
    }

    public var x: Double { origin.x }
    public var y: Double { origin.y }
    public var width: Double { size.width }
    public var height: Double { size.height }

    /// Uses half-open bounds so adjacent controls never claim the same edge.
    public func contains(_ point: GameUIPoint) -> Bool {
        width > 0 && height > 0
            && point.x >= x && point.x < x + width
            && point.y >= y && point.y < y + height
    }
}
