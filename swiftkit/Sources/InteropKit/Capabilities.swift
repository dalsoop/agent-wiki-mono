import Foundation

// capabilities 스키마(docs/app-interop-contract.md 정본과 1:1).
// 필드를 늘리거나 이름을 바꾸려면 정본 문서를 먼저 고친다.
public struct Capabilities: Codable, Equatable, Sendable {
    /// CLI 서브커맨드 자기소개 한 줄.
    public struct Command: Codable, Equatable, Sendable {
        public let name: String
        public let summary: String
        /// `--json` 지원 여부 — 기계 소비 가능 표시.
        public let json: Bool

        public init(name: String, summary: String, json: Bool) {
            self.name = name
            self.summary = summary
            self.json = json
        }
    }

    /// 조회 가능한 상태 파일 선언(계약 3조: 상태는 파일로).
    public struct StateFile: Codable, Equatable, Sendable {
        public let path: String
        public let what: String

        public init(path: String, what: String) {
            self.path = path
            self.what = what
        }
    }

    /// 생존 확인 방법. freshness 파일의 mtime 침묵 = 센서 죽음(가야 SensorHealth 소비).
    public struct Health: Codable, Equatable, Sendable {
        public let command: String
        public let freshness: String

        public init(command: String, freshness: String) {
            self.command = command
            self.freshness = freshness
        }
    }

    /// 런타임 의존성 한 줄. MD 목록 대신 capabilities 에 둔다.
    /// `kind` 는 문자열(전방호환) — 알려진 값은 `DependencyKind` 상수.
    public struct Dependency: Codable, Equatable, Sendable {
        public let id: String
        public let kind: String
        public let ref: String
        public let required: Bool
        public let why: String
        /// `kind == cli` 일 때 기대 서브커맨드(없으면 nil).
        public let commands: [String]?

        public init(
            id: String,
            kind: String,
            ref: String,
            required: Bool = true,
            why: String,
            commands: [String]? = nil
        ) {
            self.id = id
            self.kind = kind
            self.ref = ref
            self.required = required
            self.why = why
            self.commands = commands
        }
    }

    /// 앱이 소유하는 MD 한 건. 파일 경로가 아니라 등록 레코드.
    public struct Document: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let kind: String
        public let layer: String
        public let trigger: String
        public let path: String

        public init(
            id: String,
            name: String,
            kind: String,
            layer: String,
            trigger: String,
            path: String
        ) {
            self.id = id
            self.name = name
            self.kind = kind
            self.layer = layer
            self.trigger = trigger
            self.path = path
        }
    }

    public enum DocumentKind {
        public static let skill = "skill"
        public static let instruction = "instruction"
        public static let pointer = "pointer"
    }

    public enum DocumentLayer {
        public static let user = "user"
        public static let workspace = "workspace"
        public static let app = "app"
        public static let hostOfficial = "hostOfficial"
        public static let homePointer = "homePointer"
        public static let bundled = "bundled"

        public static let rank: [String: Int] = [
            user: 0, workspace: 1, app: 2, hostOfficial: 3, homePointer: 4, bundled: 5,
        ]
    }

    public enum DocumentTrigger {
        public static let always = "always"
        public static let cwd = "cwd"
        public static let onDemand = "onDemand"
    }

    /// capabilities `stateRoot.env` — `agent-tenant-isolation-manager check` 가 이 선언을 본다.
    public struct StateRoot: Codable, Equatable, Sendable {
        public let env: String

        public init(env: String) {
            self.env = env
        }
    }

    /// 알려진 dependency kind 값. 새 kind 는 계약 문서에 먼저 추가한다.
    public enum DependencyKind {
        public static let command = "command"
        public static let cli = "cli"
        public static let brewFormula = "brew.formula"
        public static let brewCask = "brew.cask"
        public static let path = "path"
        public static let permission = "permission"
        public static let credential = "credential"
    }

    public let name: String
    /// **이 앱이 무엇을 하는 물건인가** — 한 줄. 지도(agent-app-registry)와 재사용 판정이
    /// 개념으로 앱을 찾을 수 있게 하는 유일한 필드다.
    ///
    /// 없으면 어떤 일이 벌어지는가(실측 2026-08-10): 293개 앱 중 292개에 설명이 없어
    /// `agent-app-registry search "객체화"` 가 0건을 냈다. 검색이 앱 이름과 명령 이름
    /// 문자열만 훑으니, 개념어로는 아무것도 못 찾고 `search "파일"` 은 `add-file`·
    /// `cookies-import-file` 같은 **명령 이름 조각** 40건을 쏟아냈다. 사람도 에이전트도
    /// "이 일을 하는 앱이 뭐지" 에 답하지 못한다.
    ///
    /// 하위호환: 옛 payload 에 없으면 빈 문자열로 디코드된다(계약 위반은 lint 가 잡는다).
    public let purpose: String
    /// 이 앱의 번들 ID(`CFBundleIdentifier`). 실행 파일에서 자동 해석되므로 앱은 적지 않는다.
    ///
    /// 없으면 어떤 일이 벌어지는가: 실행 중인 프로세스를 함대 앱으로 판정할 축이 없어
    /// 소비자가 `net.ranode.` **접두사 추측**에 기댄다(fleet-dock 일괄 종료가 그랬다).
    /// 접두사는 규칙이 아니라 관행이라, 다른 도메인으로 낸 앱은 조용히 목록에서 빠진다.
    ///
    /// 하위호환: 옛 payload 에 없으면 빈 문자열 — 소비자는 빈 값을 "모른다"로 읽는다.
    public let bundleId: String
    /// 테넌트 격리 env 이름. 없으면 키를 인코딩하지 않는다(옛 JSON 하위호환).
    public let stateRoot: StateRoot?
    public let version: String
    public let cli: String
    public let commands: [Command]
    public let state: [StateFile]
    public let health: Health
    /// 런타임 의존. 없으면 빈 배열(하위호환). 정본은 CLI 출력 — USAGE/README 목록 금지.
    public let depends: [Dependency]
    /// 이 앱이 소유하는 MD 레코드. 없으면 빈 배열. 합성은 agent-md-ssot-manager records.
    public let documents: [Document]
    /// 이 앱이 **소유**하는 절차. 없으면 빈 배열(하위호환). JobSpec·wiki task 가 아니다.
    public let procedures: [Procedure]
    /// 이 CLI 가 내는 앱 연동 교환. 없으면 빈 배열. 소비자는 `AppCLIExchange` 만 부른다.
    public let exchanges: [AppCLIExchange.Advertised]

    public struct Owned: Sendable, Equatable {
        public var depends: [Dependency]
        public var documents: [Document]
        public var procedures: [Procedure]
        public var exchanges: [AppCLIExchange.Advertised]
        public var stateRoot: StateRoot?

        public init(
            depends: [Dependency] = [],
            documents: [Document] = [],
            procedures: [Procedure] = [],
            exchanges: [AppCLIExchange.Advertised] = [],
            stateRoot: StateRoot? = CapabilitiesIdentity.stateRoot()
        ) {
            self.depends = depends
            self.documents = documents
            self.procedures = procedures
            self.exchanges = exchanges
            self.stateRoot = stateRoot
        }
    }

    public init(
        name: String,
        purpose: String = CapabilitiesIdentity.purpose(),
        bundleId: String = CapabilitiesIdentity.bundleId(),
        version: String = CLIMarketingVersion.current(),
        cli: String,
        commands: [Command],
        state: [StateFile],
        health: Health,
        owned: Owned
    ) {
        self.name = name
        self.purpose = purpose
        self.bundleId = bundleId
        self.stateRoot = owned.stateRoot
        self.version = version
        self.cli = cli
        self.commands = commands
        self.state = state
        self.health = health
        self.depends = owned.depends
        self.documents = owned.documents
        self.procedures = owned.procedures
        self.exchanges = owned.exchanges
    }

    /// 하위호환 — 축을 직접 나열하는 옛 호출부(함대 222곳)도 그대로 컴파일된다.
    /// 새 코드는 `owned:` 그룹 이니셜라이저로 쓴다. 둘 다 같은 저장 프로퍼티에 쓴다.
    public init(
        name: String,
        purpose: String = CapabilitiesIdentity.purpose(),
        bundleId: String = CapabilitiesIdentity.bundleId(),
        version: String = CLIMarketingVersion.current(),
        cli: String,
        commands: [Command],
        state: [StateFile],
        health: Health,
        depends: [Dependency] = [],
        documents: [Document] = [],
        procedures: [Procedure] = [],
        exchanges: [AppCLIExchange.Advertised] = []
    ) {
        self.name = name
        self.purpose = purpose
        self.bundleId = bundleId
        self.stateRoot = CapabilitiesIdentity.stateRoot()
        self.version = version
        self.cli = cli
        self.commands = commands
        self.state = state
        self.health = health
        self.depends = depends
        self.documents = documents
        self.procedures = procedures
        self.exchanges = exchanges
    }

    private enum CodingKeys: String, CodingKey {
        case name, purpose, bundleId, stateRoot, version, cli, commands, state, health
        case depends, documents, procedures, exchanges, facts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        // 하위호환: 아직 purpose 를 안 채운 앱이 292개다(2026-08-10). 없으면 빈 문자열로
        // 받아 디코드를 살리고, 채우라는 압박은 lint 계약 게이트가 맡는다.
        purpose = try container.decodeIfPresent(String.self, forKey: .purpose) ?? ""
        // 하위호환: 옛 스냅샷엔 번들 ID 축이 없다. 빈 문자열은 "모른다"이지 "없다"가 아니다.
        bundleId = try container.decodeIfPresent(String.self, forKey: .bundleId) ?? ""
        stateRoot = try container.decodeIfPresent(StateRoot.self, forKey: .stateRoot)
        version = try container.decode(String.self, forKey: .version)
        cli = try container.decode(String.self, forKey: .cli)
        // 레거시 관용 (실측 2026-08-06): 구식 registry 항목 3개가 여기서 디코드에
        // 실패해 **검색·조회에서 통째로 사라졌다** (267 등록 · 264 스캔).
        // - `commands` 가 문자열 배열인 옛 스키마 → summary 없는 Command 로 받는다.
        // - `state`/`health` 누락 → 빈 값. 없는 계약을 지어내지 않는다 — 비었다고 둔다.
        do {
            commands = try container.decode([Command].self, forKey: .commands)
        } catch {
            do {
                let names = try container.decode([String].self, forKey: .commands)
                commands = names.map { Command(name: $0, summary: "", json: false) }
            } catch {
                commands = []
            }
        }
        state = (try? container.decode([StateFile].self, forKey: .state)) ?? []
        health = (try? container.decode(Health.self, forKey: .health))
            ?? Health(command: "", freshness: "")
        depends = try container.decodeIfPresent([Dependency].self, forKey: .depends) ?? []
        documents = try container.decodeIfPresent([Document].self, forKey: .documents) ?? []
        procedures = try container.decodeIfPresent([Procedure].self, forKey: .procedures) ?? []
        exchanges = try container.decodeIfPresent([AppCLIExchange.Advertised].self, forKey: .exchanges)
            ?? container.decodeIfPresent([AppCLIExchange.Advertised].self, forKey: .facts)
            ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(purpose, forKey: .purpose)
        try container.encode(bundleId, forKey: .bundleId)
        try container.encodeIfPresent(stateRoot, forKey: .stateRoot)
        try container.encode(version, forKey: .version)
        try container.encode(cli, forKey: .cli)
        try container.encode(commands, forKey: .commands)
        try container.encode(state, forKey: .state)
        try container.encode(health, forKey: .health)
        try container.encode(depends, forKey: .depends)
        try container.encode(documents, forKey: .documents)
        try container.encode(procedures, forKey: .procedures)
        try container.encode(exchanges, forKey: .exchanges)
    }
}

extension Capabilities {
    /// 선언 경로는 `~/...` 로 적히므로 소비 시점에 확장한다.
    public static func expandingTilde(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    /// 이 프로세스 카드에서 name·cli 를 민트한다. `Capabilities(cli:)` 손조립 leftover 를 피한다.
    public static func mintingThisProcess(
        version: String,
        commands: [Command],
        state: [StateFile],
        depends: [Dependency] = [],
        documents: [Document] = [],
        procedures: [Procedure] = [],
        exchanges: [AppCLIExchange.Advertised] = []
    ) -> Capabilities {
        let name = HostPlatform.liveCLIName()
        let cli = HostPlatform.liveCLIPath()
        let freshness = state.first?.path ?? ""
        return Capabilities(
            name: name,
            version: version,
            cli: cli,
            commands: commands,
            state: state,
            health: Health(command: "\(cli) capabilities", freshness: freshness),
            depends: depends,
            documents: documents,
            procedures: procedures,
            exchanges: exchanges
        )
    }
}


extension Capabilities {
    /// 레지스트리 SSOT 쓰기 직전 정규화.
    /// - `cli` → 실행 가능 절대경로(가능하면)
    /// - `health.command` → 항상 `<abs-cli> capabilities`
    /// 앱 선언이 version/status/projects 여도 upsert 단일 choke 에서 강제한다.
    public func normalizedForRegistry() -> Capabilities {
        let absCLI = Self.resolveAbsoluteCLI(cli)
        return Capabilities(
            name: name,
            // purpose 를 빠뜨리면 **저장 시점에 설명이 증발한다** — 앱이 아무리 잘 선언해도
            // 레지스트리에는 안 남아 검색이 다시 이름·명령만 훑게 된다(2026-08-10 실측: 이
            // 누락 때문에 새 필드를 넣고도 검색 결과가 0건이었다).
            purpose: purpose,
            // purpose 와 같은 이유로 여기서 다시 실어야 한다. 기본값에 맡기면 **upsert 를
            // 부른 쪽(ship 훅)의 번들 ID** 가 박힌다 — 앱마다 다른 값이 하나로 뭉갠다.
            bundleId: bundleId,
            version: version,
            cli: absCLI,
            commands: commands,
            state: state,
            health: Health(command: "\(absCLI) capabilities", freshness: health.freshness),
            owned: Owned(
                depends: depends,
                documents: documents,
                procedures: procedures,
                exchanges: exchanges,
                stateRoot: stateRoot
            )
        )
    }

    /// `/opt/homebrew/bin/<name>` · `/usr/local/bin` · `~/.local/bin` · which 순.
    public static func resolveAbsoluteCLI(_ hint: String) -> String {
        #if os(macOS)
        let fm = FileManager.default
        let name = URL(fileURLWithPath: hint).lastPathComponent
        var candidates: [String] = []
        if hint.hasPrefix("/"), fm.isExecutableFile(atPath: hint) {
            candidates.append(hint)
        }
        let home = NSHomeDirectory()
        candidates.append(contentsOf: [
            HostPlatform.cliBinPath(name),
            "/usr/local/bin/\(name)",
            "\(home)/.local/bin/\(name)",
        ])
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // 파일이 아직 없어도 ship 직후 관례 경로로 PATH 그림자를 피한다.
        return HostPlatform.cliBinPath(name)
        #else
        hint
        #endif
    }
}
