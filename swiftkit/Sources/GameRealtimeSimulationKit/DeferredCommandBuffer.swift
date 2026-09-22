@_exported import GameRealtimeProtocolKit

public struct CommandKey: Hashable, Codable, Sendable, Comparable {
    public let stage: UInt16
    public let systemOrder: UInt16
    public let sequence: UInt32

    public init(stage: UInt16, systemOrder: UInt16, sequence: UInt32) {
        self.stage = stage
        self.systemOrder = systemOrder
        self.sequence = sequence
    }

    public static func < (lhs: CommandKey, rhs: CommandKey) -> Bool {
        if lhs.stage != rhs.stage {
            return lhs.stage < rhs.stage
        }
        if lhs.systemOrder != rhs.systemOrder {
            return lhs.systemOrder < rhs.systemOrder
        }
        return lhs.sequence < rhs.sequence
    }
}

public enum DeferredCommand: Hashable, Codable, Sendable {
    case spawn(kind: UInt32)
    case despawn(EntityHandle)
    case setPosition(EntityHandle, FixedVector2)
}

public struct RecordedDeferredCommand:
    Hashable,
    Codable,
    Sendable,
    Comparable
{
    public let key: CommandKey
    public let command: DeferredCommand

    public init(key: CommandKey, command: DeferredCommand) {
        self.key = key
        self.command = command
    }

    public static func < (
        lhs: RecordedDeferredCommand,
        rhs: RecordedDeferredCommand
    ) -> Bool {
        lhs.key < rhs.key
    }
}

public struct DeferredSpawnResult: Hashable, Codable, Sendable {
    public let kind: UInt32
    public let entity: EntityHandle

    public init(kind: UInt32, entity: EntityHandle) {
        self.kind = kind
        self.entity = entity
    }
}

public struct DeferredFlushResult: Hashable, Codable, Sendable {
    public let spawned: [DeferredSpawnResult]

    public init(spawned: [DeferredSpawnResult]) {
        self.spawned = spawned
    }
}

public enum DeferredCommandError: Error, Equatable, Sendable {
    case invalidCommandLimit(Int)
    case duplicateKey(CommandKey)
    case conflictingMutations(EntityHandle)
    case staleHandle(EntityHandle)
}

public struct DeferredCommandBuffer: Sendable {
    public static let entityKindComponentKind = ComponentKind(
        rawValue: 0xFFFF_FF00
    )
    public static let positionComponentKind = ComponentKind(
        rawValue: 0xFFFF_FF01
    )

    public let limits: RealtimeLimits
    private var commands: [RecordedDeferredCommand]
    private var commandKeys: Set<CommandKey>

    public init(limits: RealtimeLimits = .standardV1) throws {
        guard limits.deferredCommandsPerTick >= 0 else {
            throw DeferredCommandError.invalidCommandLimit(
                limits.deferredCommandsPerTick
            )
        }
        self.limits = limits
        commands = []
        commandKeys = []
    }

    public var count: Int {
        commands.count
    }

    public var isEmpty: Bool {
        commands.isEmpty
    }

    var indexedKeyCount: Int {
        commandKeys.count
    }

    public var orderedCommands: [RecordedDeferredCommand] {
        commands.sorted()
    }

    public mutating func enqueue(
        _ command: DeferredCommand,
        key: CommandKey
    ) throws {
        guard !commandKeys.contains(key) else {
            throw DeferredCommandError.duplicateKey(key)
        }
        let attempted = commands.count + 1
        guard attempted <= limits.deferredCommandsPerTick else {
            throw EngineCapacityError(
                resource: .deferredCommandsPerTick,
                limit: limits.deferredCommandsPerTick,
                attempted: attempted
            )
        }
        commands.append(RecordedDeferredCommand(key: key, command: command))
        commandKeys.insert(key)
    }

    public mutating func flush(
        into store: inout EntityStore
    ) throws -> DeferredFlushResult {
        let ordered = orderedCommands
        try Self.validateTargets(in: ordered, against: store)

        var candidate = store
        var spawned: [DeferredSpawnResult] = []
        if ordered.contains(where: {
            if case .spawn = $0.command {
                return true
            }
            return false
        }) {
            try candidate.registerComponentKind(
                Self.entityKindComponentKind
            )
        }
        if ordered.contains(where: {
            if case .setPosition = $0.command {
                return true
            }
            return false
        }) {
            try candidate.registerComponentKind(Self.positionComponentKind)
        }

        do {
            for record in ordered {
                switch record.command {
                case let .spawn(kind):
                    let entity = try candidate.spawn()
                    _ = try candidate.attachComponent(
                        .unsigned(kind),
                        kind: Self.entityKindComponentKind,
                        to: entity
                    )
                    spawned.append(
                        DeferredSpawnResult(kind: kind, entity: entity)
                    )
                case let .despawn(entity):
                    try candidate.despawn(entity)
                case let .setPosition(entity, position):
                    _ = try candidate.attachComponent(
                        .vector(position),
                        kind: Self.positionComponentKind,
                        to: entity
                    )
                }
            }
        } catch EntityHandleError.capacityExceeded(let limit) {
            throw EngineCapacityError(
                resource: .entities,
                limit: limit,
                attempted: limit + 1
            )
        }

        store = candidate
        commands.removeAll(keepingCapacity: true)
        commandKeys.removeAll(keepingCapacity: true)
        return DeferredFlushResult(spawned: spawned)
    }

    private static func validateTargets(
        in commands: [RecordedDeferredCommand],
        against store: EntityStore
    ) throws {
        var mutatedEntities: Set<EntityHandle> = []
        mutatedEntities.reserveCapacity(commands.count)
        for record in commands {
            let target: EntityHandle
            switch record.command {
            case .spawn:
                continue
            case let .despawn(entity), let .setPosition(entity, _):
                target = entity
            }

            do {
                _ = try store.require(target)
            } catch EntityHandleError.staleHandle {
                throw DeferredCommandError.staleHandle(target)
            }
            guard mutatedEntities.insert(target).inserted else {
                throw DeferredCommandError.conflictingMutations(target)
            }
        }
    }
}
