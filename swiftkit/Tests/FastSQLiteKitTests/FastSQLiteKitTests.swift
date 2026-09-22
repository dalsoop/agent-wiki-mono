import Foundation
import Testing
@testable import FastSQLiteKit

@Suite("FastSQLiteKit Tests")
struct FastSQLiteKitTests {

    @Test func databaseCreationAndExecution() throws {
        let db = try SQLiteDatabase()
        try db.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);")
        try db.execute("INSERT INTO users (name) VALUES ('Alice');")
        try db.execute("INSERT INTO users (name) VALUES ('Bob');")

        let version = try db.userVersion()
        #expect(version == 0)

        try db.setUserVersion(1)
        #expect(try db.userVersion() == 1)
    }

    @Test func preparedStatementBindAndFetch() throws {
        let db = try SQLiteDatabase()
        try db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY, title TEXT, score REAL);")

        let insertStmt = try SQLitePreparedStatement(
            database: db,
            query: "INSERT INTO items (title, score) VALUES (?, ?);"
        )
        try insertStmt.bindText("Item A", at: 1)
        try insertStmt.bindDouble(98.5, at: 2)
        let inserted = try insertStmt.step()
        #expect(!inserted) // INSERT는 DONE 반환 (step() == false)

        let selectStmt = try SQLitePreparedStatement(
            database: db,
            query: "SELECT id, title, score FROM items WHERE title = ?;"
        )
        try selectStmt.bindText("Item A", at: 1)
        let hasRow = try selectStmt.step()
        #expect(hasRow)
        #expect(selectStmt.columnText(at: 1) == "Item A")
        #expect(selectStmt.columnDouble(at: 2) == 98.5)
    }

    @Test func migrationSequencing() throws {
        let db = try SQLiteDatabase()
        #expect(try db.userVersion() == 0)

        let migrations = [
            SQLiteMigration(version: 1, description: "v1 schema", sql: "CREATE TABLE t1 (val TEXT);"),
            SQLiteMigration(version: 2, description: "v2 schema", sql: "ALTER TABLE t1 ADD COLUMN extra INT;")
        ]

        try SQLiteMigrator.migrate(database: db, migrations: migrations)
        #expect(try db.userVersion() == 2)

        // 이미 v2이므로 추가 실행해도 no-op
        try SQLiteMigrator.migrate(database: db, migrations: migrations)
        #expect(try db.userVersion() == 2)
    }

    @Test func transactionRollbackOnError() throws {
        let db = try SQLiteDatabase()
        try db.execute("CREATE TABLE logs (msg TEXT);")

        do {
            try db.inTransaction {
                try db.execute("INSERT INTO logs VALUES ('first');")
                // 유효하지 않은 SQL 에러 발생
                try db.execute("INSERT INTO nonexistent_table VALUES ('err');")
            }
        } catch {
            // 의도된 에러
        }

        let query = try SQLitePreparedStatement(database: db, query: "SELECT count(*) FROM logs;")
        _ = try query.step()
        #expect(query.columnInt64(at: 0) == 0) // 롤백되어 0건이어야 함
    }
}
