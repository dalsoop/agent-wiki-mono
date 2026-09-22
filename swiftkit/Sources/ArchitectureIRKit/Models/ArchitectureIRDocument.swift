import Foundation

/// 모노레포 전체 아키텍처의 Typed JSON IR 단일 진실의 원천(SSOT).
public struct ArchitectureIRDocument: Codable, Sendable, Equatable {
    /// IR 스키마 버전 (Semantic Versioning, 예: "1.0.0")
    public var schemaVersion: String
    
    /// 스캔 시점 메타데이터 및 거버넌스 헌법 요약
    public var metadata: ArchitectureMetadata
    
    /// 아키텍처 노드 집합 (Apps, SwiftKits, Host Tools, MCPs)
    public var nodes: [ArchitectureNode]
    
    /// 컴포넌트 간 상호작용 엣지 집합
    public var edges: [ArchitectureEdge]

    public init(
        schemaVersion: String = "1.0.0",
        metadata: ArchitectureMetadata,
        nodes: [ArchitectureNode] = [],
        edges: [ArchitectureEdge] = []
    ) {
        self.schemaVersion = schemaVersion
        self.metadata = metadata
        self.nodes = nodes
        self.edges = edges
    }

    public var nodeIndex: [String: ArchitectureNode] {
        Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
    }

    public var outgoingEdges: [String: [ArchitectureEdge]] {
        Dictionary(grouping: edges, by: \.source)
    }

    public var incomingEdges: [String: [ArchitectureEdge]] {
        Dictionary(grouping: edges, by: \.target)
    }
}
