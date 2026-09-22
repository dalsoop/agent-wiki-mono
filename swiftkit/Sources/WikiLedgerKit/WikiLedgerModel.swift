import Foundation
import GraphEngineKit

/// Agent Wiki 원장 객체 = 그래프 노드. GraphEngineKit.GraphNode 에 부합.
///
/// 원장(`~/gujo-wiki`)의 객체는 YAML frontmatter 에 정체성을 갖는 평면 마크다운.
/// 이 킷은 그것을 read-only 로 모델링한다 — 원장을 결코 쓰지 않는다(쓰기는 reaper 앱).
public struct WikiNode: GraphNode, Codable, Sendable {
    /// 객체 sha256 (frontmatter `id`).
    public let id: String
    /// `type:` (evidence/decision/concept/run/playbook/entity/evaluation…).
    public let type: String
    /// `author:` (예: agent:claude@macbook, llmwiki-import).
    public let author: String
    /// `published:` ISO8601.
    public let published: String
    /// `title:` (원문 그대로). GraphNode.displayLabel 로도 쓰임(alias 해상).
    public let title: String
    /// 원장 루트 기준 상대 경로(진단용).
    public let path: String

    public var displayLabel: String { title }

    public init(id: String, type: String, author: String, published: String, title: String, path: String) {
        self.id = id
        self.type = type
        self.author = author
        self.published = published
        self.title = title
        self.path = path
    }
}

/// 위키 엣지 종류. rawValue 가 GraphEdge.kind 태그.
public enum WikiEdgeKind: String, Sendable, Codable, CaseIterable {
    case cite
    case supersedes
    case retracts
    case observes
    case batch
    case wikilink
    case instanceOf = "instance-of"
}

/// 위키 방향 엣지. GraphEngineKit.GraphEdge 에 부합.
public struct WikiEdge: GraphEdge, Codable, Sendable {
    public let from: String
    public let to: String
    public let kind: String
    public let relation: String?

    public var displayKind: WikiEdgeKind? { WikiEdgeKind(rawValue: kind) }

    public init(from: String, to: String, kind: WikiEdgeKind, relation: String? = nil) {
        self.from = from
        self.to = to
        self.kind = kind.rawValue
        self.relation = relation
    }

    /// 캐시 복원용(이미 rawValue 로 직렬화된 것에서).
    public init(from: String, to: String, kindRaw: String, relation: String? = nil) {
        self.from = from
        self.to = to
        self.kind = kindRaw
        self.relation = relation
    }
}
