import Foundation
import KnowledgeBaseWikiCore

/// AgentWikiGlobal 월드 사람용 표시 이름 레지스트리 및 매핑.
public enum WorldDisplayRegistry {
    /// 기본 표준 디스플레이 명칭 사전
    public static let standardMappings: [String: String] = [
        "gujo-wiki": "조직 공유 원장 (Gujo Shared Ledger)",
        "person-yun-jeonghan": "윤정한 개인 주관 일지 (Jeonghan Personal Ledger)",
    ]

    /// world slug 및 명시적 display 값을 기반으로 사람용 친화적 표시 이름을 반환한다.
    public static func displayName(for slug: String, explicitDisplay: String? = nil) -> String {
        if let explicitDisplay, !explicitDisplay.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return explicitDisplay
        }
        return standardMappings[slug] ?? WorldDisplayNameMapper.defaultDisplayName(for: slug)
    }
}
