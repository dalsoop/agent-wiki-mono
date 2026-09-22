import Foundation
import CryptoKit

// MARK: - 1. 단어와 구문(AST) 분리 벡터 (AST Structural Vector)
/// AST 문법 구조와 구문 뼈대를 어휘(Identifier)로부터 분리한 64차원 정규화 구조 벡터
public struct ASTStructureVector: Codable, Sendable, Equatable {
    public let dimensions: [Double] // 64-D normalized vector

    public init(dimensions: [Double]) {
        self.dimensions = dimensions
    }

    /// AST 노드 종류 시퀀스로부터 구조 특징 벡터 추출 (어휘 불변성 유지)
    public static func extractFromASTSkeleton(nodeTypes: [String]) -> ASTStructureVector {
        var rawVector = [Double](repeating: 0.0, count: 64)
        for (idx, node) in nodeTypes.enumerated() {
            let hashVal = abs(node.hashValue) % 64
            let positionWeight = 1.0 / (Double(idx) + 1.0)
            rawVector[hashVal] += positionWeight
        }
        // L2 Normalization
        let norm = sqrt(rawVector.map { $0 * $0 }.reduce(0.0, +))
        let normalized = norm > 0 ? rawVector.map { $0 / norm } : rawVector
        return ASTStructureVector(dimensions: normalized)
    }

    /// 코사인 유사도
    public func cosineSimilarity(to other: ASTStructureVector) -> Double {
        guard dimensions.count == other.dimensions.count else { return 0.0 }
        let dotProduct = zip(dimensions, other.dimensions).map(*).reduce(0.0, +)
        return max(0.0, min(1.0, dotProduct))
    }
}

// MARK: - 2. 128차원 시맨틱 인텐트 융합 벡터 (Semantic Intent Vector)
/// 단어(Lexical) + 문장(Intent Sentence) + 구조(AST)가 융합된 고차원 인덱싱 벡터
public struct SemanticIntentVector: Codable, Sendable, Equatable {
    public let ruleId: String
    public let domainName: String
    public let intentDimensions: [Double] // 128-D normalized

    public init(ruleId: String, domainName: String, intentDimensions: [Double]) {
        self.ruleId = ruleId
        self.domainName = domainName
        self.intentDimensions = intentDimensions
    }

    /// 텍스트 문장과 구조 벡터로부터 128차원 인텐트 벡터 합성
    public static func synthesize(
        ruleId: String,
        domainName: String,
        intentSentence: String,
        structure: ASTStructureVector
    ) -> SemanticIntentVector {
        var vector = [Double](repeating: 0.0, count: 128)

        // 0~63차원: AST 구문 뼈대 (가중치 0.6)
        for i in 0..<min(64, structure.dimensions.count) {
            vector[i] = structure.dimensions[i] * 0.6
        }

        // 64~127차원: 자연어 의도 단어 및 도메인 의미 토큰 임베딩 (가중치 0.4)
        let words = intentSentence.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        for word in words {
            let hashVal = 64 + (abs(word.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }) % 64)
            vector[hashVal] += 0.4 / Double(max(1, words.count))
        }

        // L2 Normalization
        let norm = sqrt(vector.map { $0 * $0 }.reduce(0.0, +))
        let normalized = norm > 0 ? vector.map { $0 / norm } : vector

        return SemanticIntentVector(
            ruleId: ruleId,
            domainName: domainName,
            intentDimensions: normalized
        )
    }

    public func cosineSimilarity(to other: SemanticIntentVector) -> Double {
        guard intentDimensions.count == other.intentDimensions.count else { return 0.0 }
        let dotProduct = zip(intentDimensions, other.intentDimensions).map(*).reduce(0.0, +)
        return max(0.0, min(1.0, dotProduct))
    }
}

// MARK: - 3. 계층형 시맨틱 벡터 인덱서 (Semantic Vector Hierarchical Indexer)
public actor SemanticVectorIndexer {
    public struct ClusterNode: Sendable {
        public let clusterId: String
        public let domainName: String
        public var centroid: [Double]
        public var memberRuleIds: [String]
    }

    private var indexedVectors: [String: SemanticIntentVector] = [:] // ruleId -> Vector
    private var clusters: [String: ClusterNode] = [:]                // clusterId -> ClusterNode

    public init() {}

    /// 신규 룰 벡터 등록 및 동적 계층 인덱싱
    public func indexRule(vector: SemanticIntentVector) {
        indexedVectors[vector.ruleId] = vector

        // 가장 가까운 기존 클러스터 탐색
        var bestClusterId: String? = nil
        var maxSim = -1.0

        for (cId, cluster) in clusters where cluster.domainName == vector.domainName {
            let sim = computeCosine(v1: vector.intentDimensions, v2: cluster.centroid)
            if sim > maxSim {
                maxSim = sim
                bestClusterId = cId
            }
        }

        // 임계값(0.70) 이상이면 기존 클러스터에 흡수 및 센트로이드 갱신, 아니면 신규 마이크로 클러스터 개설
        if let bestId = bestClusterId, maxSim >= 0.70 {
            var target = clusters[bestId]!
            target.memberRuleIds.append(vector.ruleId)
            // 센트로이드 이동 평균 갱신
            let n = Double(target.memberRuleIds.count)
            for i in 0..<target.centroid.count {
                target.centroid[i] = (target.centroid[i] * (n - 1.0) + vector.intentDimensions[i]) / n
            }
            clusters[bestId] = target
        } else {
            let newClusterId = "cluster-\(vector.domainName)-\(clusters.count + 1)"
            clusters[newClusterId] = ClusterNode(
                clusterId: newClusterId,
                domainName: vector.domainName,
                centroid: vector.intentDimensions,
                memberRuleIds: [vector.ruleId]
            )
        }
    }

    /// 인텐트 및 구조 질의로부터 가장 관련성 높은 유사 룰 Top-K 고속 검색
    public func searchSimilar(query: SemanticIntentVector, topK: Int = 5) -> [(ruleId: String, similarity: Double)] {
        var results: [(ruleId: String, similarity: Double)] = []

        for (_, vector) in indexedVectors {
            let sim = query.cosineSimilarity(to: vector)
            results.append((vector.ruleId, sim))
        }

        results.sort { $0.similarity > $1.similarity }
        return Array(results.prefix(topK))
    }

    /// 현재 클러스터 개수
    public func clusterCount() -> Int {
        clusters.count
    }

    /// 전체 색인된 룰 개수
    public func totalIndexedCount() -> Int {
        indexedVectors.count
    }

    private func computeCosine(v1: [Double], v2: [Double]) -> Double {
        guard v1.count == v2.count else { return 0.0 }
        let dot = zip(v1, v2).map(*).reduce(0.0, +)
        return max(0.0, min(1.0, dot))
    }
}
