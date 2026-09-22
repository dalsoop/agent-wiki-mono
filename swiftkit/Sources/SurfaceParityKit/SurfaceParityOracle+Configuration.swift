import Foundation

extension SurfaceParityOracle {
    public struct Configuration: Sendable {
        public enum ArrayComparisonMode: Sendable {
            case ordered
            case unordered
        }

        public var ignoredKeys: Set<String>
        public var floatingPointTolerance: Double?
        public var arrayMode: ArrayComparisonMode
        public var unwrapTopLevelEnvelope: Bool

        public init(
            ignoredKeys: Set<String> = ["timestamp", "generatedAt", "lastModified", "updatedAt", "date", "iso8601"],
            floatingPointTolerance: Double? = 0.0001,
            arrayMode: ArrayComparisonMode = .ordered,
            unwrapTopLevelEnvelope: Bool = true
        ) {
            self.ignoredKeys = ignoredKeys
            self.floatingPointTolerance = floatingPointTolerance
            self.arrayMode = arrayMode
            self.unwrapTopLevelEnvelope = unwrapTopLevelEnvelope
        }
    }
}
