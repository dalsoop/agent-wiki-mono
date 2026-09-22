import Foundation
import VPNKit

public struct ConnectionPreset: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var jumpHost: String
    public var kubeHost: String
    public var namespaceFilter: String
    public var defaultDatabase: String
    public var queryTimeoutSeconds: Int
    public var defaultLimit: Int
    /// 2026-10-31까지 저장 포맷 호환을 위해 유지하는 legacy VPN 이름.
    public var requiredTunnel: String?
    /// 대상 연결 복구 화면에서 먼저 제안할 시스템 VPN.
    public var recoveryPreferredVPN: VPNServiceReference?

    public struct Hosts: Codable, Equatable, Sendable {
        public var id: String
        public var name: String
        public var jumpHost: String
        public var kubeHost: String
        public init(
            id: String = "k3s-prod-via-pve",
            name: String = "k3s-prod via pve",
            jumpHost: String = "root@192.168.2.50",
            kubeHost: String = "root@10.0.50.100"
        ) {
            self.id = id
            self.name = name
            self.jumpHost = jumpHost
            self.kubeHost = kubeHost
        }
    }

    public struct QueryDefaults: Codable, Equatable, Sendable {
        public var namespaceFilter: String
        public var defaultDatabase: String
        public var queryTimeoutSeconds: Int
        public var defaultLimit: Int
        public init(
            namespaceFilter: String = "",
            defaultDatabase: String = "",
            queryTimeoutSeconds: Int = 30,
            defaultLimit: Int = 100
        ) {
            self.namespaceFilter = namespaceFilter
            self.defaultDatabase = defaultDatabase
            self.queryTimeoutSeconds = queryTimeoutSeconds
            self.defaultLimit = defaultLimit
        }
    }

    public init(
        hosts: Hosts = Hosts(),
        query: QueryDefaults = QueryDefaults(),
        requiredTunnel: String? = nil
    ) {
        self.id = hosts.id
        self.name = hosts.name
        self.jumpHost = hosts.jumpHost
        self.kubeHost = hosts.kubeHost
        self.namespaceFilter = query.namespaceFilter
        self.defaultDatabase = query.defaultDatabase
        self.queryTimeoutSeconds = query.queryTimeoutSeconds
        self.defaultLimit = query.defaultLimit
        self.requiredTunnel = requiredTunnel
        self.recoveryPreferredVPN = requiredTunnel.map(VPNServiceReference.legacy)
    }

    public init(
        hosts: Hosts = Hosts(),
        query: QueryDefaults = QueryDefaults(),
        requiredTunnel: String? = nil,
        recoveryPreferredVPN: VPNServiceReference?
    ) {
        self.id = hosts.id
        self.name = hosts.name
        self.jumpHost = hosts.jumpHost
        self.kubeHost = hosts.kubeHost
        self.namespaceFilter = query.namespaceFilter
        self.defaultDatabase = query.defaultDatabase
        self.queryTimeoutSeconds = query.queryTimeoutSeconds
        self.defaultLimit = query.defaultLimit
        self.recoveryPreferredVPN = recoveryPreferredVPN
        self.requiredTunnel = recoveryPreferredVPN?.displayName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case jumpHost
        case kubeHost
        case namespaceFilter
        case defaultDatabase
        case queryTimeoutSeconds
        case defaultLimit
        case requiredTunnel
        case recoveryPreferredVPN = "recovery_preferred_vpn"
        /// 2026-07-23 빌드가 잘못 배포한 camelCase 키. 읽기 호환 전용.
        case deployedRecoveryPreferredVPN = "recoveryPreferredVPN"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        jumpHost = try container.decode(String.self, forKey: .jumpHost)
        kubeHost = try container.decode(String.self, forKey: .kubeHost)
        namespaceFilter = try container.decode(
            String.self,
            forKey: .namespaceFilter
        )
        defaultDatabase = try container.decode(
            String.self,
            forKey: .defaultDatabase
        )
        queryTimeoutSeconds = try container.decode(
            Int.self,
            forKey: .queryTimeoutSeconds
        )
        defaultLimit = try container.decode(Int.self, forKey: .defaultLimit)

        if container.contains(.recoveryPreferredVPN) {
            recoveryPreferredVPN = try container.decodeIfPresent(
                VPNServiceReference.self,
                forKey: .recoveryPreferredVPN
            )
            requiredTunnel = recoveryPreferredVPN?.displayName
        } else if container.contains(.deployedRecoveryPreferredVPN) {
            recoveryPreferredVPN = try container.decodeIfPresent(
                VPNServiceReference.self,
                forKey: .deployedRecoveryPreferredVPN
            )
            requiredTunnel = recoveryPreferredVPN?.displayName
        } else {
            requiredTunnel = try container.decodeIfPresent(
                String.self,
                forKey: .requiredTunnel
            )
            recoveryPreferredVPN = requiredTunnel.map(
                VPNServiceReference.legacy
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(jumpHost, forKey: .jumpHost)
        try container.encode(kubeHost, forKey: .kubeHost)
        try container.encode(namespaceFilter, forKey: .namespaceFilter)
        try container.encode(defaultDatabase, forKey: .defaultDatabase)
        try container.encode(
            queryTimeoutSeconds,
            forKey: .queryTimeoutSeconds
        )
        try container.encode(defaultLimit, forKey: .defaultLimit)
        try container.encode(
            recoveryPreferredVPN,
            forKey: .recoveryPreferredVPN
        )
        try container.encode(
            recoveryPreferredVPN?.displayName,
            forKey: .requiredTunnel
        )
    }

    public static let defaultK3SProd = ConnectionPreset()
}

public enum WorkbenchTab: String, Codable, CaseIterable, Equatable, Sendable, Identifiable {
    case query
    case data
    case erd
    case schema
    case history
    case settings

    public var id: String { rawValue }
}

/// One column of a table, used by the schema/ERD views.
public struct ColumnInfo: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var type: String
    public var isPrimaryKey: Bool
    public var isForeignKey: Bool

    public var id: String { name }

    public init(name: String, type: String, isPrimaryKey: Bool, isForeignKey: Bool) {
        self.name = name
        self.type = type
        self.isPrimaryKey = isPrimaryKey
        self.isForeignKey = isForeignKey
    }
}

/// A foreign-key edge: `fromColumn` references `toTable(toColumn)`.
public struct ForeignKeyInfo: Codable, Equatable, Sendable, Identifiable {
    public var fromColumn: String
    public var toTable: String
    public var toColumn: String

    public var id: String { "\(fromColumn)->\(toTable).\(toColumn)" }

    public init(fromColumn: String, toTable: String, toColumn: String) {
        self.fromColumn = fromColumn
        self.toTable = toTable
        self.toColumn = toColumn
    }
}

/// A table's columns and outbound foreign keys — the unit the ERD renders.
public struct TableSchema: Codable, Equatable, Sendable, Identifiable {
    public var name: String
    public var columns: [ColumnInfo]
    public var foreignKeys: [ForeignKeyInfo]

    public var id: String { name }

    public init(name: String, columns: [ColumnInfo], foreignKeys: [ForeignKeyInfo]) {
        self.name = name
        self.columns = columns
        self.foreignKeys = foreignKeys
    }
}

public struct QueryTab: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var sql: String
    public var targetID: String?

    public init(
        id: String = "query-1",
        title: String = "Query 1",
        sql: String = "select count(*) from information_schema.tables",
        targetID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.sql = sql
        self.targetID = targetID
    }
}

public enum QueryExecutionStatus: String, Codable, Equatable, Sendable {
    case success
    case failure
}

public struct QueryExecutionRecord: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var sql: String
    public var targetID: String?
    public var databaseName: String?
    public var executedAt: Date
    public var durationMilliseconds: Int
    public var rowCount: Int?
    public var status: QueryExecutionStatus
    public var errorMessage: String?

    public struct Outcome: Codable, Equatable, Sendable {
        public var durationMilliseconds: Int
        public var rowCount: Int?
        public var status: QueryExecutionStatus
        public var errorMessage: String?
        public init(
            durationMilliseconds: Int = 0,
            rowCount: Int? = nil,
            status: QueryExecutionStatus = .success,
            errorMessage: String? = nil
        ) {
            self.durationMilliseconds = durationMilliseconds
            self.rowCount = rowCount
            self.status = status
            self.errorMessage = errorMessage
        }
    }

    public init(
        id: String = UUID().uuidString,
        sql: String,
        targetID: String? = nil,
        databaseName: String? = nil,
        executedAt: Date = Date(),
        outcome: Outcome = Outcome()
    ) {
        self.id = id
        self.sql = sql
        self.targetID = targetID
        self.databaseName = databaseName
        self.executedAt = executedAt
        self.durationMilliseconds = outcome.durationMilliseconds
        self.rowCount = outcome.rowCount
        self.status = outcome.status
        self.errorMessage = outcome.errorMessage
    }
}

public struct DatabaseViewerSettings: Codable, Equatable, Sendable {
    public var profiles: [ConnectionPreset]
    public var selectedProfileID: String
    public var readOnlyMode: Bool
    /// How the ERD groups tables: everything, domain only, or Laravel framework only.
    public var erdTableFilter: TableCategoryFilter
    /// 워크벤치를 닫아 이 프로필의 VPN 터널을 쓰는 리소스가 없어지면 터널을 자동으로 내릴지(기본 false).
    public var autoDisconnectWhenIdle: Bool

    public init(
        profiles: [ConnectionPreset] = [.defaultK3SProd],
        selectedProfileID: String = ConnectionPreset.defaultK3SProd.id,
        readOnlyMode: Bool = true,
        erdTableFilter: TableCategoryFilter = .all,
        autoDisconnectWhenIdle: Bool = false
    ) {
        let usableProfiles = profiles.isEmpty ? [.defaultK3SProd] : profiles
        self.profiles = usableProfiles
        self.selectedProfileID = selectedProfileID
        self.readOnlyMode = readOnlyMode
        self.erdTableFilter = erdTableFilter
        self.autoDisconnectWhenIdle = autoDisconnectWhenIdle
    }

    // Decode leniently so state persisted before `erdTableFilter` existed still loads.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedProfiles = try container.decodeIfPresent([ConnectionPreset].self, forKey: .profiles) ?? [.defaultK3SProd]
        self.profiles = decodedProfiles.isEmpty ? [.defaultK3SProd] : decodedProfiles
        self.selectedProfileID = try container.decodeIfPresent(String.self, forKey: .selectedProfileID)
            ?? ConnectionPreset.defaultK3SProd.id
        self.readOnlyMode = try container.decodeIfPresent(Bool.self, forKey: .readOnlyMode) ?? true
        self.erdTableFilter = try container.decodeIfPresent(TableCategoryFilter.self, forKey: .erdTableFilter) ?? .all
        self.autoDisconnectWhenIdle = try container.decodeIfPresent(Bool.self, forKey: .autoDisconnectWhenIdle) ?? false
    }

    public var selectedProfile: ConnectionPreset {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first ?? .defaultK3SProd
    }
}

public struct DatabaseTarget: Codable, Equatable, Sendable, Identifiable {
    public var id: String {
        "\(namespace)/\(clusterName)/\(databaseName)"
    }

    public var namespace: String
    public var clusterName: String
    public var primaryPod: String
    public var databaseName: String

    public init(namespace: String, clusterName: String, primaryPod: String, databaseName: String) {
        self.namespace = namespace
        self.clusterName = clusterName
        self.primaryPod = primaryPod
        self.databaseName = databaseName
    }
}

public struct TableReference: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(schema).\(name)" }

    public var schema: String
    public var name: String

    public init(schema: String, name: String) {
        self.schema = schema
        self.name = name
    }
}

public struct QueryResult: Codable, Equatable, Sendable {
    public var columns: [String]
    public var rows: [[String]]

    public init(columns: [String], rows: [[String]]) {
        self.columns = columns
        self.rows = rows
    }
}

/// Which slice of tables the ERD shows.
public enum TableCategoryFilter: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Every table.
    case all
    /// Application/business tables only (excludes Laravel framework tables).
    case domain
    /// Laravel framework/infrastructure tables only.
    case framework

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .all: return "All"
        case .domain: return "Domain"
        case .framework: return "Framework"
        }
    }
}

/// Splits a SQLite database's tables into Laravel framework/infrastructure tables
/// versus application domain tables, so the ERD can show them separately.
public enum LaravelTableClassifier {
    /// Exact table names created by Laravel core or first-party packages.
    public static let frameworkTables: Set<String> = [
        "migrations",
        "cache",
        "cache_locks",
        "jobs",
        "job_batches",
        "failed_jobs",
        "sessions",
        "password_reset_tokens",
        "password_resets",
        "personal_access_tokens",
        "notifications",
        "sqlite_sequence",
    ]

    /// Prefixes for framework/observability package tables (Telescope, Pulse).
    public static let frameworkPrefixes: [String] = ["telescope_", "pulse_"]

    public static func isFramework(_ tableName: String) -> Bool {
        let name = tableName.lowercased()
        if frameworkTables.contains(name) { return true }
        return frameworkPrefixes.contains { name.hasPrefix($0) }
    }

    public static func category(of tableName: String) -> TableCategoryFilter {
        isFramework(tableName) ? .framework : .domain
    }

    /// Keep only the schemas that match `filter`.
    public static func filter(_ schemas: [TableSchema], by filter: TableCategoryFilter) -> [TableSchema] {
        switch filter {
        case .all:
            return schemas
        case .domain:
            return schemas.filter { !isFramework($0.name) }
        case .framework:
            return schemas.filter { isFramework($0.name) }
        }
    }
}
