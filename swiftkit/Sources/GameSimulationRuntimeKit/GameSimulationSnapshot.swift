import Foundation
import GameSimulationStateKit
import GameSimulationReducerKit

public enum GameSimulationSnapshotError: Error, Equatable, Sendable {
    case invalidJSON
    case decodeFailed
    case checksumMismatch
    case unsupportedSnapshotSchema(expected: Int, received: Int)
    case gameStateSchemaMismatch(expected: Int, received: Int)
    case invalidRuntimeValue(String)
    case invalidSaveName
    case missingMigration(fromVersion: Int, targetVersion: Int)
    case migrationFailed(fromVersion: Int, toVersion: Int)
    case migrationVersionMismatch(expected: Int, received: Int)

    public var code: String {
        switch self {
        case .invalidJSON: "snapshot.invalid-json"
        case .decodeFailed: "snapshot.decode-failed"
        case .checksumMismatch: "snapshot.checksum-mismatch"
        case .unsupportedSnapshotSchema: "snapshot.unsupported-schema"
        case .gameStateSchemaMismatch: "snapshot.game-state-schema-mismatch"
        case .invalidRuntimeValue: "snapshot.invalid-runtime-value"
        case .invalidSaveName: "snapshot.invalid-save-name"
        case .missingMigration: "snapshot.missing-migration"
        case .migrationFailed: "snapshot.migration-failed"
        case .migrationVersionMismatch: "snapshot.migration-version-mismatch"
        }
    }
}

public struct GameSimulationSnapshotEnvelope<State, Action>: Codable, Equatable, Sendable
where State: GameSimulationBaseState,
      Action: Codable & Equatable & Sendable {
    public var schemaVersion: Int
    public var engineVersion: String
    public var gameStateSchemaVersion: Int
    public var revision: Int64
    public var tick: GameSimulationTick
    public var isPaused: Bool
    public var speed: Int
    public var randomState: GameSimulationRandomState
    public var scheduledActions: [GameSimulationScheduledAction<Action>]
    public var state: State
    public var checksum: String
    public var createdAt: Date?

    public struct Metadata: Equatable, Sendable {
        public var schemaVersion: Int
        public var engineVersion: String
        public var gameStateSchemaVersion: Int
        public var checksum: String
        public var createdAt: Date?

        public init(
            schemaVersion: Int = 1,
            engineVersion: String = "1.0.0",
            gameStateSchemaVersion: Int,
            checksum: String = "",
            createdAt: Date? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.engineVersion = engineVersion
            self.gameStateSchemaVersion = gameStateSchemaVersion
            self.checksum = checksum
            self.createdAt = createdAt
        }
    }

    public struct Runtime: Equatable, Sendable {
        public var revision: Int64
        public var tick: GameSimulationTick
        public var isPaused: Bool
        public var speed: Int
        public var randomState: GameSimulationRandomState
        public var scheduledActions: [GameSimulationScheduledAction<Action>]

        public init(
            revision: Int64,
            tick: GameSimulationTick,
            isPaused: Bool,
            speed: Int,
            randomState: GameSimulationRandomState,
            scheduledActions: [GameSimulationScheduledAction<Action>]
        ) {
            self.revision = revision
            self.tick = tick
            self.isPaused = isPaused
            self.speed = speed
            self.randomState = randomState
            self.scheduledActions = scheduledActions
        }
    }

    public init(metadata: Metadata, runtime: Runtime, state: State) {
        self.schemaVersion = metadata.schemaVersion
        self.engineVersion = metadata.engineVersion
        self.gameStateSchemaVersion = metadata.gameStateSchemaVersion
        self.revision = runtime.revision
        self.tick = runtime.tick
        self.isPaused = runtime.isPaused
        self.speed = runtime.speed
        self.randomState = runtime.randomState
        self.scheduledActions = runtime.scheduledActions
        self.state = state
        self.checksum = metadata.checksum
        self.createdAt = metadata.createdAt
    }
}

public enum GameSimulationSnapshotChecksum {
    public static func rewrite(_ data: Data) throws -> Data {
        var object = try rootObject(from: data)
        object["checksum"] = checksum(for: object)
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.sortedKeys, .withoutEscapingSlashes]
        )
    }

    public static func isValid(_ data: Data) throws -> Bool {
        let object = try rootObject(from: data)
        guard let stored = object["checksum"] as? String else { return false }
        return stored == checksum(for: object)
    }

    private static func rootObject(from data: Data) throws -> [String: Any] {
        do {
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw GameSimulationSnapshotError.invalidJSON
            }
            return root
        } catch let err as GameSimulationSnapshotError {
            throw err
        } catch {
            throw GameSimulationSnapshotError.invalidJSON
        }
    }

    private static func checksum(for object: [String: Any]) -> String {
        var payload = object
        payload["checksum"] = nil
        payload["createdAt"] = nil
        let data: Data
        do {
            data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            return ""
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", hash)
    }
}

public extension GameSimulationMachine {
    func snapshotEnvelope(
        createdAt: Date? = nil
    ) throws -> GameSimulationSnapshotEnvelope<R.State, R.Action> {
        let data = try snapshotData(createdAt: createdAt)
        do {
            return try JSONDecoder().decode(
                GameSimulationSnapshotEnvelope<R.State, R.Action>.self,
                from: data
            )
        } catch {
            throw GameSimulationSnapshotError.decodeFailed
        }
    }

    func snapshotData(createdAt: Date? = nil) throws -> Data {
        try validateStateParity()
        let envelope = GameSimulationSnapshotEnvelope<R.State, R.Action>(
            metadata: .init(
                gameStateSchemaVersion: R.State.schemaVersion,
                createdAt: createdAt
            ),
            runtime: .init(
                revision: revision,
                tick: currentTick,
                isPaused: isPaused,
                speed: speed,
                randomState: randomState,
                scheduledActions: scheduledActionValues
            ),
            state: state
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            return try GameSimulationSnapshotChecksum.rewrite(
                encoder.encode(envelope)
            )
        } catch let error as GameSimulationSnapshotError {
            throw error
        } catch {
            throw GameSimulationSnapshotError.decodeFailed
        }
    }

    mutating func restoreSnapshot(from data: Data) throws {
        guard try GameSimulationSnapshotChecksum.isValid(data) else {
            throw GameSimulationSnapshotError.checksumMismatch
        }
        let envelope: GameSimulationSnapshotEnvelope<R.State, R.Action>
        do {
            envelope = try JSONDecoder().decode(
                GameSimulationSnapshotEnvelope<R.State, R.Action>.self,
                from: data
            )
        } catch {
            throw GameSimulationSnapshotError.decodeFailed
        }
        guard envelope.schemaVersion == 1 else {
            throw GameSimulationSnapshotError.unsupportedSnapshotSchema(
                expected: 1,
                received: envelope.schemaVersion
            )
        }
        guard envelope.gameStateSchemaVersion == R.State.schemaVersion else {
            throw GameSimulationSnapshotError.gameStateSchemaMismatch(
                expected: R.State.schemaVersion,
                received: envelope.gameStateSchemaVersion
            )
        }
        guard envelope.tick >= 0, envelope.revision >= 0 else {
            throw GameSimulationSnapshotError.invalidRuntimeValue("negative revision or tick")
        }
        guard (1 ... 16).contains(envelope.speed) else {
            throw GameSimulationSnapshotError.invalidRuntimeValue("speed")
        }
        let scheduledIDs = envelope.scheduledActions.map(\.id)
        guard Set(scheduledIDs).count == scheduledIDs.count else {
            throw GameSimulationSnapshotError.invalidRuntimeValue("duplicate scheduled action id")
        }
        do {
            try GameSimulationRuntimeParityValidator.validate(
                state: envelope.state,
                revision: envelope.revision,
                tick: envelope.tick
            )
        } catch let error as GameSimulationExecutionError {
            throw GameSimulationSnapshotError.invalidRuntimeValue(error.code)
        }

        restoreSnapshotValues(
            state: envelope.state,
            revision: envelope.revision,
            currentTick: envelope.tick,
            isPaused: envelope.isPaused,
            speed: envelope.speed,
            randomState: envelope.randomState,
            scheduledActions: envelope.scheduledActions
        )
    }
}
