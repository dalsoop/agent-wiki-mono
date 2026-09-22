import Foundation

public struct SQLiteMigration: Sendable {
    public let targetVersion: Int
    public let migrationDescription: String
    public let action: @Sendable (SQLiteDatabase) throws -> Void

    public init(
        version: Int,
        description: String = "",
        action: @escaping @Sendable (SQLiteDatabase) throws -> Void
    ) {
        self.targetVersion = version
        self.migrationDescription = description
        self.action = action
    }

    public init(version: Int, description: String = "", sql: String) {
        self.targetVersion = version
        self.migrationDescription = description
        self.action = { db in
            try db.execute(sql)
        }
    }
}

public enum SQLiteMigrator {
    /// 주어진 마이그레이션 목록을 현재 user_version과 비교하여 트랜잭션 내에서 순차 적용한다.
    public static func migrate(database: SQLiteDatabase, migrations: [SQLiteMigration]) throws {
        let sorted = migrations.sorted { $0.targetVersion < $1.targetVersion }
        let currentVersion = try database.userVersion()

        for step in sorted where step.targetVersion > currentVersion {
            try database.inTransaction {
                try step.action(database)
                try database.setUserVersion(step.targetVersion)
            }
        }
    }
}
