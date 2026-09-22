public struct RealtimeLimits: Hashable, Codable, Sendable {
    public struct EntityCapacity: Hashable, Sendable {
        public var totalEntities: Int
        public var entitiesPerKind: Int
        public var componentSlotsPerKind: Int
        public var registeredComponentKinds: Int
        public var stableQueryCacheEntries: Int

        public init(
            totalEntities: Int,
            entitiesPerKind: Int,
            componentSlotsPerKind: Int,
            registeredComponentKinds: Int,
            stableQueryCacheEntries: Int
        ) {
            self.totalEntities = totalEntities
            self.entitiesPerKind = entitiesPerKind
            self.componentSlotsPerKind = componentSlotsPerKind
            self.registeredComponentKinds = registeredComponentKinds
            self.stableQueryCacheEntries = stableQueryCacheEntries
        }
    }

    public struct CommandCapacity: Hashable, Sendable {
        public var deferredCommandsPerTick: Int
        public var authorityEventsPerTick: Int
        public var queuedInputFrames: Int

        public init(
            deferredCommandsPerTick: Int,
            authorityEventsPerTick: Int,
            queuedInputFrames: Int
        ) {
            self.deferredCommandsPerTick = deferredCommandsPerTick
            self.authorityEventsPerTick = authorityEventsPerTick
            self.queuedInputFrames = queuedInputFrames
        }
    }

    public struct CollisionCapacity: Hashable, Sendable {
        public var broadphaseOccupiedCells: Int
        public var broadphaseCandidatePairsPerTick: Int
        public var resolvedCollisionPairsPerTick: Int
        public var solverIterationsPerPair: Int

        public init(
            broadphaseOccupiedCells: Int,
            broadphaseCandidatePairsPerTick: Int,
            resolvedCollisionPairsPerTick: Int,
            solverIterationsPerPair: Int
        ) {
            self.broadphaseOccupiedCells = broadphaseOccupiedCells
            self.broadphaseCandidatePairsPerTick = broadphaseCandidatePairsPerTick
            self.resolvedCollisionPairsPerTick = resolvedCollisionPairsPerTick
            self.solverIterationsPerPair = solverIterationsPerPair
        }
    }

    public struct PersistenceCapacity: Hashable, Sendable {
        public var checkpointRingLength: Int
        public var checkpointRingBytes: Int
        public var canonicalSnapshotBytes: Int
        public var replayInputFrames: Int
        public var outboundSnapshots: Int

        public init(
            checkpointRingLength: Int,
            checkpointRingBytes: Int,
            canonicalSnapshotBytes: Int,
            replayInputFrames: Int,
            outboundSnapshots: Int
        ) {
            self.checkpointRingLength = checkpointRingLength
            self.checkpointRingBytes = checkpointRingBytes
            self.canonicalSnapshotBytes = canonicalSnapshotBytes
            self.replayInputFrames = replayInputFrames
            self.outboundSnapshots = outboundSnapshots
        }
    }

    public let totalEntities: Int
    public let entitiesPerKind: Int
    public let componentSlotsPerKind: Int
    public let registeredComponentKinds: Int
    public let stableQueryCacheEntries: Int
    public let deferredCommandsPerTick: Int
    public let authorityEventsPerTick: Int
    public let queuedInputFrames: Int
    public let broadphaseOccupiedCells: Int
    public let broadphaseCandidatePairsPerTick: Int
    public let resolvedCollisionPairsPerTick: Int
    public let solverIterationsPerPair: Int
    public let checkpointRingLength: Int
    public let checkpointRingBytes: Int
    public let canonicalSnapshotBytes: Int
    public let replayInputFrames: Int
    public let outboundSnapshots: Int

    public init(
        entities: EntityCapacity,
        commands: CommandCapacity,
        collision: CollisionCapacity,
        persistence: PersistenceCapacity
    ) {
        self.totalEntities = entities.totalEntities
        self.entitiesPerKind = entities.entitiesPerKind
        self.componentSlotsPerKind = entities.componentSlotsPerKind
        self.registeredComponentKinds = entities.registeredComponentKinds
        self.stableQueryCacheEntries = entities.stableQueryCacheEntries
        self.deferredCommandsPerTick = commands.deferredCommandsPerTick
        self.authorityEventsPerTick = commands.authorityEventsPerTick
        self.queuedInputFrames = commands.queuedInputFrames
        self.broadphaseOccupiedCells = collision.broadphaseOccupiedCells
        self.broadphaseCandidatePairsPerTick = collision.broadphaseCandidatePairsPerTick
        self.resolvedCollisionPairsPerTick = collision.resolvedCollisionPairsPerTick
        self.solverIterationsPerPair = collision.solverIterationsPerPair
        self.checkpointRingLength = persistence.checkpointRingLength
        self.checkpointRingBytes = persistence.checkpointRingBytes
        self.canonicalSnapshotBytes = persistence.canonicalSnapshotBytes
        self.replayInputFrames = persistence.replayInputFrames
        self.outboundSnapshots = persistence.outboundSnapshots
    }

    public static let standardV1 = RealtimeLimits(
        entities: .init(
            totalEntities: 8_192,
            entitiesPerKind: 4_096,
            componentSlotsPerKind: 8_192,
            registeredComponentKinds: 128,
            stableQueryCacheEntries: 256
        ),
        commands: .init(
            deferredCommandsPerTick: 4_096,
            authorityEventsPerTick: 4_096,
            queuedInputFrames: 1_024
        ),
        collision: .init(
            broadphaseOccupiedCells: 16_384,
            broadphaseCandidatePairsPerTick: 65_536,
            resolvedCollisionPairsPerTick: 32_768,
            solverIterationsPerPair: 4
        ),
        persistence: .init(
            checkpointRingLength: 120,
            checkpointRingBytes: 64 * 1_024 * 1_024,
            canonicalSnapshotBytes: 512 * 1_024,
            replayInputFrames: 300_000,
            outboundSnapshots: 8
        )
    )

    public func withEntities(
        totalEntities: Int? = nil,
        entitiesPerKind: Int? = nil,
        componentSlotsPerKind: Int? = nil,
        registeredComponentKinds: Int? = nil,
        stableQueryCacheEntries: Int? = nil
    ) -> RealtimeLimits {
        RealtimeLimits(
            entities: .init(
                totalEntities: totalEntities ?? self.totalEntities,
                entitiesPerKind: entitiesPerKind ?? self.entitiesPerKind,
                componentSlotsPerKind: componentSlotsPerKind ?? self.componentSlotsPerKind,
                registeredComponentKinds:
                    registeredComponentKinds ?? self.registeredComponentKinds,
                stableQueryCacheEntries:
                    stableQueryCacheEntries ?? self.stableQueryCacheEntries
            ),
            commands: .init(
                deferredCommandsPerTick: deferredCommandsPerTick,
                authorityEventsPerTick: authorityEventsPerTick,
                queuedInputFrames: queuedInputFrames
            ),
            collision: .init(
                broadphaseOccupiedCells: broadphaseOccupiedCells,
                broadphaseCandidatePairsPerTick: broadphaseCandidatePairsPerTick,
                resolvedCollisionPairsPerTick: resolvedCollisionPairsPerTick,
                solverIterationsPerPair: solverIterationsPerPair
            ),
            persistence: .init(
                checkpointRingLength: checkpointRingLength,
                checkpointRingBytes: checkpointRingBytes,
                canonicalSnapshotBytes: canonicalSnapshotBytes,
                replayInputFrames: replayInputFrames,
                outboundSnapshots: outboundSnapshots
            )
        )
    }

    public func withCommands(deferredCommandsPerTick: Int? = nil) -> RealtimeLimits {
        RealtimeLimits(
            entities: .init(
                totalEntities: totalEntities,
                entitiesPerKind: entitiesPerKind,
                componentSlotsPerKind: componentSlotsPerKind,
                registeredComponentKinds: registeredComponentKinds,
                stableQueryCacheEntries: stableQueryCacheEntries
            ),
            commands: .init(
                deferredCommandsPerTick:
                    deferredCommandsPerTick ?? self.deferredCommandsPerTick,
                authorityEventsPerTick: authorityEventsPerTick,
                queuedInputFrames: queuedInputFrames
            ),
            collision: .init(
                broadphaseOccupiedCells: broadphaseOccupiedCells,
                broadphaseCandidatePairsPerTick: broadphaseCandidatePairsPerTick,
                resolvedCollisionPairsPerTick: resolvedCollisionPairsPerTick,
                solverIterationsPerPair: solverIterationsPerPair
            ),
            persistence: .init(
                checkpointRingLength: checkpointRingLength,
                checkpointRingBytes: checkpointRingBytes,
                canonicalSnapshotBytes: canonicalSnapshotBytes,
                replayInputFrames: replayInputFrames,
                outboundSnapshots: outboundSnapshots
            )
        )
    }

    public func withCollision(
        broadphaseOccupiedCells: Int? = nil,
        broadphaseCandidatePairsPerTick: Int? = nil,
        resolvedCollisionPairsPerTick: Int? = nil,
        solverIterationsPerPair: Int? = nil
    ) -> RealtimeLimits {
        RealtimeLimits(
            entities: .init(
                totalEntities: totalEntities,
                entitiesPerKind: entitiesPerKind,
                componentSlotsPerKind: componentSlotsPerKind,
                registeredComponentKinds: registeredComponentKinds,
                stableQueryCacheEntries: stableQueryCacheEntries
            ),
            commands: .init(
                deferredCommandsPerTick: deferredCommandsPerTick,
                authorityEventsPerTick: authorityEventsPerTick,
                queuedInputFrames: queuedInputFrames
            ),
            collision: .init(
                broadphaseOccupiedCells:
                    broadphaseOccupiedCells ?? self.broadphaseOccupiedCells,
                broadphaseCandidatePairsPerTick:
                    broadphaseCandidatePairsPerTick
                        ?? self.broadphaseCandidatePairsPerTick,
                resolvedCollisionPairsPerTick:
                    resolvedCollisionPairsPerTick ?? self.resolvedCollisionPairsPerTick,
                solverIterationsPerPair:
                    solverIterationsPerPair ?? self.solverIterationsPerPair
            ),
            persistence: .init(
                checkpointRingLength: checkpointRingLength,
                checkpointRingBytes: checkpointRingBytes,
                canonicalSnapshotBytes: canonicalSnapshotBytes,
                replayInputFrames: replayInputFrames,
                outboundSnapshots: outboundSnapshots
            )
        )
    }

    public func withPersistence(checkpointRingBytes: Int? = nil) -> RealtimeLimits {
        RealtimeLimits(
            entities: .init(
                totalEntities: totalEntities,
                entitiesPerKind: entitiesPerKind,
                componentSlotsPerKind: componentSlotsPerKind,
                registeredComponentKinds: registeredComponentKinds,
                stableQueryCacheEntries: stableQueryCacheEntries
            ),
            commands: .init(
                deferredCommandsPerTick: deferredCommandsPerTick,
                authorityEventsPerTick: authorityEventsPerTick,
                queuedInputFrames: queuedInputFrames
            ),
            collision: .init(
                broadphaseOccupiedCells: broadphaseOccupiedCells,
                broadphaseCandidatePairsPerTick: broadphaseCandidatePairsPerTick,
                resolvedCollisionPairsPerTick: resolvedCollisionPairsPerTick,
                solverIterationsPerPair: solverIterationsPerPair
            ),
            persistence: .init(
                checkpointRingLength: checkpointRingLength,
                checkpointRingBytes: checkpointRingBytes ?? self.checkpointRingBytes,
                canonicalSnapshotBytes: canonicalSnapshotBytes,
                replayInputFrames: replayInputFrames,
                outboundSnapshots: outboundSnapshots
            )
        )
    }
}

public struct EntityHandle: Hashable, Codable, Sendable {
    public let index: UInt32
    public let generation: UInt32

    public init(index: UInt32, generation: UInt32) {
        self.index = index
        self.generation = generation
    }
}

public struct ComponentKind: Hashable, Codable, Sendable, Comparable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static func < (lhs: ComponentKind, rhs: ComponentKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum ComponentValue: Hashable, Codable, Sendable {
    case signed(Int32)
    case unsigned(UInt32)
    case fixed(FixedPoint)
    case vector(FixedVector2)
}

struct EntityComponent: Hashable, Codable, Sendable {
    let entity: EntityHandle
    let kind: ComponentKind
    let value: ComponentValue

    init(
        entity: EntityHandle,
        kind: ComponentKind,
        value: ComponentValue
    ) {
        self.entity = entity
        self.kind = kind
        self.value = value
    }
}

public enum EntityHandleError: Error, Equatable, Sendable {
    case capacityExceeded(limit: Int)
    case componentSlotsPerKindCapacityExceeded(kind: ComponentKind, limit: Int)
    case entitiesPerKindCapacityExceeded(kind: ComponentKind, limit: Int)
    case generationWrapped
    case invalidLimit(totalEntities: Int)
    case registeredComponentKindsCapacityExceeded(limit: Int)
    case staleHandle(EntityHandle)
    case stableQueryCacheCapacityExceeded(limit: Int)
    case structureVersionWrapped
    case unregisteredComponentKind(ComponentKind)
}

public struct StableQuery: Sendable {
    public let structureVersion: UInt64
    public let entities: [EntityHandle]

    public init(structureVersion: UInt64, entities: [EntityHandle]) {
        self.structureVersion = structureVersion
        self.entities = entities.sorted(by: EntityStore.entityOrder)
    }

    init(sortedStructureVersion: UInt64, sortedEntities: [EntityHandle]) {
        structureVersion = sortedStructureVersion
        entities = sortedEntities
    }
}

enum EntityStoreRestorationError: Error {
    case invalidState
}

struct EntityStoreRestorationState: Sendable {
    let structureVersion: UInt64
    let generations: [UInt32]
    let occupied: [Bool]
    let recycledIndices: [UInt32]
    let registeredComponentKinds: [ComponentKind]
    let components: [EntityComponent]
}

struct ComponentQueryCacheEntry: Sendable {
    let requiredKinds: [ComponentKind]
    let query: StableQuery
}

struct ComponentStorage: Sendable {
    let kind: ComponentKind
    var entries: [EntityComponent]
}

public struct EntityStore: Sendable {
    public let limits: RealtimeLimits
    public internal(set) var structureVersion: UInt64

    var generations: [UInt32]
    var occupied: [Bool]
    var recycledIndices: [UInt32]
    var registeredComponentKinds: [ComponentKind]
    var componentStorages: [ComponentStorage]
    var stableQueryCache: StableQuery
    var componentQueryCache: [ComponentQueryCacheEntry]

    public init(limits: RealtimeLimits) throws {
        try Self.validate(limits: limits)

        self.limits = limits
        structureVersion = 0
        generations = []
        occupied = []
        recycledIndices = []
        registeredComponentKinds = []
        componentStorages = []
        stableQueryCache = StableQuery(
            sortedStructureVersion: 0,
            sortedEntities: []
        )
        componentQueryCache = []
    }

    init(
        limits: RealtimeLimits,
        restoring state: EntityStoreRestorationState
    ) throws {
        try Self.validate(limits: limits)
        guard state.generations.count == state.occupied.count,
              state.generations.count <= limits.totalEntities,
              state.registeredComponentKinds.count <= limits.registeredComponentKinds
        else {
            throw EntityStoreRestorationError.invalidState
        }

        let recycledIndices = state.recycledIndices.sorted()
        guard recycledIndices == Self.unique(recycledIndices),
              recycledIndices.allSatisfy({
                  Int($0) < state.occupied.count && !state.occupied[Int($0)]
              }),
              state.occupied.indices.allSatisfy({ position in
                  state.occupied[position]
                      || recycledIndices.contains(UInt32(position))
              })
        else {
            throw EntityStoreRestorationError.invalidState
        }

        let registeredKinds = Self.unique(
            state.registeredComponentKinds.sorted()
        )
        guard registeredKinds.count == state.registeredComponentKinds.count else {
            throw EntityStoreRestorationError.invalidState
        }

        let sortedComponents = state.components.sorted(by: Self.componentOrder)
        try Self.validateRestoredComponents(
            sortedComponents,
            generations: state.generations,
            occupied: state.occupied,
            registeredKinds: registeredKinds,
            limits: limits
        )

        self.limits = limits
        structureVersion = state.structureVersion
        generations = state.generations
        occupied = state.occupied
        self.recycledIndices = recycledIndices
        registeredComponentKinds = registeredKinds
        componentStorages = Self.makeComponentStorages(
            registeredKinds: registeredKinds,
            components: sortedComponents
        )
        stableQueryCache = StableQuery(
            sortedStructureVersion: state.structureVersion,
            sortedEntities: Self.liveHandles(
                generations: state.generations,
                occupied: state.occupied
            )
        )
        componentQueryCache = []
    }
}
