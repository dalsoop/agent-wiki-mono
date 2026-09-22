import XCTest
@testable import GameRealtimeStateKit

final class EntityStoreTests: XCTestCase {
    func testRecycleRejectsStaleHandleAndQueryIsStable() throws {
        var store = try EntityStore(limits: .standardV1)
        let old = try store.spawn()
        _ = try store.despawn(old)
        let fresh = try store.spawn()
        XCTAssertEqual(old.index, fresh.index)
        XCTAssertNotEqual(old.generation, fresh.generation)
        XCTAssertThrowsError(try store.require(old))
        XCTAssertEqual(
            store.queryAll().map(\.index),
            store.queryAll().map(\.index).sorted()
        )
    }

    func testMultipleNonSequentialDespawnsRecycleLowestIndex() throws {
        var store = try EntityStore(limits: makeLimits())
        let handles = try (0..<5).map { _ in try store.spawn() }

        try store.despawn(handles[3])
        try store.despawn(handles[1])

        XCTAssertEqual(
            try store.spawn(),
            EntityHandle(index: handles[1].index, generation: 1)
        )
        XCTAssertEqual(
            try store.spawn(),
            EntityHandle(index: handles[3].index, generation: 1)
        )
    }

    func testRequireThrowsExactStaleHandleError() throws {
        var store = try EntityStore(limits: makeLimits())
        let stale = try store.spawn()
        try store.despawn(stale)

        XCTAssertThrowsError(try store.require(stale)) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .staleHandle(stale)
            )
        }
    }

    func testStructureVersionAndCacheTrackMembershipWhileValueReplaceDoesNot() throws {
        var store = try EntityStore(limits: makeLimits())
        let kind = ComponentKind(rawValue: 7)
        let entity = try store.spawn()
        try store.registerComponentKind(kind)
        let beforeAttach = try store.stableQuery(requiring: [kind])
        let versionBeforeAttach = store.structureVersion

        XCTAssertNil(
            try store.attachComponent(.signed(10), kind: kind, to: entity)
        )
        let afterAttach = try store.stableQuery(requiring: [kind])
        XCTAssertEqual(store.structureVersion, versionBeforeAttach + 1)
        XCTAssertEqual(beforeAttach.entities, [])
        XCTAssertEqual(afterAttach.structureVersion, store.structureVersion)
        XCTAssertEqual(afterAttach.entities, [entity])

        let versionBeforeReplace = store.structureVersion
        XCTAssertEqual(
            try store.attachComponent(.signed(20), kind: kind, to: entity),
            .signed(10)
        )
        let afterReplace = try store.stableQuery(requiring: [kind])
        XCTAssertEqual(store.structureVersion, versionBeforeReplace)
        XCTAssertEqual(afterReplace.structureVersion, afterAttach.structureVersion)
        XCTAssertEqual(afterReplace.entities, [entity])

        XCTAssertEqual(
            try store.removeComponent(kind: kind, from: entity),
            .signed(20)
        )
        let afterRemove = try store.stableQuery(requiring: [kind])
        XCTAssertEqual(store.structureVersion, versionBeforeReplace + 1)
        XCTAssertEqual(afterRemove.structureVersion, store.structureVersion)
        XCTAssertEqual(afterRemove.entities, [])
    }

    func testEntityCapacityFailureAtLimitIsTypedAndAtomic() throws {
        var store = try EntityStore(limits: makeLimits(totalEntities: 2))
        XCTAssertEqual(try store.spawn().index, 0)
        XCTAssertEqual(try store.spawn().index, 1)
        let versionAtLimit = store.structureVersion
        let queryAtLimit = store.stableQuery()

        XCTAssertThrowsError(try store.spawn()) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .capacityExceeded(limit: 2)
            )
        }
        XCTAssertEqual(store.structureVersion, versionAtLimit)
        XCTAssertEqual(store.stableQuery().structureVersion, queryAtLimit.structureVersion)
        XCTAssertEqual(store.queryAll(), queryAtLimit.entities)
    }

    func testGenerationWrapFromRestorationStateIsTypedAndAtomic() throws {
        let entity = EntityHandle(index: 0, generation: UInt32.max)
        let restoration = EntityStoreRestorationState(
            structureVersion: 41,
            generations: [UInt32.max],
            occupied: [true],
            recycledIndices: [],
            registeredComponentKinds: [],
            components: []
        )
        var store = try EntityStore(
            limits: makeLimits(totalEntities: 1),
            restoring: restoration
        )
        let queryBeforeFailure = store.stableQuery()

        XCTAssertThrowsError(try store.despawn(entity)) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .generationWrapped
            )
        }
        XCTAssertEqual(try store.require(entity), entity)
        XCTAssertEqual(store.structureVersion, 41)
        XCTAssertEqual(store.stableQuery().structureVersion, queryBeforeFailure.structureVersion)
        XCTAssertEqual(store.queryAll(), queryBeforeFailure.entities)
    }

    func testComponentRegistrationAttachReplaceRemoveAndLookup() throws {
        var store = try EntityStore(limits: makeLimits())
        let kind = ComponentKind(rawValue: 3)
        let entity = try store.spawn()

        XCTAssertThrowsError(
            try store.attachComponent(.unsigned(1), kind: kind, to: entity)
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .unregisteredComponentKind(kind)
            )
        }

        try store.registerComponentKind(kind)
        XCTAssertNil(
            try store.attachComponent(.unsigned(1), kind: kind, to: entity)
        )
        XCTAssertEqual(
            try store.component(kind: kind, for: entity),
            .unsigned(1)
        )
        XCTAssertEqual(
            try store.attachComponent(.fixed(FixedPoint(rawValue: 2_048)), kind: kind, to: entity),
            .unsigned(1)
        )
        XCTAssertEqual(
            try store.component(kind: kind, for: entity),
            .fixed(FixedPoint(rawValue: 2_048))
        )
        XCTAssertEqual(
            try store.removeComponent(kind: kind, from: entity),
            .fixed(FixedPoint(rawValue: 2_048))
        )
        XCTAssertNil(try store.component(kind: kind, for: entity))
        XCTAssertNil(try store.removeComponent(kind: kind, from: entity))

        try store.despawn(entity)
        XCTAssertThrowsError(
            try store.component(kind: kind, for: entity)
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .staleHandle(entity)
            )
        }
    }

    func testRequiredComponentQueryIsStable() throws {
        var store = try EntityStore(limits: makeLimits())
        let health = ComponentKind(rawValue: 10)
        let armor = ComponentKind(rawValue: 20)
        try store.registerComponentKind(health)
        try store.registerComponentKind(armor)
        let entities = try (0..<4).map { _ in try store.spawn() }

        _ = try store.attachComponent(.signed(30), kind: health, to: entities[3])
        _ = try store.attachComponent(.signed(10), kind: health, to: entities[1])
        _ = try store.attachComponent(.unsigned(1), kind: armor, to: entities[2])
        _ = try store.attachComponent(.unsigned(2), kind: armor, to: entities[1])

        XCTAssertEqual(
            try store.stableQuery(requiring: [health]).entities.map(\.index),
            [1, 3]
        )
        XCTAssertEqual(
            try store.stableQuery(requiring: [armor, health]).entities.map(\.index),
            [1]
        )
        XCTAssertEqual(
            try store.stableQuery(requiring: [health, armor, health]).entities.map(\.index),
            [1]
        )
    }

    func testRegisteredComponentKindCapacityIsTypedAndAtomic() throws {
        var store = try EntityStore(
            limits: makeLimits(registeredComponentKinds: 1)
        )
        let first = ComponentKind(rawValue: 1)
        let rejected = ComponentKind(rawValue: 2)
        try store.registerComponentKind(first)
        let versionAtLimit = store.structureVersion

        XCTAssertThrowsError(
            try store.registerComponentKind(rejected)
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .registeredComponentKindsCapacityExceeded(limit: 1)
            )
        }
        XCTAssertEqual(store.structureVersion, versionAtLimit)
        try store.registerComponentKind(first)
        XCTAssertEqual(store.structureVersion, versionAtLimit)
    }

    func testEntitiesPerKindCapacityIsTypedAndAtomic() throws {
        var store = try EntityStore(
            limits: makeLimits(
                entitiesPerKind: 1,
                componentSlotsPerKind: 2
            )
        )
        let kind = ComponentKind(rawValue: 1)
        try store.registerComponentKind(kind)
        let first = try store.spawn()
        let rejected = try store.spawn()
        _ = try store.attachComponent(.signed(1), kind: kind, to: first)
        let versionAtLimit = store.structureVersion

        XCTAssertThrowsError(
            try store.attachComponent(.signed(2), kind: kind, to: rejected)
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .entitiesPerKindCapacityExceeded(kind: kind, limit: 1)
            )
        }
        XCTAssertEqual(store.structureVersion, versionAtLimit)
        XCTAssertEqual(try store.component(kind: kind, for: first), .signed(1))
        XCTAssertNil(try store.component(kind: kind, for: rejected))
    }

    func testComponentSlotsPerKindCapacityIsTypedAndAtomic() throws {
        var store = try EntityStore(
            limits: makeLimits(
                entitiesPerKind: 2,
                componentSlotsPerKind: 1
            )
        )
        let kind = ComponentKind(rawValue: 1)
        try store.registerComponentKind(kind)
        let first = try store.spawn()
        let rejected = try store.spawn()
        _ = try store.attachComponent(.signed(1), kind: kind, to: first)
        let versionAtLimit = store.structureVersion

        XCTAssertThrowsError(
            try store.attachComponent(.signed(2), kind: kind, to: rejected)
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .componentSlotsPerKindCapacityExceeded(kind: kind, limit: 1)
            )
        }
        XCTAssertEqual(store.structureVersion, versionAtLimit)
        XCTAssertEqual(try store.component(kind: kind, for: first), .signed(1))
        XCTAssertNil(try store.component(kind: kind, for: rejected))
    }

    func testStableQueryCacheCapacityIsTypedAndAtomic() throws {
        var store = try EntityStore(
            limits: makeLimits(stableQueryCacheEntries: 1)
        )
        let first = ComponentKind(rawValue: 1)
        let rejected = ComponentKind(rawValue: 2)
        try store.registerComponentKind(first)
        try store.registerComponentKind(rejected)
        let entity = try store.spawn()
        _ = try store.attachComponent(.signed(1), kind: first, to: entity)
        _ = try store.attachComponent(.signed(2), kind: rejected, to: entity)
        let cached = try store.stableQuery(requiring: [first])
        let versionAtLimit = store.structureVersion

        XCTAssertThrowsError(
            try store.stableQuery(requiring: [rejected])
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .stableQueryCacheCapacityExceeded(limit: 1)
            )
        }
        XCTAssertEqual(store.structureVersion, versionAtLimit)
        XCTAssertEqual(
            try store.stableQuery(requiring: [first]).entities,
            cached.entities
        )
    }

    func testShuffledAttachKeepsKindAndMultiKindQueriesAscending() throws {
        var store = try EntityStore(limits: makeLimits())
        let movement = ComponentKind(rawValue: 30)
        let health = ComponentKind(rawValue: 10)
        let armor = ComponentKind(rawValue: 20)
        try store.registerComponentKind(movement)
        try store.registerComponentKind(health)
        try store.registerComponentKind(armor)
        let entities = try (0..<6).map { _ in try store.spawn() }

        for position in [5, 1, 4, 0] {
            _ = try store.attachComponent(
                .signed(Int32(position)),
                kind: health,
                to: entities[position]
            )
        }
        for position in [4, 0, 3] {
            _ = try store.attachComponent(
                .unsigned(UInt32(position)),
                kind: armor,
                to: entities[position]
            )
        }
        for position in [5, 4, 0] {
            _ = try store.attachComponent(
                .fixed(FixedPoint(rawValue: Int32(position))),
                kind: movement,
                to: entities[position]
            )
        }

        XCTAssertEqual(
            try store.stableQuery(requiring: [health]).entities.map(\.index),
            [0, 1, 4, 5]
        )
        XCTAssertEqual(
            try store.stableQuery(requiring: [armor]).entities.map(\.index),
            [0, 3, 4]
        )
        XCTAssertEqual(
            try store.stableQuery(requiring: [health, armor]).entities.map(\.index),
            [0, 4]
        )
        XCTAssertEqual(
            try store.stableQuery(
                requiring: [movement, health, armor, health]
            ).entities.map(\.index),
            [0, 4]
        )
    }

    func testReplaceRemoveAndRecycleKeepExactMembership() throws {
        var store = try EntityStore(limits: makeLimits())
        let primary = ComponentKind(rawValue: 1)
        let secondary = ComponentKind(rawValue: 2)
        try store.registerComponentKind(primary)
        try store.registerComponentKind(secondary)
        let entities = try (0..<3).map { _ in try store.spawn() }
        for entity in entities.reversed() {
            _ = try store.attachComponent(
                .signed(Int32(entity.index)),
                kind: primary,
                to: entity
            )
        }
        _ = try store.attachComponent(
            .unsigned(11),
            kind: secondary,
            to: entities[1]
        )

        let versionBeforeReplace = store.structureVersion
        XCTAssertEqual(
            try store.attachComponent(.signed(100), kind: primary, to: entities[1]),
            .signed(1)
        )
        XCTAssertEqual(store.structureVersion, versionBeforeReplace)
        XCTAssertEqual(
            try store.removeComponent(kind: primary, from: entities[0]),
            .signed(0)
        )
        try store.despawn(entities[2])
        let recycled = try store.spawn()
        XCTAssertEqual(recycled.index, entities[2].index)
        XCTAssertNotEqual(recycled.generation, entities[2].generation)
        _ = try store.attachComponent(
            .unsigned(22),
            kind: secondary,
            to: recycled
        )
        _ = try store.attachComponent(
            .signed(200),
            kind: primary,
            to: recycled
        )

        XCTAssertEqual(
            try store.stableQuery(requiring: [primary]).entities,
            [entities[1], recycled]
        )
        XCTAssertEqual(
            try store.stableQuery(requiring: [secondary]).entities,
            [entities[1], recycled]
        )
        XCTAssertEqual(
            try store.component(kind: primary, for: entities[1]),
            .signed(100)
        )
        XCTAssertNil(try store.component(kind: primary, for: entities[0]))
        XCTAssertThrowsError(
            try store.component(kind: primary, for: entities[2])
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .staleHandle(entities[2])
            )
        }
    }

    func testPartitionedCapacityFailureRemainsAtomic() throws {
        var store = try EntityStore(
            limits: makeLimits(
                entitiesPerKind: 3,
                componentSlotsPerKind: 2
            )
        )
        let kind = ComponentKind(rawValue: 1)
        try store.registerComponentKind(kind)
        let entities = try (0..<4).map { _ in try store.spawn() }
        _ = try store.attachComponent(.signed(2), kind: kind, to: entities[2])
        _ = try store.attachComponent(.signed(0), kind: kind, to: entities[0])
        let queryAtLimit = try store.stableQuery(requiring: [kind])
        let versionAtLimit = store.structureVersion

        XCTAssertThrowsError(
            try store.attachComponent(.signed(1), kind: kind, to: entities[1])
        ) { error in
            XCTAssertEqual(
                error as? EntityHandleError,
                .componentSlotsPerKindCapacityExceeded(kind: kind, limit: 2)
            )
        }
        XCTAssertEqual(store.structureVersion, versionAtLimit)
        XCTAssertEqual(
            try store.stableQuery(requiring: [kind]).entities,
            queryAtLimit.entities
        )
        XCTAssertEqual(
            try store.component(kind: kind, for: entities[2]),
            .signed(2)
        )
        XCTAssertEqual(
            try store.component(kind: kind, for: entities[0]),
            .signed(0)
        )
        XCTAssertNil(try store.component(kind: kind, for: entities[1]))

        _ = try store.removeComponent(kind: kind, from: entities[0])
        XCTAssertNil(
            try store.attachComponent(.signed(1), kind: kind, to: entities[1])
        )
        XCTAssertEqual(
            try store.stableQuery(requiring: [kind]).entities.map(\.index),
            [1, 2]
        )
    }
}

private func makeLimits(
    totalEntities: Int = 8,
    entitiesPerKind: Int = 8,
    componentSlotsPerKind: Int = 8,
    registeredComponentKinds: Int = 8,
    stableQueryCacheEntries: Int = 8
) -> RealtimeLimits {
    return RealtimeLimits.standardV1.withEntities(
        totalEntities: totalEntities,
        entitiesPerKind: entitiesPerKind,
        componentSlotsPerKind: componentSlotsPerKind,
        registeredComponentKinds: registeredComponentKinds,
        stableQueryCacheEntries: stableQueryCacheEntries
    )
}
