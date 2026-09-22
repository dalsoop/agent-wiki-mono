import Foundation

public enum ArtifactKind: String, Codable, Sendable {
    case process
    case agentRoom = "agent_room"
    case buildLock = "build_lock"
    case backgroundWorker = "background_worker"

    public var label: String {
        switch self {
        case .process: return "프로세스"
        case .agentRoom: return "에이전트 방"
        case .buildLock: return "빌드 락"
        case .backgroundWorker: return "백그라운드 워커"
        }
    }
}

public enum TriageSafety: String, Codable, Sendable {
    case safeToKill = "safe_to_kill"       // 고아 MCP, 유휴 좀비
    case userInteractive = "user_session"   // Claude/Grok 터미널 (보호)
    case systemCritical = "system_daemon"   // MariaDB, Launchd (금지)

    public var label: String {
        switch self {
        case .safeToKill: return "⚠️ 유휴 좀비(정리 권장)"
        case .userInteractive: return "👤 사용자 세션(보호)"
        case .systemCritical: return "⚙️ 시스템 상주(보호)"
        }
    }
}

public struct ExecutionContext: Codable, Sendable, Equatable {
    public let command: String
    public let workingDirectory: String
    public let environmentVariables: [String: String]
    public let parentID: String?

    public init(
        command: String,
        workingDirectory: String = FileManager.default.currentDirectoryPath,
        environmentVariables: [String: String] = [:],
        parentID: String? = nil
    ) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.environmentVariables = environmentVariables
        self.parentID = parentID
    }
}

public protocol TriageableArtifact: Identifiable, Sendable {
    var id: String { get }
    var artifactKind: ArtifactKind { get }
    var displayName: String { get }
    var stalledSeconds: Int { get }
    var safety: TriageSafety { get }
    var executionContext: ExecutionContext { get }
}

public struct TriageReceipt: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let artifactID: String
    public let kind: ArtifactKind
    public let displayName: String
    public let dismissedAt: Date
    public let dismissedBy: String
    public let recoveredCPU: Double
    public let context: ExecutionContext
    public var isRevived: Bool
    public var revivedAt: Date?

    public init(
        id: UUID = UUID(),
        artifactID: String,
        kind: ArtifactKind,
        displayName: String,
        dismissedAt: Date = Date(),
        dismissedBy: String = "user",
        recoveredCPU: Double = 0.0,
        context: ExecutionContext,
        isRevived: Bool = false,
        revivedAt: Date? = nil
    ) {
        self.id = id
        self.artifactID = artifactID
        self.kind = kind
        self.displayName = displayName
        self.dismissedAt = dismissedAt
        self.dismissedBy = dismissedBy
        self.recoveredCPU = recoveredCPU
        self.context = context
        self.isRevived = isRevived
        self.revivedAt = revivedAt
    }
}
