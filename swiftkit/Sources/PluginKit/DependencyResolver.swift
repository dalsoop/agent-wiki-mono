import Foundation

/// 앱 간 의존성 계산, 버전 호환성 검증 및 실행 플랜(DAG) 생성기
public final class DependencyResolver: Sendable {
    
    public struct ExecutionPlan: Equatable, Sendable {
        /// 단계별 실행 그룹. 각 단계(Inner Array) 내의 플러그인은 상호 의존성이 없으므로 완전히 병렬로 실행할 수 있습니다.
        public let stages: [[String]]
        
        /// 직렬화된 전체 실행 순서
        public var sequentialOrder: [String] {
            stages.flatMap { $0 }
        }
        
        public init(stages: [[String]]) {
            self.stages = stages
        }
    }
    
    public init() {}
    
    /// 주어진 타겟 앱들을 실행하기 위한 의존성 해석 및 병렬 실행 단계(Stages)를 계산합니다.
    /// - Parameters:
    ///   - targetIds: 실행하고자 하는 대상 앱/플러그인 ID 목록
    ///   - dependencyMap: [앱 ID: 의존하고 있는 앱 ID 목록]
    /// - Returns: 계산된 단계별 병렬 실행 플랜
    public func resolveExecutionPlan(
        targets targetIds: [String],
        dependencyMap: [String: [String]]
    ) throws -> ExecutionPlan {
        // 1. 필요한 모든 노드(타겟 + 전이적 의존성) 수집
        var visited = Set<String>()
        var requiredNodes = Set<String>()
        
        func collectDependencies(for id: String, path: [String]) throws {
            if path.contains(id) {
                let cycle = path + [id]
                throw PluginError.cycleDetected(cycle)
            }
            if visited.contains(id) { return }
            visited.insert(id)
            requiredNodes.insert(id)
            
            let deps = dependencyMap[id] ?? []
            for dep in deps {
                try collectDependencies(for: dep, path: path + [id])
            }
        }
        
        for target in targetIds {
            try collectDependencies(for: target, path: [])
        }
        
        // 2. Kahn's Algorithm 기반 Topological Sort 및 Stage Grouping (병렬화 계산)
        var inDegree: [String: Int] = [:]
        var graph: [String: [String]] = [:] // dep -> [dependents]
        
        for node in requiredNodes {
            inDegree[node] = 0
            graph[node] = []
        }
        
        for node in requiredNodes {
            let deps = dependencyMap[node] ?? []
            for dep in deps where requiredNodes.contains(dep) {
                graph[dep, default: []].append(node)
                inDegree[node, default: 0] += 1
            }
        }
        
        var stages: [[String]] = []
        var currentStage = requiredNodes.filter { inDegree[$0] == 0 }.sorted()
        var processedCount = 0
        
        while !currentStage.isEmpty {
            stages.append(currentStage)
            processedCount += currentStage.count
            
            var nextStageCandidates: [String] = []
            
            for node in currentStage {
                let dependents = graph[node] ?? []
                for dep in dependents {
                    inDegree[dep, default: 1] -= 1
                    if inDegree[dep] == 0 {
                        nextStageCandidates.append(dep)
                    }
                }
            }
            
            currentStage = nextStageCandidates.sorted()
        }
        
        if processedCount != requiredNodes.count {
            throw PluginError.cycleDetected(["복합 순환 의존성 감지됨"])
        }
        
        return ExecutionPlan(stages: stages)
    }
    
    /// 플러그인 버전 호환성 검증
    /// - Parameters:
    ///   - installedPlugins: 현재 설치된 플러그인 맵 [플러그인 ID: SemVer]
    ///   - requirements: 요구되는 의존성 목록 [PluginDependencyRequirement]
    public func validateVersionCompatibility(
        installedPlugins: [String: SemVer],
        requirements: [PluginDependencyRequirement]
    ) throws {
        for req in requirements {
            guard let installedVer = installedPlugins[req.pluginId] else {
                throw PluginError.missingDependencies("필수 플러그인 '\(req.pluginId)'가 설치되어 있지 않습니다.")
            }
            
            if !installedVer.satisfies(minVersion: req.minVersion, maxVersion: req.maxVersion) {
                let minClause = req.minVersion.map { " >= \($0)" } ?? ""
                let maxClause = req.maxVersion.map { " <= \($0)" } ?? ""
                throw PluginError.executionFailed(
                    pluginId: req.pluginId,
                    reason: "버전 불일치: 현재 설치된 버전(\(installedVer))이 요구 조건(\(req.pluginId)\(minClause)\(maxClause))을 만족하지 않습니다."
                )
            }
        }
    }
}
