import Foundation
import AgentRegistryKit

/// AgentDef 기반 카드. 선언된 에이전트(~/.agent-apps/agents.json)를 카드로 평탄화.
public struct AgentCard: CatalogCard, Equatable {
    public let def: AgentDef
    public init(def: AgentDef) { self.def = def }

    public var cardID: String { def.id }
    public var title: String { def.name }
    public var kind: CardKind { .agent }
    public var subtitle: String? { def.persona }
    public var tool: String? { def.agent }
    public var path: String? { nil }            // AgentDef 는 레지스트리 JSON이 정본
    public var summary: String? { def.notes }
}
