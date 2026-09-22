import Foundation
import StateRootKit
@_exported import SessionKit

/// 방 안에서 기동할 에이전트 CLI 도구 (SupportedAIAgentCLI SSOT)
public typealias AgentTool = SupportedAIAgentCLI

/// 방 안에서 도구를 기동하기 위한 사양
public struct RoomLaunch: Codable, Equatable, Sendable {
    public var tool: AgentTool
    public var model: String?
    public var promptText: String
    public var promptFile: String?
    public var timeout: Duration
    public var env: [String: String]
    public var workdir: String?

    public init(
        tool: AgentTool,
        model: String? = nil,
        promptText: String = "",
        promptFile: String? = nil,
        timeout: Duration = .seconds(3600),
        env: [String: String] = [:],
        workdir: String? = nil
    ) {
        self.tool = tool
        self.model = model
        self.promptText = promptText
        self.promptFile = promptFile
        self.timeout = timeout
        self.env = env
        self.workdir = workdir
    }

    enum CodingKeys: String, CodingKey {
        case tool
        case model
        case promptText
        case promptFile
        case timeoutSeconds
        case env
        case workdir
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.tool = try container.decode(AgentTool.self, forKey: .tool)
        self.model = try container.decodeIfPresent(String.self, forKey: .model)
        self.promptText = try container.decodeIfPresent(String.self, forKey: .promptText) ?? ""
        self.promptFile = try container.decodeIfPresent(String.self, forKey: .promptFile)
        let seconds = try container.decodeIfPresent(Double.self, forKey: .timeoutSeconds) ?? 3600.0
        self.timeout = .seconds(seconds)
        self.env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        self.workdir = try container.decodeIfPresent(String.self, forKey: .workdir)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(tool, forKey: .tool)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encode(promptText, forKey: .promptText)
        try container.encodeIfPresent(promptFile, forKey: .promptFile)
        let (seconds, attoseconds) = timeout.components
        let doubleSeconds = Double(seconds) + Double(attoseconds) / 1e18
        try container.encode(doubleSeconds, forKey: .timeoutSeconds)
        try container.encode(env, forKey: .env)
        try container.encodeIfPresent(workdir, forKey: .workdir)
    }
}

extension RoomLaunch {
    /// 룸 볼트 격리 경로 및 단방향 프록시 환경변수를 주입한 새 사양을 반환
    public func injectingVaultEnvironment(
        layout: RoomVaultLayout,
        tenant: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RoomLaunch {
        var mergedEnv = env
        mergedEnv["ROOM_VAULT_PATH"] = layout.roomURL.path
        mergedEnv["ROOM_SKILLS_PATH"] = layout.skillsDir.path
        mergedEnv["ROOM_CURATED_PATH"] = layout.curatedDir.path
        mergedEnv["ROOM_MEMORY_PATH"] = layout.memoryDir.path
        mergedEnv["ROOM_RAW_PATH"] = layout.rawDir.path

        let tenantRoot = StateRootKit.tenantStateRoot(tenant: tenant, environment: environment)
        let tenantSkills = (tenantRoot as NSString).appendingPathComponent("skills")
        mergedEnv["TENANT_SKILLS_PATH"] = tenantSkills
        mergedEnv["SWIFT_APP_STATE_ROOT"] = tenantRoot

        return RoomLaunch(
            tool: tool,
            model: model,
            promptText: promptText,
            promptFile: promptFile,
            timeout: timeout,
            env: mergedEnv,
            workdir: workdir ?? layout.roomURL.path
        )
    }
}
