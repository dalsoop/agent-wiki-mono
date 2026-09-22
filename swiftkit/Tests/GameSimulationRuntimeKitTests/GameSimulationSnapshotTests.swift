import XCTest
import GameSimulationStateKit
import GameSimulationReducerKit
@testable import GameSimulationRuntimeKit

final class GameSimulationSnapshotTests: XCTestCase {
    private struct State: GameSimulationState {
        static let schemaVersion = 1
        var entities = GameEntityRepository()
        var count = 0
    }

    private enum Action: Codable, Equatable, Sendable {
        case increment
        case scheduleIncrement
    }

    private struct Reducer: GameSimulationReducer {
        func reduceAction(
            state: inout State,
            action: Action,
            environment: Void
        ) -> GameSimulationEffect<Action> {
            switch action {
            case .increment:
                state.count += 1
                return .none
            case .scheduleIncrement:
                return .scheduleAction(id: "increment", at: 3, action: .increment)
            }
        }
    }

    func testSameInputsProduceByteEquivalentCanonicalSnapshot() throws {
        var left = try makeMachine(seed: 42)
        var right = try makeMachine(seed: 42)
        try left.send(.increment)
        try right.send(.increment)
        try left.send(.scheduleIncrement)
        try right.send(.scheduleIncrement)
        try left.advance(ticks: 2)
        try right.advance(ticks: 2)

        XCTAssertEqual(
            try left.snapshotData(createdAt: nil),
            try right.snapshotData(createdAt: nil)
        )
    }

    func testSnapshotRestoreIncludesRuntimeAndScheduledState() throws {
        var source = try makeMachine(seed: 7)
        try source.send(.scheduleIncrement)
        source.pause()
        try source.setSpeed(4)
        _ = source.nextRandom()
        let data = try source.snapshotData(createdAt: nil)

        var restored = try makeMachine(seed: 999)
        try restored.restoreSnapshot(from: data)

        XCTAssertEqual(restored.state, source.state)
        XCTAssertEqual(restored.revision, source.revision)
        XCTAssertEqual(restored.currentTick, source.currentTick)
        XCTAssertEqual(restored.isPaused, source.isPaused)
        XCTAssertEqual(restored.speed, source.speed)
        XCTAssertEqual(restored.randomState, source.randomState)
        XCTAssertEqual(restored.scheduledActionValues, source.scheduledActionValues)
    }

    func testCorruptChecksumDoesNotMutateMachine() throws {
        var source = try makeMachine(seed: 1)
        try source.send(.increment)
        let valid = try source.snapshotData(createdAt: nil)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: valid) as? [String: Any]
        )
        var state = try XCTUnwrap(object["state"] as? [String: Any])
        state["count"] = 99
        object["state"] = state
        let corrupt = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        var target = try makeMachine(seed: 5)
        let before = target.state
        XCTAssertThrowsError(try target.restoreSnapshot(from: corrupt)) {
            XCTAssertEqual($0 as? GameSimulationSnapshotError, .checksumMismatch)
        }
        XCTAssertEqual(target.state, before)
        XCTAssertEqual(target.revision, 0)
    }

    func testValidChecksumCannotRestoreRepositoryWithOrphanRecord() throws {
        let source = try makeMachine(seed: 1)
        let valid = try source.snapshotData(createdAt: nil)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: valid) as? [String: Any]
        )
        var state = try XCTUnwrap(object["state"] as? [String: Any])
        state["entities"] = [
            "records": [[
                "id": "child",
                "parentID": "missing",
                "tags": [],
            ]],
        ]
        object["state"] = state
        let forged = try GameSimulationSnapshotChecksum.rewrite(
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )

        var target = try makeMachine(seed: 5)
        let before = target.state
        XCTAssertThrowsError(try target.restoreSnapshot(from: forged)) {
            XCTAssertEqual($0 as? GameSimulationSnapshotError, .decodeFailed)
        }
        XCTAssertEqual(target.state, before)
        XCTAssertEqual(target.revision, 0)
    }

    func testAtomicStoreRoundTrip() throws {
        let directory = temporaryDirectory()
        let store = GameSimulationSnapshotStore(directory: directory)
        let data = Data("snapshot".utf8)

        try store.save(data, name: "slot-1")

        XCTAssertEqual(try store.load(name: "slot-1"), data)
        XCTAssertFalse(
            try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .contains(where: { $0.hasSuffix(".tmp") })
        )
    }

    func testMigrationChainMustBeContiguousAndRewritesChecksum() throws {
        let directory = temporaryDirectory()
        let store = GameSimulationSnapshotStore(directory: directory)
        let machine = try makeMachine(seed: 1)
        let current = try machine.snapshotData(createdAt: nil)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: current) as? [String: Any]
        )
        object["gameStateSchemaVersion"] = 0
        let old = try GameSimulationSnapshotChecksum.rewrite(
            JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
        try store.save(old, name: "old")

        let migration = GameSimulationSnapshotMigration(
            fromVersion: 0,
            toVersion: 1
        ) { data in
            var json = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            json["gameStateSchemaVersion"] = 1
            return try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        }
        let migrated = try store.load(
            name: "old",
            targetGameStateSchemaVersion: 1,
            migrations: [migration]
        )
        let envelope = try JSONDecoder().decode(
            GameSimulationSnapshotEnvelope<State, Action>.self,
            from: migrated
        )
        XCTAssertEqual(envelope.gameStateSchemaVersion, 1)
        XCTAssertTrue(try GameSimulationSnapshotChecksum.isValid(migrated))

        XCTAssertThrowsError(
            try store.load(
                name: "old",
                targetGameStateSchemaVersion: 2,
                migrations: [migration]
            )
        ) {
            XCTAssertEqual(
                $0 as? GameSimulationSnapshotError,
                .missingMigration(fromVersion: 1, targetVersion: 2)
            )
        }
    }

    private func makeMachine(seed: UInt64) throws -> GameSimulationMachine<Reducer> {
        try GameSimulationMachine(
            state: State(),
            environment: (),
            reducer: Reducer(),
            configuration: .init(seed: seed)
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "game-simulation-runtime-tests")
            .appending(path: UUID().uuidString)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        }
        return url
    }
}
