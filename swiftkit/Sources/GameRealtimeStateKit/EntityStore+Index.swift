extension EntityStore {
    static func unique<T: Equatable>(_ values: [T]) -> [T] {
        var result: [T] = []
        result.reserveCapacity(values.count)
        for value in values where result.last != value {
            result.append(value)
        }
        return result
    }

    static func componentOrder(
        _ lhs: EntityComponent,
        _ rhs: EntityComponent
    ) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind < rhs.kind
        }
        return entityOrder(lhs.entity, rhs.entity)
    }

    static func entityOrder(
        _ lhs: EntityHandle,
        _ rhs: EntityHandle
    ) -> Bool {
        if lhs.index != rhs.index {
            return lhs.index < rhs.index
        }
        return lhs.generation < rhs.generation
    }

    static func entityInsertionIndex(
        _ entity: EntityHandle,
        in entries: [EntityComponent]
    ) -> Int {
        var lowerBound = entries.startIndex
        var upperBound = entries.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if entityOrder(entries[middle].entity, entity) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    static func kindInsertionIndex(
        _ kind: ComponentKind,
        in kinds: [ComponentKind]
    ) -> Int {
        var lowerBound = kinds.startIndex
        var upperBound = kinds.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if kinds[middle] < kind {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    static func queryCacheInsertionIndex(
        _ requiredKinds: [ComponentKind],
        in entries: [ComponentQueryCacheEntry]
    ) -> Int {
        var lowerBound = entries.startIndex
        var upperBound = entries.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            if kindsOrder(entries[middle].requiredKinds, requiredKinds) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    static func intersection(
        _ lhs: [EntityHandle],
        _ rhs: [EntityHandle]
    ) -> [EntityHandle] {
        var result: [EntityHandle] = []
        result.reserveCapacity(min(lhs.count, rhs.count))
        var lhsPosition = lhs.startIndex
        var rhsPosition = rhs.startIndex
        while lhsPosition < lhs.endIndex && rhsPosition < rhs.endIndex {
            let lhsEntity = lhs[lhsPosition]
            let rhsEntity = rhs[rhsPosition]
            if lhsEntity == rhsEntity {
                result.append(lhsEntity)
                lhsPosition += 1
                rhsPosition += 1
            } else if entityOrder(lhsEntity, rhsEntity) {
                lhsPosition += 1
            } else {
                rhsPosition += 1
            }
        }
        return result
    }

    static func kindsOrder(
        _ lhs: [ComponentKind],
        _ rhs: [ComponentKind]
    ) -> Bool {
        for position in 0..<min(lhs.count, rhs.count) {
            if lhs[position] != rhs[position] {
                return lhs[position] < rhs[position]
            }
        }
        return lhs.count < rhs.count
    }
}
