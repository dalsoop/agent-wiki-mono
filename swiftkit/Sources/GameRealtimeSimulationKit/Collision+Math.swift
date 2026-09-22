import GameRealtimeProtocolKit

extension CollisionWorld {
    static func squaredDistance(
        x: Int64,
        y: Int64,
        isWithin radius: UInt64
    ) -> Bool {
        let absoluteX = magnitude(x)
        let absoluteY = magnitude(y)
        guard absoluteX <= radius, absoluteY <= radius else {
            return false
        }
        let radiusSquared = radius * radius
        let ySquared = absoluteY * absoluteY
        return absoluteX * absoluteX <= radiusSquared - ySquared
    }

    static func magnitude(_ value: Int64) -> UInt64 {
        if value >= 0 {
            return UInt64(value)
        }
        return UInt64(-(value + 1)) + 1
    }

    static func sumOfSquares(
        _ lhs: Int64,
        _ rhs: Int64
    ) throws -> Int64 {
        try add(multiplied(lhs, lhs), multiplied(rhs, rhs))
    }

    static func add(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw CollisionWorldError.arithmeticOverflow
        }
        return result
    }

    static func subtract(
        _ lhs: Int64,
        _ rhs: Int64
    ) throws -> Int64 {
        let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        guard !overflow else {
            throw CollisionWorldError.arithmeticOverflow
        }
        return result
    }

    static func multiplied(
        _ lhs: Int64,
        _ rhs: Int64
    ) throws -> Int64 {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw CollisionWorldError.arithmeticOverflow
        }
        return result
    }

    static func integerSquareRoot(_ value: Int64) -> Int64 {
        guard value > 0 else {
            return 0
        }
        var lower: Int64 = 1
        var upper = min(value, 3_037_000_499)
        var answer: Int64 = 0
        while lower <= upper {
            let middle = lower + (upper - lower) / 2
            if middle <= value / middle {
                answer = middle
                lower = middle + 1
            } else {
                upper = middle - 1
            }
        }
        return answer
    }

    static func floorDivision(
        _ value: Int64,
        by divisor: Int64
    ) -> Int64 {
        let quotient = value / divisor
        let remainder = value % divisor
        return remainder < 0 ? quotient - 1 : quotient
    }
}
