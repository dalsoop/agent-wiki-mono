import GameRealtimeProtocolKit

extension CollisionWorld {
    public func candidatePairs() throws -> [CollisionPair] {
        var pairIndex = Set<CollisionPair>(
            minimumCapacity:
                min(
                    limits.broadphaseCandidatePairsPerTick,
                    16_384
                )
        )
        var pairs: [CollisionPair] = []
        pairs.reserveCapacity(
            min(
                limits.broadphaseCandidatePairsPerTick,
                16_384
            )
        )
        for slots in cellBuckets.values {
            guard slots.count > 1 else {
                continue
            }
            for firstIndex in 0 ..< slots.count - 1 {
                for secondIndex in firstIndex + 1 ..< slots.count {
                    let pair = CollisionPair(
                        bodies[slots[firstIndex]].entity,
                        bodies[slots[secondIndex]].entity
                    )
                    guard pairIndex.insert(pair).inserted else {
                        continue
                    }
                    pairs.append(pair)
                    guard pairIndex.count
                            <= limits.broadphaseCandidatePairsPerTick
                    else {
                        throw EngineCapacityError(
                            resource:
                                .broadphaseCandidatePairsPerTick,
                            limit:
                                limits
                                    .broadphaseCandidatePairsPerTick,
                            attempted:
                                limits
                                    .broadphaseCandidatePairsPerTick
                                    + 1
                        )
                    }
                }
            }
        }
        pairs.sort()
        return pairs
    }

    public func resolvedPairs(
        iterationsPerPair: Int
    ) throws -> [CollisionPair] {
        try validateIterationsPerPair(iterationsPerPair)
        return try resolvedPairs(
            from: candidatePairs(),
            iterationsPerPair: iterationsPerPair
        )
    }

    package func resolvedPairs(
        from candidates: [CollisionPair],
        iterationsPerPair: Int
    ) throws -> [CollisionPair] {
        try validateIterationsPerPair(iterationsPerPair)

        var resolved: [CollisionPair] = []
        for pair in Self.canonicalCandidates(candidates) {
            guard let first = body(for: pair.first),
                  let second = body(for: pair.second),
                  try Self.overlaps(first.shape, second.shape)
            else {
                continue
            }
            let attempted = resolved.count + 1
            guard attempted <= limits.resolvedCollisionPairsPerTick else {
                throw EngineCapacityError(
                    resource: .resolvedCollisionPairsPerTick,
                    limit: limits.resolvedCollisionPairsPerTick,
                    attempted: attempted
                )
            }
            resolved.append(pair)
        }
        return resolved
    }

    static func canonicalCandidates(
        _ candidates: [CollisionPair]
    ) -> [CollisionPair] {
        guard candidates.count > 1 else {
            return candidates
        }
        for index in 1 ..< candidates.count
        where !(candidates[index - 1] < candidates[index])
        {
            return Array(Set(candidates)).sorted()
        }
        return candidates
    }

    func validateIterationsPerPair(
        _ iterationsPerPair: Int
    ) throws {
        guard iterationsPerPair >= 0 else {
            throw CollisionWorldError.invalidLimit(
                resource: .solverIterationsPerPair,
                value: iterationsPerPair
            )
        }
        guard iterationsPerPair <= limits.solverIterationsPerPair else {
            throw EngineCapacityError(
                resource: .solverIterationsPerPair,
                limit: limits.solverIterationsPerPair,
                attempted: iterationsPerPair
            )
        }
    }
}
