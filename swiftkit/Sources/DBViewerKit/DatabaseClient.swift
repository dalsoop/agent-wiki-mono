import Foundation

/// Failure modes shared by every `DatabaseClient` implementation.
public enum DatabaseClientError: Error, Equatable, LocalizedError {
    case unsafeSQL
    case commandFailed(String)
    case parseFailed(String)
    /// 선택한 연결 프로필(이름)의 jump·kube 호스트가 비어 있다 — 원격 명령을 띄우기 전에 거부한다.
    case connectionNotConfigured(String)

    public var errorDescription: String? {
        switch self {
        case .unsafeSQL:
            "Only read-only SQL is allowed."
        case let .commandFailed(message):
            message.isEmpty ? "Query failed." : message
        case let .parseFailed(message):
            message
        case let .connectionNotConfigured(profile):
            "연결 대상을 설정하세요: 프로필 '\(profile)' 의 jumpHost·kubeHost 가 비어 있습니다 "
                + "(예: root@db-jump.example.internal). \(AppPaths.default.storeFile.path) 의 "
                + "settings.profiles 에 지정합니다."
        }
    }
}

public protocol DatabaseClient: Sendable {
    func discover() async -> Result<[DatabaseTarget], DatabaseClientError>
    func runQuery(target: DatabaseTarget, sql: String) async -> Result<QueryResult, DatabaseClientError>
    func previewTable(target: DatabaseTarget, schema: String, table: String, limit: Int) async -> Result<QueryResult, DatabaseClientError>
    func listTables(target: DatabaseTarget) async -> Result<[TableReference], DatabaseClientError>
}
