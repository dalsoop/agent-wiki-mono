import Foundation

/// 450+ 모노레포 전체 앱의 의존성을 스캔하고 시뮬레이션/검증하는 도구
public struct FleetSimulationRunner: Sendable {
    
    public struct SimulationReport: Sendable {
        public let totalApps: Int
        public let appsWithDependencies: Int
        public let independentApps: Int
        public let totalDependencyLinks: Int
        public let detectedCycles: [[String]]
        public let maxPipelineDepth: Int
        public let sampleComplexPlans: [(target: String, plan: DependencyResolver.ExecutionPlan)]
    }
    
    public init() {}
    
    /// 지정된 dependencyMap을 기반으로 전체 함대 의존성 무결성 및 시뮬레이션을 실행합니다.
    public func simulateFleet(dependencyMap: [String: [String]]) -> SimulationReport {
        let resolver = DependencyResolver()
        var cycles: [[String]] = []
        var maxDepth = 0
        var complexPlans: [(target: String, plan: DependencyResolver.ExecutionPlan)] = []
        var totalLinks = 0
        var dependentAppsCount = 0
        
        for (app, deps) in dependencyMap {
            totalLinks += deps.count
            if !deps.isEmpty {
                dependentAppsCount += 1
            }
            
            do {
                let plan = try resolver.resolveExecutionPlan(targets: [app], dependencyMap: dependencyMap)
                if plan.stages.count > maxDepth {
                    maxDepth = plan.stages.count
                }
                if plan.stages.count >= 3 || deps.count >= 2 {
                    complexPlans.append((target: app, plan: plan))
                }
            } catch {
                if case PluginError.cycleDetected(let cycle) = error {
                    cycles.append(cycle)
                }
            }
        }
        
        return SimulationReport(
            totalApps: dependencyMap.count,
            appsWithDependencies: dependentAppsCount,
            independentApps: dependencyMap.count - dependentAppsCount,
            totalDependencyLinks: totalLinks,
            detectedCycles: cycles,
            maxPipelineDepth: maxDepth,
            sampleComplexPlans: Array(complexPlans.prefix(5))
        )
    }
}
