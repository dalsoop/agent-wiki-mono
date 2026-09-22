public struct FixedPoint: Hashable, Codable, Sendable {
    public static let scale: Int32 = 1_024

    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public func adding(_ other: FixedPoint) throws -> FixedPoint {
        let (sum, overflow) = rawValue.addingReportingOverflow(other.rawValue)
        if overflow {
            throw FixedPointError.overflow
        }
        return FixedPoint(rawValue: sum)
    }
}

public enum FixedPointError: Error, Equatable {
    case overflow
}

public struct FixedVector2: Hashable, Codable, Sendable {
    public let x: FixedPoint
    public let y: FixedPoint

    public init(x: FixedPoint, y: FixedPoint) {
        self.x = x
        self.y = y
    }
}
