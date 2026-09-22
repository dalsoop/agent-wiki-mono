import Foundation

/// 블록 단위 토큰 절감 — 인포커터 "블록 숨기기" 승화.
///
/// 숨김 ≠ 삭제. 접힌 블록은 1줄 스텁으로 남겨 에이전트가 expand 로 펼칠 수 있다.
/// DOM·스킬·타임라인·CLI 출력 전 레이어에 동일 개념 적용.
public protocol BlockFilterable {
    associatedtype Block: Identifiable
    func blocks() -> [Block]
    func relevance(_ block: Block, for context: BlockFilterContext) -> Double
}

public struct BlockFilterContext: Sendable {
    public let keywords: [String]
    public let maxTokens: Int

    public init(keywords: [String] = [], maxTokens: Int = 4000) {
        self.keywords = keywords
        self.maxTokens = maxTokens
    }
}

/// relevance 내림차순으로 예산 안에서 블록 선택.
public enum BlockFilter {
    public static func select<F: BlockFilterable>(
        from source: F, context: BlockFilterContext,
        tokenEstimate: (F.Block) -> Int
    ) -> (expanded: [F.Block], collapsed: [F.Block]) {
        let all = source.blocks()
        let scored = all.map { (block: $0, score: source.relevance($0, for: context)) }
            .sorted { $0.score > $1.score }
        var budget = context.maxTokens
        var expanded: [F.Block] = []
        var collapsed: [F.Block] = []
        for item in scored {
            let cost = tokenEstimate(item.block)
            if budget >= cost && item.score > 0 {
                expanded.append(item.block)
                budget -= cost
            } else {
                collapsed.append(item.block)
            }
        }
        return (expanded, collapsed)
    }
}
