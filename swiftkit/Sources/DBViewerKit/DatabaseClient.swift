import Foundation

/// Failure modes shared by every `DatabaseClient` implementation.
public enum DatabaseClientError: Error, Equatable, LocalizedError {
    case unsafeSQL
    case commandFailed(String)
    case parseFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeSQL:
            "Only read-only SQL is allowed."
        case let .commandFailed(message):
            message.isEmpty ? "Query failed." : message
        case let .parseFailed(message):
            message
        }
    }
}

public protocol DatabaseClient: Sendable {
    func discover() async -> Result<[DatabaseTarget], DatabaseClientError>
    func runQuery(target: DatabaseTarget, sql: String) async -> Result<QueryResult, DatabaseClientError>
    func previewTable(target: DatabaseTarget, schema: String, table: String, limit: Int) async -> Result<QueryResult, DatabaseClientError>
    func listTables(target: DatabaseTarget) async -> Result<[TableReference], DatabaseClientError>
}
