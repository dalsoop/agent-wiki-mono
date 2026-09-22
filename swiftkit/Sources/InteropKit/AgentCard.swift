import Foundation

/// 앱 하나를 에이전트에게 소개하는 카드.
///
/// 구조는 Google A2A `AgentCard` 를 따른다 — 웹은 `.well-known/agent-card.json`
/// 으로 서빙하지만 데스크톱 앱은 그럴 origin 이 없어 CLI 로 같은 카드를 낸다.
/// (agents.txt 명세가 "데스크톱·CLI 는 이 표준의 적용 대상이 아니다" 라고 명시한다.)
///
/// MCP 는 경쟁 상대가 아니라 `interfaces` 안의 한 항목이다 — 업계 관례가
/// "AgentCard 가 상위, MCP 서버는 그 안에 실린다" 이다.
///
/// 기존 `Capabilities`(37개 앱이 이미 씀)를 **감싸고 안 건드린다**. 카드는
/// 그 위에 skills·interfaces·extensions 를 얹는 층이다.
public struct AgentCard: Codable, Equatable, Sendable {
    /// 카드가 어디서 왔는지. 에이전트가 신선도를 판단하는 근거다.
    public enum Source: String, Codable, Sendable {
        /// 앱 CLI 를 직접 호출해 받았다. 정본이고 항상 최신.
        case app
        /// `~/.agent-apps/registry.json` 에서 읽었다. 설치 훅이 넣은 것이라
        /// 앱이 그 뒤로 바뀌었으면 낡았을 수 있다.
        case registry
        /// 앱도 레지스트리도 답을 못 해서 파일에서 조립했다.
        /// 이름·설명은 맞지만 명령·상태는 비어 있다.
        case fallback
    }

    public struct Provider: Codable, Equatable, Sendable {
        public let slug: String
        public let name: String
        public let version: String?
        public let description: String?

        public init(slug: String, name: String, version: String? = nil, description: String? = nil) {
            self.slug = slug
            self.name = name
            self.version = version
            self.description = description
        }
    }

    /// 이 앱이 할 수 있는 일 하나. A2A `AgentSkill` 에 대응한다.
    ///
    /// 본문은 카드에 안 담는다 — 길어지면 카드가 못 쓰게 된다. `doc` 에
    /// "어떻게 가져오는지" 만 적고 에이전트가 필요할 때 부른다(MCP 의
    /// `"dynamic"` 과 같은 발상).
    public struct Skill: Codable, Equatable, Sendable {
        public let id: String
        public let name: String
        public let description: String?
        /// 본문을 가져오는 방법. 예: `cli://myapp skill show <id>`
        public let doc: String?

        public init(id: String, name: String, description: String? = nil, doc: String? = nil) {
            self.id = id
            self.name = name
            self.description = description
            self.doc = doc
        }
    }

    /// 이 앱을 부르는 길 하나. A2A `AgentInterface` 에 대응한다.
    ///
    /// 앱마다 여러 개를 갖는다 — CLI 로도 부르고, 상태 파일로도 읽고,
    /// MCP 서버도 띄우고, URL scheme 도 받는다.
    public struct Interface: Codable, Equatable, Sendable {
        /// A2A 표준 이름. `cli` · `mcp` · `state` · `url` · `http`.
        public let protocolBinding: String
        /// 바인딩별 진입점. cli 면 명령 이름, state 면 파일 경로,
        /// mcp 면 서버를 띄우는 명령, url 이면 scheme.
        public let target: String
        public let description: String?

        public init(protocolBinding: String, target: String, description: String? = nil) {
            self.protocolBinding = protocolBinding
            self.target = target
            self.description = description
        }
    }

    /// 표준 필드로 안 담기는 앱별 능력. A2A `AgentExtension` 에 대응한다.
    ///
    /// 앱마다 조직·도메인이 달라 고정 스키마로는 안 맞는다. 여기에 id 와
    /// "어디서 가져오는지" 만 두고, 모르는 id 는 에이전트가 무시하면 된다.
    public struct Extension: Codable, Equatable, Sendable {
        public let id: String
        /// 가져오는 방법. 예: `cli://myapp todo --json`
        public let uri: String?
        public let description: String?

        public init(id: String, uri: String? = nil, description: String? = nil) {
            self.id = id
            self.uri = uri
            self.description = description
        }
    }

    public let specVersion: String
    public let source: Source
    public let provider: Provider
    /// 기존 계약(`docs/app-interop-contract.md`). 앱이 capabilities 를 안 내면 nil.
    public let capabilities: Capabilities?
    public let skills: [Skill]?
    public let interfaces: [Interface]?
    public let extensions: [Extension]?

    public static let currentSpecVersion = "1.0"

    public init(
        specVersion: String = AgentCard.currentSpecVersion,
        source: Source,
        provider: Provider,
        capabilities: Capabilities? = nil,
        skills: [Skill]? = nil,
        interfaces: [Interface]? = nil,
        extensions: [Extension]? = nil
    ) {
        self.specVersion = specVersion
        self.source = source
        self.provider = provider
        self.capabilities = capabilities
        self.skills = skills
        self.interfaces = interfaces
        self.extensions = extensions
    }
}

extension AgentCard {
    /// `capabilities.commands` 를 interfaces 로 환산한 편의 목록.
    /// 카드를 소비하는 쪽이 "이 앱을 어떻게 부르나" 를 한 곳에서 보게 한다.
    public var cliCommandNames: [String] {
        capabilities?.commands.map(\.name) ?? []
    }

    /// 이 카드가 실제 능력 정보를 담고 있는가.
    /// fallback 카드는 이름만 있고 명령이 비어 있어 구분이 필요하다.
    public var hasCapabilityDetail: Bool {
        guard let capabilities else { return false }
        return !capabilities.commands.isEmpty
    }
}
