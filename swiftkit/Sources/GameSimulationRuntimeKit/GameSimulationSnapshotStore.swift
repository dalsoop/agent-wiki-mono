import Foundation

public struct GameSimulationSnapshotMigration {
    public let fromVersion: Int
    public let toVersion: Int
    private let transformBody: (Data) throws -> Data

    public init(
        fromVersion: Int,
        toVersion: Int,
        transform: @escaping (Data) throws -> Data
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        transformBody = transform
    }

    public func transform(_ data: Data) throws -> Data {
        try transformBody(data)
    }
}

public struct GameSimulationSnapshotStore {
    public let directory: URL
    private let fileManager: FileManager

    public init(
        directory: URL,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func save(_ data: Data, name: String) throws {
        let destination = try url(for: name)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let temporary = directory.appending(
            path: ".\(name).\(UUID().uuidString).tmp"
        )
        defer { try? fileManager.removeItem(at: temporary) }
        try data.write(to: temporary)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    public func load(name: String) throws -> Data {
        try Data(contentsOf: url(for: name))
    }

    public func load(
        name: String,
        targetGameStateSchemaVersion targetVersion: Int,
        migrations: [GameSimulationSnapshotMigration]
    ) throws -> Data {
        var data = try load(name: name)
        guard try GameSimulationSnapshotChecksum.isValid(data) else {
            throw GameSimulationSnapshotError.checksumMismatch
        }
        var version = try header(from: data).gameStateSchemaVersion
        guard version <= targetVersion else {
            throw GameSimulationSnapshotError.gameStateSchemaMismatch(
                expected: targetVersion,
                received: version
            )
        }

        while version < targetVersion {
            guard let migration = migrations.first(where: {
                $0.fromVersion == version && $0.toVersion > version
            }) else {
                throw GameSimulationSnapshotError.missingMigration(
                    fromVersion: version,
                    targetVersion: targetVersion
                )
            }
            let transformed: Data
            do {
                transformed = try migration.transform(data)
            } catch {
                throw GameSimulationSnapshotError.migrationFailed(
                    fromVersion: migration.fromVersion,
                    toVersion: migration.toVersion
                )
            }
            let received = try header(from: transformed).gameStateSchemaVersion
            guard received == migration.toVersion else {
                throw GameSimulationSnapshotError.migrationVersionMismatch(
                    expected: migration.toVersion,
                    received: received
                )
            }
            data = try GameSimulationSnapshotChecksum.rewrite(transformed)
            version = received
        }
        return data
    }

    private func url(for name: String) throws -> URL {
        guard !name.isEmpty,
              name != ".",
              name != "..",
              !name.contains("/"),
              !name.contains("\\") else {
            throw GameSimulationSnapshotError.invalidSaveName
        }
        return directory.appending(path: "\(name).json")
    }

    private func header(from data: Data) throws -> SnapshotHeader {
        do {
            return try JSONDecoder().decode(SnapshotHeader.self, from: data)
        } catch {
            throw GameSimulationSnapshotError.decodeFailed
        }
    }

    private struct SnapshotHeader: Decodable {
        var gameStateSchemaVersion: Int
    }
}
