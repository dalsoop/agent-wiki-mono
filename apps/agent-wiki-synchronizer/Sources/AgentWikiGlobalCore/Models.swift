import Foundation

/// 예시 모델 — 실제 앱 도메인 타입으로 교체.
public struct AgentWikiGlobalItem: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}
