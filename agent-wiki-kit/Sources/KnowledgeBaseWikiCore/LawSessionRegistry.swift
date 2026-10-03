import Foundation
import SessionKit
import StateRootKit
import WikiLedgerKit

// 세션 등록 — 세션마다 파일 하나(`~/.agent-wiki/sessions/<세션 id>.json`, 상태 루트 기준).
// 근거: docs/business-rules.md "작성자와 모델 기록", docs/architecture.md "agent-law"(`hook session`),
// docs/security.md(필요한 칸만 남긴다), 결정 0007(옛 훅이 세션 시작 출처를 runtime 에 넣던 결함).
// 옛 단일 파일 `~/.agent-wiki/authoring.json` 에는 더 쓰지 않는다.

/// 세션 등록 파일 한 벌. 아는 값만 적는다(없는 칸은 파일에 키가 없다).
public struct LawSessionRegistration: Codable, Sendable, Equatable {
    public var sessionID: String
    public var runtime: String?
    public var runtimeVersion: String?
    public var model: String?
    public var effort: String?
    /// 실행 환경의 테넌트 slug(`tenant:` 를 뗀 값). 무표시면 비운다 — personal 판정은 적재 쪽이 한다.
    public var tenant: String?
    /// 설정의 `currentDevice`.
    public var device: String?
    public var workingDirectory: String?
    /// 처음 등록한 시각(ISO 8601). 재개·압축 훅이 다시 와도 바꾸지 않는다.
    public var startedAt: String?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session-id"
        case runtime
        case runtimeVersion = "runtime-version"
        case model, effort, tenant, device
        case workingDirectory = "cwd"
        case startedAt = "started-at"
    }

    public init(
        sessionID: String, runtime: String? = nil, runtimeVersion: String? = nil, model: String? = nil,
        effort: String? = nil, tenant: String? = nil, device: String? = nil, workingDirectory: String? = nil,
        startedAt: String? = nil
    ) {
        self.sessionID = sessionID
        self.runtime = runtime
        self.runtimeVersion = runtimeVersion
        self.model = model
        self.effort = effort
        self.tenant = tenant
        self.device = device
        self.workingDirectory = workingDirectory
        self.startedAt = startedAt
    }

    /// 같은 세션의 새 훅 값으로 덮는다. 새 값이 아는 칸만 바꾸고, 시작 시각은 처음 값을 지킨다.
    public func merging(_ newer: LawSessionRegistration) -> LawSessionRegistration {
        LawSessionRegistration(
            sessionID: sessionID,
            runtime: newer.runtime ?? runtime,
            runtimeVersion: newer.runtimeVersion ?? runtimeVersion,
            model: newer.model ?? model,
            effort: newer.effort ?? effort,
            tenant: newer.tenant ?? tenant,
            device: newer.device ?? device,
            workingDirectory: newer.workingDirectory ?? workingDirectory,
            startedAt: startedAt ?? newer.startedAt)
    }

    /// 모델 기록 칸(공포의 마지막 단계 값).
    public var modelRecord: LawModelRecord {
        LawModelRecord(runtime: runtime, runtimeVersion: runtimeVersion, model: model, effort: effort)
    }
}

/// 세션 등록 디렉터리. 시험은 `directory` 를 명시한다 — 기본값은 실제 상태 루트다.
public struct LawSessionRegistry: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 상태 루트 기준 `~/.agent-wiki/sessions`.
    public static var standard: LawSessionRegistry {
        LawSessionRegistry(directory: StateRootKit.url(".agent-wiki/sessions"))
    }

    /// 파일 이름으로 쓸 수 있는 세션 id 인가(경로 구분자·`..`·숨김 이름 거부).
    public static func isValidSessionID(_ sessionID: String) -> Bool {
        guard !sessionID.isEmpty, sessionID.count <= 200, sessionID.first != "." else { return false }
        return sessionID.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "-" || $0 == "_" || $0 == "."
        }
    }

    public func fileURL(sessionID: String) -> URL? {
        guard Self.isValidSessionID(sessionID) else { return nil }
        return directory.appendingPathComponent("\(sessionID).json")
    }

    /// 세션 id 로 등록을 읽는다. 없거나 깨졌으면 nil.
    public func registration(sessionID: String) -> LawSessionRegistration? {
        guard let url = fileURL(sessionID: sessionID), let data = try? Data(contentsOf: url) else { return nil }
        guard var registration = try? JSONDecoder().decode(LawSessionRegistration.self, from: data) else { return nil }
        registration.sessionID = sessionID
        return registration
    }

    /// 실행 도구가 넘겨준 세션 id 환경 변수로 자기 세션의 등록을 찾는다. 세션 id 가 없으면 nil — 다른 세션을 추정하지 않는다.
    public func registration(environment: [String: String]) -> LawSessionRegistration? {
        guard let sessionID = LawSessionEnvironment.sessionID(environment) else { return nil }
        return registration(sessionID: sessionID)
    }

    /// 등록을 남긴다. 같은 세션 파일이 있으면 아는 값만 덮고, 다른 세션 파일은 건드리지 않는다.
    /// 원자적 쓰기. 실패해도 던지지 않고 false.
    @discardableResult
    public func register(_ update: LawSessionRegistration) -> Bool {
        guard let url = fileURL(sessionID: update.sessionID) else { return false }
        let merged = registration(sessionID: update.sessionID)?.merging(update) ?? update
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(merged) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

/// 실행 도구 환경 변수 단계. 변수 이름은 지원 CLI 목록(`SupportedAIAgentCLI`) 한 곳에 있다.
public enum LawSessionEnvironment {
    /// 지금 실행 도구의 세션 id. 식별된 도구의 변수 → 목록 순서의 첫 변수.
    public static func sessionID(_ environment: [String: String]) -> String? {
        if let cli = SupportedAIAgentCLI.current(in: environment), let id = cli.sessionID(in: environment) {
            return id
        }
        return SupportedAIAgentCLI.allCases.lazy.compactMap { $0.sessionID(in: environment) }.first
    }

    /// 실행 도구 환경 변수에서 읽은 모델 기록(아는 값만). 기록 어휘에 없는 추론 강도는 버린다.
    public static func toolRecord(_ environment: [String: String]) -> LawModelRecord {
        guard let cli = SupportedAIAgentCLI.current(in: environment) else { return LawModelRecord() }
        return LawModelRecord(
            runtime: LawRuntime(cli: cli)?.rawValue, runtimeVersion: cli.version(in: environment),
            model: cli.model(in: environment), effort: LawSessionHook.effortValue(cli.effort(in: environment)))
    }
}

extension LawRuntime {
    /// 지원 CLI → 기록 어휘. 기록 어휘에 없는 도구는 nil.
    public init?(cli: SupportedAIAgentCLI) {
        switch cli {
        case .claude: self = .claudeCode
        case .codex: self = .codex
        case .grok: self = .grok
        case .agy: self = .antigravity
        case .opencode, .cursor: return nil
        }
    }
}

/// `hook session` 의 본체. 어떤 입력에서도 던지지 않는다.
public enum LawSessionHook {
    /// 훅 입력 JSON 의 키 후보(앞이 먼저). Claude Code·Codex SessionStart 는 `session_id`·`model`·`cwd`·
    /// `transcript_path`·`source` 를 준다. `source`(startup·resume·clear·compact·fork)는 세션 시작 출처라 읽지 않는다.
    static let sessionKeys = ["session_id", "sessionId"]
    static let modelKeys = ["model", "model_id", "modelId"]
    static let effortKeys = ["effort", "reasoning_effort"]
    static let workingDirectoryKeys = ["cwd"]
    static let transcriptKeys = ["transcript_path", "transcriptPath"]

    /// 훅 입력과 환경으로 등록 한 벌을 만든다. 세션 id 를 모르면 nil(아무것도 쓰지 않는다).
    /// - Parameters:
    ///   - explicit: 훅 명령의 명시 인자(`--runtime` 등). 입력보다 먼저다.
    ///   - tenantHomeDirectory: 테넌트 context 파일을 찾을 홈(시험 주입용).
    public static func registration(
        payload: Data,
        explicit: LawModelRecord = LawModelRecord(),
        explicitSessionID: String? = nil,
        environment: [String: String],
        device: String?,
        tenantHomeDirectory: String = NSHomeDirectory(),
        currentDirectory: String? = nil,
        now: Date = Date()
    ) -> LawSessionRegistration? {
        let event = decodeObject(payload)
        func pick(_ keys: [String]) -> String? {
            for key in keys {
                if let value = clean(event[key] as? String) { return value }
            }
            return nil
        }
        guard let sessionID = clean(explicitSessionID) ?? pick(sessionKeys) ?? LawSessionEnvironment.sessionID(environment),
              LawSessionRegistry.isValidSessionID(sessionID)
        else { return nil }

        let tool = LawSessionEnvironment.toolRecord(environment)
        let transcriptOwner = pick(transcriptKeys).flatMap { path in
            SupportedAIAgentCLI.allCases.first { $0.ownsPath(path) }
        }
        let runtime = runtimeValue(explicit.runtime) ?? tool.runtime
            ?? transcriptOwner.flatMap { LawRuntime(cli: $0)?.rawValue }

        let tenant = StateRootKit.currentTenantID(environment: environment, homeDirectory: tenantHomeDirectory)
            .map(StateRootKit.tenantSlug(from:)).flatMap { clean($0) }

        return LawSessionRegistration(
            sessionID: sessionID,
            runtime: runtime,
            runtimeVersion: clean(explicit.runtimeVersion) ?? tool.runtimeVersion,
            model: clean(explicit.model) ?? pick(modelKeys) ?? tool.model,
            effort: effortValue(explicit.effort) ?? effortValue(pick(effortKeys)) ?? tool.effort,
            tenant: tenant,
            device: clean(device),
            workingDirectory: pick(workingDirectoryKeys) ?? clean(currentDirectory),
            startedAt: timestamp(now))
    }

    /// 훅 진입점. 등록을 남겼으면 true. 실패·잘못된 입력에도 던지지 않는다.
    @discardableResult
    public static func run(
        payload: Data,
        registry: LawSessionRegistry,
        explicit: LawModelRecord = LawModelRecord(),
        explicitSessionID: String? = nil,
        environment: [String: String],
        device: String?,
        tenantHomeDirectory: String = NSHomeDirectory(),
        currentDirectory: String? = nil,
        now: Date = Date()
    ) -> Bool {
        guard let registration = registration(
            payload: payload, explicit: explicit, explicitSessionID: explicitSessionID, environment: environment,
            device: device, tenantHomeDirectory: tenantHomeDirectory, currentDirectory: currentDirectory, now: now)
        else { return false }
        return registry.register(registration)
    }

    /// 기록 어휘(`LawRuntime`)에 있는 값만 runtime 으로 받는다. 세션 시작 출처 같은 다른 값은 버린다.
    static func runtimeValue(_ raw: String?) -> String? {
        guard let value = clean(raw), LawRuntime(rawValue: value) != nil else { return nil }
        return value
    }

    /// 기록 어휘(`LawEffort`)에 있는 값만 받는다.
    static func effortValue(_ raw: String?) -> String? {
        guard let value = clean(raw)?.lowercased(), LawEffort(rawValue: value) != nil else { return nil }
        return value
    }

    static func clean(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty,
              !value.contains(where: \.isNewline)
        else { return nil }
        return value
    }

    static func decodeObject(_ data: Data) -> [String: Any] {
        guard !data.isEmpty else { return [:] }
        do {
            return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            return [:]
        }
    }

    static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
