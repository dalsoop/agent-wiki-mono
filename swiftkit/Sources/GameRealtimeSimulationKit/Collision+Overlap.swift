import GameRealtimeProtocolKit

extension CollisionWorld {
    public static func circlesOverlap(
        centerA: FixedVector2,
        radiusA: FixedPoint,
        centerB: FixedVector2,
        radiusB: FixedPoint
    ) throws -> Bool {
        try validate(radius: radiusA)
        try validate(radius: radiusB)
        let radius = Int64(radiusA.rawValue) + Int64(radiusB.rawValue)
        return squaredDistance(
            x: Int64(centerA.x.rawValue) - Int64(centerB.x.rawValue),
            y: Int64(centerA.y.rawValue) - Int64(centerB.y.rawValue),
            isWithin: UInt64(radius)
        )
    }

    public static func aabbsOverlap(
        centerA: FixedVector2,
        halfExtentsA: FixedVector2,
        centerB: FixedVector2,
        halfExtentsB: FixedVector2
    ) throws -> Bool {
        try validate(halfExtents: halfExtentsA)
        try validate(halfExtents: halfExtentsB)
        let first = bounds(center: centerA, halfExtents: halfExtentsA)
        let second = bounds(center: centerB, halfExtents: halfExtentsB)
        return first.minimumX <= second.maximumX
            && second.minimumX <= first.maximumX
            && first.minimumY <= second.maximumY
            && second.minimumY <= first.maximumY
    }

    public static func circleOverlapsAABB(
        circleCenter: FixedVector2,
        radius: FixedPoint,
        aabbCenter: FixedVector2,
        halfExtents: FixedVector2
    ) throws -> Bool {
        try validate(radius: radius)
        try validate(halfExtents: halfExtents)
        let box = bounds(center: aabbCenter, halfExtents: halfExtents)
        let circleX = Int64(circleCenter.x.rawValue)
        let circleY = Int64(circleCenter.y.rawValue)
        let nearestX = min(max(circleX, box.minimumX), box.maximumX)
        let nearestY = min(max(circleY, box.minimumY), box.maximumY)
        return squaredDistance(
            x: circleX - nearestX,
            y: circleY - nearestY,
            isWithin: UInt64(radius.rawValue)
        )
    }

    static func overlaps(
        _ lhs: CollisionShape,
        _ rhs: CollisionShape
    ) throws -> Bool {
        switch (lhs, rhs) {
        case let (
            .circle(firstCenter, firstRadius),
            .circle(secondCenter, secondRadius)
        ):
            return try circlesOverlap(
                centerA: firstCenter,
                radiusA: firstRadius,
                centerB: secondCenter,
                radiusB: secondRadius
            )
        case let (
            .aabb(firstCenter, firstHalfExtents),
            .aabb(secondCenter, secondHalfExtents)
        ):
            return try aabbsOverlap(
                centerA: firstCenter,
                halfExtentsA: firstHalfExtents,
                centerB: secondCenter,
                halfExtentsB: secondHalfExtents
            )
        case let (.circle(center, radius), .aabb(boxCenter, halfExtents)),
             let (.aabb(boxCenter, halfExtents), .circle(center, radius)):
            return try circleOverlapsAABB(
                circleCenter: center,
                radius: radius,
                aabbCenter: boxCenter,
                halfExtents: halfExtents
            )
        }
    }

    static func validate(radius: FixedPoint) throws {
        guard radius.rawValue >= 0 else {
            throw CollisionWorldError.negativeRadius(radius.rawValue)
        }
    }

    static func validate(
        halfExtents: FixedVector2
    ) throws {
        guard halfExtents.x.rawValue >= 0,
              halfExtents.y.rawValue >= 0
        else {
            throw CollisionWorldError.negativeHalfExtents(halfExtents)
        }
    }

    static func bounds(
        center: FixedVector2,
        halfExtents: FixedVector2
    ) -> (
        minimumX: Int64,
        maximumX: Int64,
        minimumY: Int64,
        maximumY: Int64
    ) {
        let centerX = Int64(center.x.rawValue)
        let centerY = Int64(center.y.rawValue)
        let extentX = Int64(halfExtents.x.rawValue)
        let extentY = Int64(halfExtents.y.rawValue)
        return (
            centerX - extentX,
            centerX + extentX,
            centerY - extentY,
            centerY + extentY
        )
    }

    static func bounds(
        for shape: CollisionShape
    ) -> (
        minimumX: Int64,
        maximumX: Int64,
        minimumY: Int64,
        maximumY: Int64
    ) {
        switch shape {
        case let .circle(center, radius):
            let extent = FixedVector2(x: radius, y: radius)
            return bounds(center: center, halfExtents: extent)
        case let .aabb(center, halfExtents):
            return bounds(center: center, halfExtents: halfExtents)
        }
    }
}
