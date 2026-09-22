import GameRealtimeProtocolKit

public enum CollisionWorldError: Error, Equatable, Sendable {
    case invalidLimit(resource: EngineCapacityError.Resource, value: Int)
    case invalidCellSize(Int32)
    case negativeRadius(Int32)
    case negativeHalfExtents(FixedVector2)
    case duplicateEntityIndex(UInt32)
    case invalidHitFraction(numerator: UInt64, denominator: UInt64)
    case arithmeticOverflow
}

public struct CollisionPair:
    Hashable,
    Codable,
    Sendable,
    Comparable
{
    public let first: EntityHandle
    public let second: EntityHandle

    public init(_ lhs: EntityHandle, _ rhs: EntityHandle) {
        if Self.entityLess(lhs, rhs) {
            first = lhs
            second = rhs
        } else {
            first = rhs
            second = lhs
        }
    }

    public var minIndex: UInt32 {
        first.index
    }

    public var maxIndex: UInt32 {
        second.index
    }

    public static func < (lhs: CollisionPair, rhs: CollisionPair) -> Bool {
        if lhs.first != rhs.first {
            return entityLess(lhs.first, rhs.first)
        }
        return entityLess(lhs.second, rhs.second)
    }

    static func entityLess(
        _ lhs: EntityHandle,
        _ rhs: EntityHandle
    ) -> Bool {
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }
        return lhs.generation < rhs.generation
    }
}

public struct CollisionHitFraction:
    Hashable,
    Codable,
    Sendable,
    Comparable
{
    public let numerator: UInt64
    public let denominator: UInt64

    public init(numerator: UInt64, denominator: UInt64) throws {
        guard denominator > 0, numerator <= denominator else {
            throw CollisionWorldError.invalidHitFraction(
                numerator: numerator,
                denominator: denominator
            )
        }
        let divisor = Self.greatestCommonDivisor(numerator, denominator)
        self.numerator = numerator / divisor
        self.denominator = denominator / divisor
    }

    public static func < (
        lhs: CollisionHitFraction,
        rhs: CollisionHitFraction
    ) -> Bool {
        let left = lhs.numerator.multipliedFullWidth(by: rhs.denominator)
        let right = rhs.numerator.multipliedFullWidth(by: lhs.denominator)
        if left.high != right.high {
            return left.high < right.high
        }
        return left.low < right.low
    }

    private static func greatestCommonDivisor(
        _ lhs: UInt64,
        _ rhs: UInt64
    ) -> UInt64 {
        var a = lhs
        var b = rhs
        while b != 0 {
            let remainder = a % b
            a = b
            b = remainder
        }
        return max(a, 1)
    }
}

public struct SweptCollisionHit: Hashable, Codable, Sendable {
    public let entity: EntityHandle
    public let fraction: CollisionHitFraction

    public init(entity: EntityHandle, fraction: CollisionHitFraction) {
        self.entity = entity
        self.fraction = fraction
    }
}

struct CollisionCell: Hashable, Sendable, Comparable {
    let x: Int64
    let y: Int64

    static func < (lhs: CollisionCell, rhs: CollisionCell) -> Bool {
        if lhs.x != rhs.x {
            return lhs.x < rhs.x
        }
        return lhs.y < rhs.y
    }
}

enum CollisionShape: Hashable, Sendable {
    case circle(center: FixedVector2, radius: FixedPoint)
    case aabb(center: FixedVector2, halfExtents: FixedVector2)
}

struct CollisionBody: Hashable, Sendable {
    let entity: EntityHandle
    let shape: CollisionShape
    let cells: [CollisionCell]
}

public struct CollisionWorld: Sendable {
    public let limits: RealtimeLimits
    public let cellSize: FixedPoint
    var bodies: [CollisionBody]
    var entitySlots: [UInt32: Int]
    var cellBuckets: [CollisionCell: [Int]]
    var occupiedCells: Set<CollisionCell>

    public init(
        limits: RealtimeLimits = .standardV1,
        cellSize: FixedPoint = FixedPoint(rawValue: FixedPoint.scale)
    ) throws {
        guard limits.broadphaseOccupiedCells >= 0 else {
            throw CollisionWorldError.invalidLimit(
                resource: .broadphaseOccupiedCells,
                value: limits.broadphaseOccupiedCells
            )
        }
        guard limits.broadphaseCandidatePairsPerTick >= 0 else {
            throw CollisionWorldError.invalidLimit(
                resource: .broadphaseCandidatePairsPerTick,
                value: limits.broadphaseCandidatePairsPerTick
            )
        }
        guard limits.resolvedCollisionPairsPerTick >= 0 else {
            throw CollisionWorldError.invalidLimit(
                resource: .resolvedCollisionPairsPerTick,
                value: limits.resolvedCollisionPairsPerTick
            )
        }
        guard limits.solverIterationsPerPair >= 0 else {
            throw CollisionWorldError.invalidLimit(
                resource: .solverIterationsPerPair,
                value: limits.solverIterationsPerPair
            )
        }
        guard cellSize.rawValue > 0 else {
            throw CollisionWorldError.invalidCellSize(cellSize.rawValue)
        }
        self.limits = limits
        self.cellSize = cellSize
        bodies = []
        entitySlots = [:]
        cellBuckets = [:]
        occupiedCells = []
    }

    public var bodyCount: Int {
        bodies.count
    }

    public var occupiedCellCount: Int {
        occupiedCells.count
    }

    public mutating func insertCircle(
        entity: EntityHandle,
        center: FixedVector2,
        radius: FixedPoint
    ) throws {
        try Self.validate(radius: radius)
        try insert(
            entity: entity,
            shape: .circle(center: center, radius: radius)
        )
    }

    public mutating func insertAABB(
        entity: EntityHandle,
        center: FixedVector2,
        halfExtents: FixedVector2
    ) throws {
        try Self.validate(halfExtents: halfExtents)
        try insert(
            entity: entity,
            shape: .aabb(center: center, halfExtents: halfExtents)
        )
    }

    mutating func insert(
        entity: EntityHandle,
        shape: CollisionShape
    ) throws {
        guard entitySlots[entity.index] == nil else {
            throw CollisionWorldError.duplicateEntityIndex(entity.index)
        }
        let shapeBounds = Self.bounds(for: shape)
        let stagedCells = try cells(
            minimumX: shapeBounds.minimumX,
            maximumX: shapeBounds.maximumX,
            minimumY: shapeBounds.minimumY,
            maximumY: shapeBounds.maximumY
        )

        let body = CollisionBody(
            entity: entity,
            shape: shape,
            cells: stagedCells.body
        )
        let slot = bodies.count
        bodies.append(body)
        entitySlots[entity.index] = slot
        for cell in stagedCells.body {
            cellBuckets[cell, default: []].append(slot)
        }
        occupiedCells.formUnion(stagedCells.newOccupied)
    }

    func cells(
        minimumX: Int64,
        maximumX: Int64,
        minimumY: Int64,
        maximumY: Int64
    ) throws -> (body: [CollisionCell], newOccupied: [CollisionCell]) {
        let divisor = Int64(cellSize.rawValue)
        let firstX = Self.floorDivision(minimumX, by: divisor)
        let lastX = Self.floorDivision(maximumX, by: divisor)
        let firstY = Self.floorDivision(minimumY, by: divisor)
        let lastY = Self.floorDivision(maximumY, by: divisor)
        var result: [CollisionCell] = []
        var newOccupied: [CollisionCell] = []
        var x = firstX
        while x <= lastX {
            var y = firstY
            while y <= lastY {
                let cell = CollisionCell(x: x, y: y)
                result.append(cell)
                if !occupiedCells.contains(cell) {
                    newOccupied.append(cell)
                    guard occupiedCells.count + newOccupied.count
                            <= limits.broadphaseOccupiedCells
                    else {
                        throw EngineCapacityError(
                            resource: .broadphaseOccupiedCells,
                            limit: limits.broadphaseOccupiedCells,
                            attempted:
                                limits.broadphaseOccupiedCells + 1
                        )
                    }
                }
                if y == Int64.max {
                    throw CollisionWorldError.arithmeticOverflow
                }
                y += 1
            }
            if x == Int64.max {
                throw CollisionWorldError.arithmeticOverflow
            }
            x += 1
        }
        return (result, newOccupied)
    }

    func body(for entity: EntityHandle) -> CollisionBody? {
        guard let slot = entitySlots[entity.index],
              bodies[slot].entity == entity
        else {
            return nil
        }
        return bodies[slot]
    }
}
