import XCTest
@testable import GameRealtimeSimulationKit

final class CollisionTests: XCTestCase {
    func testSweptProjectileFindsBoundaryHit() throws {
        var boxWorld = try CollisionWorld(
            limits: makeLimits(),
            cellSize: FixedPoint(rawValue: 1_024)
        )
        let box = EntityHandle(index: 9, generation: 0)
        try boxWorld.insertAABB(
            entity: box,
            center: vector(5_000, 0),
            halfExtents: vector(1_000, 1_000)
        )

        let boxHit = try XCTUnwrap(
            boxWorld.sweptSegment(
                from: vector(0, 0),
                to: vector(10_000, 0),
                radius: FixedPoint(rawValue: 500)
            )
        )
        XCTAssertEqual(boxHit.entity, box)
        XCTAssertEqual(
            boxHit.fraction,
            try CollisionHitFraction(numerator: 7, denominator: 20)
        )

        var circleWorld = try CollisionWorld(
            limits: makeLimits(),
            cellSize: FixedPoint(rawValue: 1_024)
        )
        let circle = EntityHandle(index: 4, generation: 0)
        try circleWorld.insertCircle(
            entity: circle,
            center: vector(5_000, 0),
            radius: FixedPoint(rawValue: 1_000)
        )

        let circleHit = try XCTUnwrap(
            circleWorld.sweptSegment(
                from: vector(0, 0),
                to: vector(10_000, 0),
                radius: FixedPoint(rawValue: 0)
            )
        )
        XCTAssertEqual(circleHit.entity, circle)
        XCTAssertEqual(
            circleHit.fraction,
            try CollisionHitFraction(numerator: 2, denominator: 5)
        )
    }

    func testDiscreteCircleAndAABBBoundariesAreInclusive() throws {
        XCTAssertTrue(
            try CollisionWorld.circlesOverlap(
                centerA: vector(0, 0),
                radiusA: FixedPoint(rawValue: 5),
                centerB: vector(10, 0),
                radiusB: FixedPoint(rawValue: 5)
            )
        )
        XCTAssertFalse(
            try CollisionWorld.circlesOverlap(
                centerA: vector(0, 0),
                radiusA: FixedPoint(rawValue: 5),
                centerB: vector(11, 0),
                radiusB: FixedPoint(rawValue: 5)
            )
        )
        XCTAssertTrue(
            try CollisionWorld.aabbsOverlap(
                centerA: vector(0, 0),
                halfExtentsA: vector(5, 5),
                centerB: vector(10, 0),
                halfExtentsB: vector(5, 5)
            )
        )
        XCTAssertTrue(
            try CollisionWorld.circleOverlapsAABB(
                circleCenter: vector(10, 0),
                radius: FixedPoint(rawValue: 5),
                aabbCenter: vector(0, 0),
                halfExtents: vector(5, 5)
            )
        )
        XCTAssertFalse(
            try CollisionWorld.circleOverlapsAABB(
                circleCenter: vector(11, 0),
                radius: FixedPoint(rawValue: 5),
                aabbCenter: vector(0, 0),
                halfExtents: vector(5, 5)
            )
        )
    }

    func testPairsAndSweptTiesUseStableEntityIndexOrder() throws {
        let low = EntityHandle(index: 2, generation: 8)
        let high = EntityHandle(index: 20, generation: 1)
        XCTAssertEqual(
            CollisionPair(high, low),
            CollisionPair(low, high)
        )
        XCTAssertEqual(CollisionPair(high, low).minIndex, low.index)
        XCTAssertEqual(CollisionPair(high, low).maxIndex, high.index)

        var forward = try CollisionWorld(
            limits: makeLimits(),
            cellSize: FixedPoint(rawValue: 1_024)
        )
        var reverse = try CollisionWorld(
            limits: makeLimits(),
            cellSize: FixedPoint(rawValue: 1_024)
        )
        for entity in [high, low] {
            try forward.insertAABB(
                entity: entity,
                center: vector(3_000, 0),
                halfExtents: vector(400, 400)
            )
        }
        for entity in [low, high] {
            try reverse.insertAABB(
                entity: entity,
                center: vector(3_000, 0),
                halfExtents: vector(400, 400)
            )
        }

        XCTAssertEqual(
            try forward.candidatePairs(),
            [CollisionPair(low, high)]
        )
        XCTAssertEqual(
            try reverse.candidatePairs(),
            try forward.candidatePairs()
        )
        XCTAssertEqual(
            try forward.sweptSegment(
                from: vector(0, 0),
                to: vector(6_000, 0),
                radius: FixedPoint(rawValue: 0)
            )?.entity,
            low
        )
    }

    func testOccupiedCandidateResolvedAndIterationLimitsAreTypedAndAtomic() throws {
        var occupiedWorld = try CollisionWorld(
            limits: makeLimits(occupiedCells: 1),
            cellSize: FixedPoint(rawValue: 10)
        )
        XCTAssertThrowsError(
            try occupiedWorld.insertAABB(
                entity: EntityHandle(index: 1, generation: 0),
                center: vector(10, 0),
                halfExtents: vector(10, 0)
            )
        ) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .broadphaseOccupiedCells,
                    limit: 1,
                    attempted: 2
                )
            )
        }
        XCTAssertEqual(occupiedWorld.bodyCount, 0)
        XCTAssertEqual(occupiedWorld.occupiedCellCount, 0)

        var candidateWorld = try CollisionWorld(
            limits: makeLimits(candidatePairs: 2),
            cellSize: FixedPoint(rawValue: 100)
        )
        try insertThreeOverlappingBodies(into: &candidateWorld)
        XCTAssertThrowsError(try candidateWorld.candidatePairs()) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .broadphaseCandidatePairsPerTick,
                    limit: 2,
                    attempted: 3
                )
            )
        }
        XCTAssertEqual(candidateWorld.bodyCount, 3)

        var resolvedWorld = try CollisionWorld(
            limits: makeLimits(resolvedPairs: 2),
            cellSize: FixedPoint(rawValue: 100)
        )
        try insertThreeOverlappingBodies(into: &resolvedWorld)
        XCTAssertThrowsError(
            try resolvedWorld.resolvedPairs(iterationsPerPair: 1)
        ) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .resolvedCollisionPairsPerTick,
                    limit: 2,
                    attempted: 3
                )
            )
        }
        XCTAssertThrowsError(
            try resolvedWorld.resolvedPairs(iterationsPerPair: 5)
        ) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .solverIterationsPerPair,
                    limit: 4,
                    attempted: 5
                )
            )
        }
        XCTAssertEqual(resolvedWorld.bodyCount, 3)
    }

    func testSpatialBucketsPreserveDedupeRollbackAndSweptNearest() throws {
        var multiCellWorld = try CollisionWorld(
            limits: makeLimits(),
            cellSize: FixedPoint(rawValue: 100)
        )
        let low = EntityHandle(index: 2, generation: 0)
        let high = EntityHandle(index: 9, generation: 0)
        for entity in [high, low] {
            try multiCellWorld.insertAABB(
                entity: entity,
                center: vector(100, 100),
                halfExtents: vector(100, 100)
            )
        }
        XCTAssertEqual(
            try multiCellWorld.candidatePairs(),
            [CollisionPair(low, high)]
        )
        let candidates = try multiCellWorld.candidatePairs()
        XCTAssertEqual(
            try multiCellWorld.resolvedPairs(
                from: candidates,
                iterationsPerPair: 1
            ),
            [CollisionPair(low, high)]
        )
        XCTAssertEqual(
            try multiCellWorld.resolvedPairs(iterationsPerPair: 1),
            try multiCellWorld.resolvedPairs(
                from: candidates,
                iterationsPerPair: 1
            )
        )

        var rollbackWorld = try CollisionWorld(
            limits: makeLimits(occupiedCells: 2),
            cellSize: FixedPoint(rawValue: 100)
        )
        try rollbackWorld.insertCircle(
            entity: low,
            center: vector(0, 0),
            radius: FixedPoint(rawValue: 0)
        )
        XCTAssertThrowsError(
            try rollbackWorld.insertAABB(
                entity: high,
                center: vector(200, 0),
                halfExtents: vector(100, 0)
            )
        ) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .broadphaseOccupiedCells,
                    limit: 2,
                    attempted: 3
                )
            )
        }
        XCTAssertEqual(rollbackWorld.bodyCount, 1)
        XCTAssertEqual(rollbackWorld.occupiedCellCount, 1)

        var hugeWorld = try CollisionWorld(
            limits: makeLimits(occupiedCells: 2),
            cellSize: FixedPoint(rawValue: 1)
        )
        XCTAssertThrowsError(
            try hugeWorld.insertAABB(
                entity: low,
                center: vector(0, 0),
                halfExtents: vector(.max, .max)
            )
        ) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .broadphaseOccupiedCells,
                    limit: 2,
                    attempted: 3
                )
            )
        }
        XCTAssertEqual(hugeWorld.bodyCount, 0)
        XCTAssertEqual(hugeWorld.occupiedCellCount, 0)

        var sweptWorld = try CollisionWorld(
            limits: makeLimits(),
            cellSize: FixedPoint(rawValue: 1_024)
        )
        try sweptWorld.insertCircle(
            entity: low,
            center: vector(0, 0),
            radius: FixedPoint(rawValue: 0)
        )
        let target = EntityHandle(index: 20, generation: 0)
        try sweptWorld.insertAABB(
            entity: target,
            center: vector(1_000_000, 0),
            halfExtents: vector(2_000, 100)
        )
        let hit = try XCTUnwrap(
            sweptWorld.sweptSegment(
                from: vector(997_999, 0),
                to: vector(1_002_001, 0),
                radius: FixedPoint(rawValue: 0)
            )
        )
        XCTAssertEqual(hit.entity, target)
    }

    func testProvidedCandidatesCanonicalizeBeforeResolvedCapacity() throws {
        var world = try CollisionWorld(
            limits: makeLimits(resolvedPairs: 3),
            cellSize: FixedPoint(rawValue: 100)
        )
        try insertThreeOverlappingBodies(into: &world)
        let firstSecond = CollisionPair(
            EntityHandle(index: 1, generation: 0),
            EntityHandle(index: 2, generation: 0)
        )
        let firstThird = CollisionPair(
            EntityHandle(index: 1, generation: 0),
            EntityHandle(index: 3, generation: 0)
        )
        let secondThird = CollisionPair(
            EntityHandle(index: 2, generation: 0),
            EntityHandle(index: 3, generation: 0)
        )
        let reversedWithDuplicates = [
            secondThird,
            firstThird,
            secondThird,
            firstSecond,
            firstThird,
            firstSecond,
        ]
        XCTAssertEqual(
            try world.resolvedPairs(
                from: reversedWithDuplicates,
                iterationsPerPair: 1
            ),
            [firstSecond, firstThird, secondThird]
        )

        var limited = try CollisionWorld(
            limits: makeLimits(resolvedPairs: 2),
            cellSize: FixedPoint(rawValue: 100)
        )
        try insertThreeOverlappingBodies(into: &limited)
        XCTAssertThrowsError(
            try limited.resolvedPairs(
                from: reversedWithDuplicates,
                iterationsPerPair: 1
            )
        ) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .resolvedCollisionPairsPerTick,
                    limit: 2,
                    attempted: 3
                )
            )
        }
    }

    private func insertThreeOverlappingBodies(
        into world: inout CollisionWorld
    ) throws {
        for index in UInt32(1) ... UInt32(3) {
            try world.insertAABB(
                entity: EntityHandle(index: index, generation: 0),
                center: vector(10, 10),
                halfExtents: vector(4, 4)
            )
        }
    }

    private func vector(_ x: Int32, _ y: Int32) -> FixedVector2 {
        FixedVector2(
            x: FixedPoint(rawValue: x),
            y: FixedPoint(rawValue: y)
        )
    }

    private func makeLimits(
        occupiedCells: Int = 256,
        candidatePairs: Int = 256,
        resolvedPairs: Int = 256
    ) -> RealtimeLimits {
        return RealtimeLimits.standardV1.withCollision(
            broadphaseOccupiedCells: occupiedCells,
            broadphaseCandidatePairsPerTick: candidatePairs,
            resolvedCollisionPairsPerTick: resolvedPairs,
            solverIterationsPerPair: 4
        )
    }
}
