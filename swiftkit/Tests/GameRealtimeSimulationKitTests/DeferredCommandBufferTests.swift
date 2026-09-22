import XCTest
@testable import GameRealtimeSimulationKit

final class DeferredCommandBufferTests: XCTestCase {
    func testCommandsSortByStageSystemSequence() throws {
        let entity = EntityHandle(index: 7, generation: 2)
        let position = vector(12, -8)
        let commands: [(CommandKey, DeferredCommand)] = [
            (
                CommandKey(stage: 4, systemOrder: 2, sequence: 1),
                .setPosition(entity, position)
            ),
            (
                CommandKey(stage: 2, systemOrder: 9, sequence: 3),
                .spawn(kind: 30)
            ),
            (
                CommandKey(stage: 2, systemOrder: 1, sequence: 8),
                .spawn(kind: 10)
            ),
            (
                CommandKey(stage: 2, systemOrder: 1, sequence: 2),
                .despawn(entity)
            ),
        ]
        var forward = try DeferredCommandBuffer(limits: makeLimits())
        var reverse = try DeferredCommandBuffer(limits: makeLimits())

        for (key, command) in commands {
            try forward.enqueue(command, key: key)
        }
        for (key, command) in commands.reversed() {
            try reverse.enqueue(command, key: key)
        }

        let expected = [
            CommandKey(stage: 2, systemOrder: 1, sequence: 2),
            CommandKey(stage: 2, systemOrder: 1, sequence: 8),
            CommandKey(stage: 2, systemOrder: 9, sequence: 3),
            CommandKey(stage: 4, systemOrder: 2, sequence: 1),
        ]
        XCTAssertEqual(forward.orderedCommands.map(\.key), expected)
        XCTAssertEqual(reverse.orderedCommands, forward.orderedCommands)
    }

    func testFlushAppliesSpawnPositionAndDespawnAtomically() throws {
        var store = try EntityStore(limits: makeLimits(totalEntities: 4))
        let retained = try store.spawn()
        var buffer = try DeferredCommandBuffer(
            limits: makeLimits(totalEntities: 4)
        )
        try buffer.enqueue(
            .spawn(kind: 91),
            key: CommandKey(stage: 1, systemOrder: 2, sequence: 0)
        )
        try buffer.enqueue(
            .setPosition(retained, vector(40, -20)),
            key: CommandKey(stage: 1, systemOrder: 1, sequence: 1)
        )

        let result = try buffer.flush(into: &store)

        XCTAssertEqual(result.spawned.count, 1)
        XCTAssertEqual(result.spawned[0].kind, 91)
        XCTAssertEqual(store.queryAll(), [retained, result.spawned[0].entity])
        XCTAssertEqual(
            try store.component(
                kind: DeferredCommandBuffer.positionComponentKind,
                for: retained
            ),
            .vector(vector(40, -20))
        )
        XCTAssertEqual(
            try store.component(
                kind: DeferredCommandBuffer.entityKindComponentKind,
                for: result.spawned[0].entity
            ),
            .unsigned(91)
        )
        XCTAssertTrue(buffer.isEmpty)
    }

    func testConflictMatrixRejectsWithoutLastWriteWins() throws {
        let entity = EntityHandle(index: 3, generation: 4)
        let variants: [[DeferredCommand]] = [
            [.despawn(entity), .despawn(entity)],
            [.setPosition(entity, vector(1, 1)), .despawn(entity)],
            [.despawn(entity), .setPosition(entity, vector(1, 1))],
            [
                .setPosition(entity, vector(1, 1)),
                .setPosition(entity, vector(2, 2)),
            ],
        ]

        for commands in variants {
            var store = try storeContaining(entity)
            let before = store
            var buffer = try DeferredCommandBuffer(limits: makeLimits())
            for (offset, command) in commands.enumerated() {
                try buffer.enqueue(
                    command,
                    key: CommandKey(
                        stage: UInt16(10 - offset),
                        systemOrder: UInt16(offset),
                        sequence: UInt32(offset)
                    )
                )
            }

            XCTAssertThrowsError(try buffer.flush(into: &store)) { error in
                XCTAssertEqual(
                    error as? DeferredCommandError,
                    .conflictingMutations(entity)
                )
            }
            XCTAssertEqual(store.queryAll(), before.queryAll())
            XCTAssertEqual(store.structureVersion, before.structureVersion)
            XCTAssertEqual(buffer.count, commands.count)
        }
    }

    func testStaleHandleAndDuplicateKeyFailClosed() throws {
        var store = try EntityStore(limits: makeLimits())
        let stale = try store.spawn()
        try store.despawn(stale)
        let structureVersion = store.structureVersion
        var buffer = try DeferredCommandBuffer(limits: makeLimits())
        let key = CommandKey(stage: 1, systemOrder: 1, sequence: 1)
        try buffer.enqueue(.spawn(kind: 1), key: key)

        XCTAssertThrowsError(try buffer.enqueue(.spawn(kind: 2), key: key)) {
            error in
            XCTAssertEqual(
                error as? DeferredCommandError,
                .duplicateKey(key)
            )
        }
        XCTAssertEqual(buffer.count, 1)

        try buffer.enqueue(
            .setPosition(stale, vector(9, 9)),
            key: CommandKey(stage: 2, systemOrder: 0, sequence: 0)
        )
        XCTAssertThrowsError(try buffer.flush(into: &store)) { error in
            XCTAssertEqual(
                error as? DeferredCommandError,
                .staleHandle(stale)
            )
        }
        XCTAssertEqual(store.queryAll(), [])
        XCTAssertEqual(store.structureVersion, structureVersion)
        XCTAssertEqual(buffer.count, 2)
    }

    func testCommandCapacityIsTypedAndAtomic() throws {
        var buffer = try DeferredCommandBuffer(
            limits: makeLimits(deferredCommandsPerTick: 1)
        )
        try buffer.enqueue(
            .spawn(kind: 1),
            key: CommandKey(stage: 0, systemOrder: 0, sequence: 0)
        )
        let retained = buffer.orderedCommands

        XCTAssertThrowsError(
            try buffer.enqueue(
                .spawn(kind: 2),
                key: CommandKey(stage: 0, systemOrder: 0, sequence: 1)
            )
        ) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .deferredCommandsPerTick,
                    limit: 1,
                    attempted: 2
                )
            )
        }
        XCTAssertEqual(buffer.orderedCommands, retained)
    }

    func testFlushCapacityFailureKeepsStoreAndBufferUnchanged() throws {
        var store = try EntityStore(limits: makeLimits(totalEntities: 1))
        let retainedEntity = try store.spawn()
        let retainedVersion = store.structureVersion
        var buffer = try DeferredCommandBuffer(
            limits: makeLimits(totalEntities: 1)
        )
        try buffer.enqueue(
            .setPosition(retainedEntity, vector(3, 4)),
            key: CommandKey(stage: 0, systemOrder: 0, sequence: 0)
        )
        try buffer.enqueue(
            .spawn(kind: 99),
            key: CommandKey(stage: 1, systemOrder: 0, sequence: 0)
        )

        XCTAssertThrowsError(try buffer.flush(into: &store)) { error in
            XCTAssertEqual(
                error as? EngineCapacityError,
                EngineCapacityError(
                    resource: .entities,
                    limit: 1,
                    attempted: 2
                )
            )
        }
        XCTAssertEqual(store.queryAll(), [retainedEntity])
        XCTAssertEqual(store.structureVersion, retainedVersion)
        XCTAssertEqual(buffer.count, 2)
        XCTAssertThrowsError(
            try store.component(
                kind: DeferredCommandBuffer.positionComponentKind,
                for: retainedEntity
            )
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .unregisteredComponentKind(
                    DeferredCommandBuffer.positionComponentKind
                )
            )
        }
    }

    func testThousandUniqueTargetsUseIndexedKeysAndRemainAtomic() throws {
        let limits = makeLimits(
            totalEntities: 1_024,
            deferredCommandsPerTick: 1_024
        )
        var store = try EntityStore(limits: limits)
        let entities = try (0 ..< 1_024).map { _ in
            try store.spawn()
        }
        let originalEntities = store.queryAll()
        var buffer = try DeferredCommandBuffer(limits: limits)
        for (offset, entity) in entities.enumerated() {
            try buffer.enqueue(
                .setPosition(
                    entity,
                    vector(Int32(offset), Int32(-offset))
                ),
                key: CommandKey(
                    stage: 1,
                    systemOrder: 1,
                    sequence: UInt32(offset)
                )
            )
        }
        XCTAssertEqual(buffer.indexedKeyCount, 1_024)

        let duplicate = CommandKey(
            stage: 1,
            systemOrder: 1,
            sequence: 1_023
        )
        XCTAssertThrowsError(
            try buffer.enqueue(.spawn(kind: 1), key: duplicate)
        ) { error in
            XCTAssertEqual(
                error as? DeferredCommandError,
                .duplicateKey(duplicate)
            )
        }
        XCTAssertEqual(buffer.count, 1_024)
        XCTAssertEqual(buffer.indexedKeyCount, 1_024)

        _ = try buffer.flush(into: &store)
        XCTAssertEqual(store.queryAll(), originalEntities)
        XCTAssertEqual(
            try store.stableQuery(
                requiring: [
                    DeferredCommandBuffer.positionComponentKind
                ]
            ).entities,
            originalEntities
        )
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertEqual(buffer.indexedKeyCount, 0)

        let retainedStore = store
        var conflicting = try DeferredCommandBuffer(limits: limits)
        try conflicting.enqueue(
            .setPosition(entities[0], vector(1, 1)),
            key: CommandKey(stage: 0, systemOrder: 0, sequence: 0)
        )
        try conflicting.enqueue(
            .despawn(entities[0]),
            key: CommandKey(stage: 0, systemOrder: 0, sequence: 1)
        )
        XCTAssertThrowsError(try conflicting.flush(into: &store)) {
            error in
            XCTAssertEqual(
                error as? DeferredCommandError,
                .conflictingMutations(entities[0])
            )
        }
        XCTAssertEqual(store.queryAll(), retainedStore.queryAll())
        XCTAssertEqual(
            store.structureVersion,
            retainedStore.structureVersion
        )
        XCTAssertEqual(conflicting.count, 2)
        XCTAssertEqual(conflicting.indexedKeyCount, 2)
    }

    private func vector(_ x: Int32, _ y: Int32) -> FixedVector2 {
        FixedVector2(
            x: FixedPoint(rawValue: x),
            y: FixedPoint(rawValue: y)
        )
    }

    private func storeContaining(_ expected: EntityHandle) throws -> EntityStore {
        var store = try EntityStore(limits: makeLimits(totalEntities: 8))
        var current = try store.spawn()
        while current.index < expected.index {
            current = try store.spawn()
        }
        if expected.generation > 0 {
            try store.despawn(current)
            for generation in 1 ... expected.generation {
                current = try store.spawn()
                if generation < expected.generation {
                    try store.despawn(current)
                }
            }
        }
        XCTAssertEqual(current, expected)
        return store
    }

    private func makeLimits(
        totalEntities: Int = 8,
        deferredCommandsPerTick: Int = 32
    ) -> RealtimeLimits {
        return RealtimeLimits.standardV1
            .withEntities(totalEntities: totalEntities)
            .withCommands(deferredCommandsPerTick: deferredCommandsPerTick)
    }
}
