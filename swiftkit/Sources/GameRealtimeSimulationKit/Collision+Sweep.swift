import GameRealtimeProtocolKit

extension CollisionWorld {
    private struct SignedFraction: Sendable {
        let numerator: Int64
        let denominator: Int64
    }

    public func sweptSegment(
        from: FixedVector2,
        to: FixedVector2,
        radius: FixedPoint
    ) throws -> SweptCollisionHit? {
        try Self.validate(radius: radius)
        var nearest: SweptCollisionHit?
        let expansion = Int64(radius.rawValue)
        let minimumX = try Self.subtract(
            min(Int64(from.x.rawValue), Int64(to.x.rawValue)),
            expansion
        )
        let maximumX = try Self.add(
            max(Int64(from.x.rawValue), Int64(to.x.rawValue)),
            expansion
        )
        let minimumY = try Self.subtract(
            min(Int64(from.y.rawValue), Int64(to.y.rawValue)),
            expansion
        )
        let maximumY = try Self.add(
            max(Int64(from.y.rawValue), Int64(to.y.rawValue)),
            expansion
        )
        let divisor = Int64(cellSize.rawValue)
        let firstX = Self.floorDivision(minimumX, by: divisor)
        let lastX = Self.floorDivision(maximumX, by: divisor)
        let firstY = Self.floorDivision(minimumY, by: divisor)
        let lastY = Self.floorDivision(maximumY, by: divisor)
        var candidateSlots: Set<Int> = []
        let (xDifference, xOverflow) =
            lastX.subtractingReportingOverflow(firstX)
        let (yDifference, yOverflow) =
            lastY.subtractingReportingOverflow(firstY)
        let (xCount, xCountOverflow) =
            xDifference.addingReportingOverflow(1)
        let (yCount, yCountOverflow) =
            yDifference.addingReportingOverflow(1)
        let (queryCellCount, areaOverflow) =
            xCount.multipliedReportingOverflow(by: yCount)
        if !xOverflow, !yOverflow,
           !xCountOverflow, !yCountOverflow, !areaOverflow,
           queryCellCount >= 0,
           queryCellCount <= Int64(occupiedCells.count)
        {
            var x = firstX
            while x <= lastX {
                var y = firstY
                while y <= lastY {
                    candidateSlots.formUnion(
                        cellBuckets[CollisionCell(x: x, y: y)] ?? []
                    )
                    if y == Int64.max {
                        break
                    }
                    y += 1
                }
                if x == Int64.max {
                    break
                }
                x += 1
            }
        } else {
            for (cell, slots) in cellBuckets
            where firstX <= cell.x && cell.x <= lastX
                && firstY <= cell.y && cell.y <= lastY
            {
                candidateSlots.formUnion(slots)
            }
        }
        let orderedSlots = candidateSlots.sorted {
            CollisionPair.entityLess(
                bodies[$0].entity,
                bodies[$1].entity
            )
        }
        for slot in orderedSlots {
            let body = bodies[slot]
            let fraction: CollisionHitFraction?
            switch body.shape {
            case let .circle(center, bodyRadius):
                fraction = try Self.sweptCircleFraction(
                    from: from,
                    to: to,
                    center: center,
                    radius: bodyRadius,
                    projectileRadius: radius
                )
            case let .aabb(center, halfExtents):
                fraction = try Self.sweptAABBFraction(
                    from: from,
                    to: to,
                    center: center,
                    halfExtents: halfExtents,
                    projectileRadius: radius
                )
            }
            guard let fraction else {
                continue
            }
            let candidate = SweptCollisionHit(
                entity: body.entity,
                fraction: fraction
            )
            if let currentNearest = nearest {
                if candidate.fraction < currentNearest.fraction
                    || (
                        candidate.fraction == currentNearest.fraction
                            && CollisionPair.entityLess(
                                candidate.entity,
                                currentNearest.entity
                            )
                    ) {
                    nearest = candidate
                }
            } else {
                nearest = candidate
            }
        }
        return nearest
    }

    static func sweptAABBFraction(
        from: FixedVector2,
        to: FixedVector2,
        center: FixedVector2,
        halfExtents: FixedVector2,
        projectileRadius: FixedPoint
    ) throws -> CollisionHitFraction? {
        let base = bounds(center: center, halfExtents: halfExtents)
        let expansion = Int64(projectileRadius.rawValue)
        let expanded = (
            minimumX: base.minimumX - expansion,
            maximumX: base.maximumX + expansion,
            minimumY: base.minimumY - expansion,
            maximumY: base.maximumY + expansion
        )
        var entry = SignedFraction(numerator: 0, denominator: 1)
        var exit = SignedFraction(numerator: 1, denominator: 1)
        guard try updateInterval(
            start: Int64(from.x.rawValue),
            end: Int64(to.x.rawValue),
            minimum: expanded.minimumX,
            maximum: expanded.maximumX,
            entry: &entry,
            exit: &exit
        ), try updateInterval(
            start: Int64(from.y.rawValue),
            end: Int64(to.y.rawValue),
            minimum: expanded.minimumY,
            maximum: expanded.maximumY,
            entry: &entry,
            exit: &exit
        ) else {
            return nil
        }
        return try CollisionHitFraction(
            numerator: UInt64(entry.numerator),
            denominator: UInt64(entry.denominator)
        )
    }

    static func sweptCircleFraction(
        from: FixedVector2,
        to: FixedVector2,
        center: FixedVector2,
        radius: FixedPoint,
        projectileRadius: FixedPoint
    ) throws -> CollisionHitFraction? {
        let startX = Int64(from.x.rawValue) - Int64(center.x.rawValue)
        let startY = Int64(from.y.rawValue) - Int64(center.y.rawValue)
        let deltaX = Int64(to.x.rawValue) - Int64(from.x.rawValue)
        let deltaY = Int64(to.y.rawValue) - Int64(from.y.rawValue)
        let combinedRadius = Int64(radius.rawValue)
            + Int64(projectileRadius.rawValue)

        let startSquared = try sumOfSquares(startX, startY)
        let radiusSquared = try multiplied(combinedRadius, combinedRadius)
        let c = try subtract(startSquared, radiusSquared)
        if c <= 0 {
            return try CollisionHitFraction(numerator: 0, denominator: 1)
        }
        let a = try sumOfSquares(deltaX, deltaY)
        guard a > 0 else {
            return nil
        }
        let dot = try add(
            multiplied(startX, deltaX),
            multiplied(startY, deltaY)
        )
        let b = try multiplied(2, dot)
        let bSquared = try multiplied(b, b)
        let fourAC = try multiplied(4, multiplied(a, c))
        let discriminant = try subtract(bSquared, fourAC)
        guard discriminant >= 0 else {
            return nil
        }
        let root = integerSquareRoot(discriminant)
        let negatedB = try subtract(0, b)
        let numerator = try subtract(negatedB, root)
        let denominator = try multiplied(2, a)
        guard numerator >= 0, numerator <= denominator else {
            return nil
        }
        return try CollisionHitFraction(
            numerator: UInt64(numerator),
            denominator: UInt64(denominator)
        )
    }

    private static func updateInterval(
        start: Int64,
        end: Int64,
        minimum: Int64,
        maximum: Int64,
        entry: inout SignedFraction,
        exit: inout SignedFraction
    ) throws -> Bool {
        let delta = end - start
        guard delta != 0 else {
            return minimum <= start && start <= maximum
        }
        let axisEntry: SignedFraction
        let axisExit: SignedFraction
        if delta > 0 {
            axisEntry = SignedFraction(
                numerator: minimum - start,
                denominator: delta
            )
            axisExit = SignedFraction(
                numerator: maximum - start,
                denominator: delta
            )
        } else {
            axisEntry = SignedFraction(
                numerator: start - maximum,
                denominator: -delta
            )
            axisExit = SignedFraction(
                numerator: start - minimum,
                denominator: -delta
            )
        }
        if try fractionLess(entry, axisEntry) {
            entry = axisEntry
        }
        if try fractionLess(axisExit, exit) {
            exit = axisExit
        }
        return try !fractionLess(exit, entry)
    }

    private static func fractionLess(
        _ lhs: SignedFraction,
        _ rhs: SignedFraction
    ) throws -> Bool {
        try multiplied(lhs.numerator, rhs.denominator)
            < multiplied(rhs.numerator, lhs.denominator)
    }
}
