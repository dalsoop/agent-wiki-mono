import Foundation
import SkillRegistryKit

/// SkillRef 기반 카드. 전역/워크스페이스 스킬(SKILL.md)을 카드로 평탄화.
public struct SkillCard: CatalogCard, Equatable {
    public let ref: SkillRef
    public init(ref: SkillRef) { self.ref = ref }

    public var cardID: String { ref.id }
    public var title: String { ref.name }
    public var kind: CardKind { .skill }
    public var subtitle: String? { ref.scope }   // "global" | "workspace"
    public var tool: String? { ref.tool }
    public var path: String? { ref.path }
    public var summary: String? { nil }          // 본문 파싱은 agent-skills 앱이 소유
}
