import Foundation
import GameRealtimeStateKit

public struct RNGStreamSnapshot: Hashable, Codable, Sendable {
    public let streamID: UInt64
    public let state: UInt64

    public init(streamID: UInt64, state: UInt64) {
        self.streamID = streamID
        self.state = state
    }
}

public struct CanonicalSnapshot: Hashable, Codable, Sendable {
    public let schemaID: String
    public let profileID: String
    public let tick: UInt64
    public let epoch: UInt64
    public let rngStreams: [RNGStreamSnapshot]
    public let canonicalBytes: Data
    public let deterministicStateHash: UInt64

    public init(
        schemaID: String,
        profileID: String,
        tick: UInt64,
        epoch: UInt64,
        rngStreams: [RNGStreamSnapshot],
        canonicalBytes: Data,
        deterministicStateHash: UInt64
    ) throws {
        guard !schemaID.isEmpty else {
            throw EngineConfigurationError.emptySnapshotIdentifier(.schemaID)
        }
        guard !profileID.isEmpty else {
            throw EngineConfigurationError.emptySnapshotIdentifier(.profileID)
        }

        let sortedRNGStreams = rngStreams.sorted {
            $0.streamID < $1.streamID
        }
        for index in sortedRNGStreams.indices.dropFirst() {
            let previous = sortedRNGStreams[index - 1]
            let current = sortedRNGStreams[index]
            guard previous.streamID != current.streamID else {
                throw EngineConfigurationError.duplicateRNGStreamID(
                    current.streamID
                )
            }
        }

        let snapshotLimit = RealtimeLimits.standardV1.canonicalSnapshotBytes
        guard canonicalBytes.count <= snapshotLimit else {
            throw EngineCapacityError(
                resource: .canonicalSnapshotBytes,
                limit: snapshotLimit,
                attempted: canonicalBytes.count
            )
        }

        self.schemaID = schemaID
        self.profileID = profileID
        self.tick = tick
        self.epoch = epoch
        self.rngStreams = sortedRNGStreams
        self.canonicalBytes = canonicalBytes
        self.deterministicStateHash = deterministicStateHash
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaID: container.decode(String.self, forKey: .schemaID),
            profileID: container.decode(String.self, forKey: .profileID),
            tick: container.decode(UInt64.self, forKey: .tick),
            epoch: container.decode(UInt64.self, forKey: .epoch),
            rngStreams: container.decode(
                [RNGStreamSnapshot].self,
                forKey: .rngStreams
            ),
            canonicalBytes: container.decode(
                Data.self,
                forKey: .canonicalBytes
            ),
            deterministicStateHash: container.decode(
                UInt64.self,
                forKey: .deterministicStateHash
            )
        )
    }
}

public struct TickResult: Sendable {
    public init() {}
}

public struct AdvanceReport: Sendable {
    public init() {}
}

public struct EngineCapacityError: Error, Equatable, Sendable {
    public enum Resource: String, Codable, Hashable, Sendable {
        case entities
        case entitiesPerKind
        case componentSlotsPerKind
        case registeredComponentKinds
        case stableQueryCacheEntries
        case deferredCommandsPerTick
        case authorityEventsPerTick
        case queuedInputFrames
        case broadphaseOccupiedCells
        case broadphaseCandidatePairsPerTick
        case resolvedCollisionPairsPerTick
        case solverIterationsPerPair
        case checkpointRingLength
        case checkpointRingBytes
        case canonicalSnapshotBytes
        case replayInputFrames
        case outboundSnapshots
    }

    public let resource: Resource
    public let limit: Int
    public let attempted: Int

    public init(resource: Resource, limit: Int, attempted: Int) {
        self.resource = resource
        self.limit = limit
        self.attempted = attempted
    }
}

public enum EngineConfigurationError: Error, Equatable, Sendable {
    public enum InputCoordinate: String, Codable, Hashable, Sendable {
        case moveX
        case moveY
        case aimX
        case aimY
    }

    public enum SnapshotIdentifier: String, Codable, Hashable, Sendable {
        case schemaID
        case profileID
    }

    case unsupportedInputContractVersion(UInt16)
    case inputCoordinateOutOfRange(
        component: InputCoordinate,
        rawValue: Int32
    )
    case unsupportedInputButtons(rawValue: UInt32)
    case emptySnapshotIdentifier(SnapshotIdentifier)
    case duplicateRNGStreamID(UInt64)
}

public enum EngineOwnershipError: Error, Equatable, Sendable {
    case reentrantMutation
}
