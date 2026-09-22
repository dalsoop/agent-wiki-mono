import Foundation
import OpportunityIntelKit

/// 기회/공고/딜 수집 노드 공용 프로토콜
public protocol OpportunityIngestNode: Sendable {
    /// 노드 고유 식별자 (예: "kstartup-rss", "dc-ai-board", "openai-pricing")
    var nodeId: String { get }
    /// 취급 카테고리 (예: "gov-grants", "subscription-deals")
    var category: String { get }
    /// 수집 실행 메서드
    func ingest() async throws -> [OpportunityIntelItem]
}
