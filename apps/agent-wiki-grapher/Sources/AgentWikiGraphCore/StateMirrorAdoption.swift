import Foundation
import StateMirrorKit

/// 상태 미러 게시 지점 — 함대 계약(CLAUDE.md "앱 상태 미러").
///
/// 그래프 인덱스 요약을 `~/.swift-app-state/agent-wiki-graph.json` 으로 게시해
/// 에이전트·스크립트가 스크린샷 없이 `swift-app-router state agent-wiki-graph` 로 읽는다.
public enum StateMirrorAdoption {
    /// StateMirror 파일 키 — `~/.swift-app-state/agent-wiki-graph.json`.
    public static let appName = "agent-wiki-graph"

    public struct State: Codable, Sendable {
        public var status: String
        public var generatedAt: Date
        public var root: String
        public var nodeCount: Int
        public var edgeCount: Int
        public var orphanCount: Int
        public var objectFileCount: Int
        public var indexedAt: Date?

        public init(status: String = "ok", generatedAt: Date = Date(),
                    root: String = "", nodeCount: Int = 0, edgeCount: Int = 0,
                    orphanCount: Int = 0, objectFileCount: Int = 0, indexedAt: Date? = nil) {
            self.status = status
            self.generatedAt = generatedAt
            self.root = root
            self.nodeCount = nodeCount
            self.edgeCount = edgeCount
            self.orphanCount = orphanCount
            self.objectFileCount = objectFileCount
            self.indexedAt = indexedAt
        }
    }

    /// 인덱스 로드/재빌드 직후 호출 — 서비스 요약을 미러에 반영.
    public static func publish(summary: AgentWikiGraphService.StatusSummary) {
        StateMirror.publish(app: appName, State(
            status: "ok",
            root: summary.root,
            nodeCount: summary.nodeCount,
            edgeCount: summary.edgeCount,
            orphanCount: summary.orphanCount,
            objectFileCount: summary.objectFileCount,
            indexedAt: summary.indexedAt
        ))
    }
}
