import Foundation

/// 카드 종류 — agent-skills 의 HubItem.kind 와 같은 역할, 뷰-무관.
public enum CardKind: String, Sendable, Codable, Equatable {
    case agent
    case skill
}

/// 카드 공통 계약 — GUI 카드뷰와 CLI --json 이 **같은 데이터**를 쓰게 한다.
/// "파일 SSOT ↔ UI 같은 모양"의 접점: 렌더(뷰 또는 JSON)는 이 프로토콜만 안다.
public protocol CatalogCard: Sendable {
    var cardID: String { get }
    var title: String { get }
    var kind: CardKind { get }
    var subtitle: String? { get }
    var tool: String? { get }       // 백엔드/도구: "claude" | "codex" | ...
    var path: String? { get }       // 정본 파일 경로(있다면)
    var summary: String? { get }    // description/notes 발췌
}
