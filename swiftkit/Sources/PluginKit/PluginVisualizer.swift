import Foundation

/// 플러그인 의존성 및 실행 계획을 시각화하는 도구 (Mermaid / ASCII Tree)
public enum PluginVisualizer {
    
    /// 의존성 그래프와 실행 단계를 Mermaid 다이어그램 마크다운으로 변환합니다.
    public static func toMermaid(
        plan: DependencyResolver.ExecutionPlan,
        dependencyMap: [String: [String]]
    ) -> String {
        var lines = ["```mermaid", "graph TD"]
        
        // 1. Stage 별 서브그래프 생성
        for (index, stage) in plan.stages.enumerated() {
            let stageNum = index + 1
            let title = stage.count > 1 ? "Stage \(stageNum) (병렬 실행)" : "Stage \(stageNum)"
            lines.append("    subgraph S\(stageNum) [\"\(title)\"]")
            for id in stage {
                lines.append("        \(id)[\"\(id)\"]")
            }
            lines.append("    end")
        }
        
        // 2. 의존성 엣지 연결 (dep -> target)
        for (target, deps) in dependencyMap.sorted(by: { $0.key < $1.key }) {
            for dep in deps.sorted() {
                if plan.sequentialOrder.contains(dep) && plan.sequentialOrder.contains(target) {
                    lines.append("    \(dep) --> \(target)")
                }
            }
        }
        
        lines.append("```")
        return lines.joined(separator: "\n")
    }
    
    /// 터미널에서 즉시 볼 수 있는 ASCII 트리 텍스트로 변환합니다.
    public static func toAscii(
        plan: DependencyResolver.ExecutionPlan,
        targetId: String
    ) -> String {
        var lines = ["Target: \(targetId)"]
        
        for (index, stage) in plan.stages.enumerated() {
            let isLastStage = index == plan.stages.count - 1
            let stagePrefix = isLastStage ? "└── " : "├── "
            let childPrefix = isLastStage ? "    " : "│   "
            let mode = stage.count > 1 ? "Concurrent" : "Sequential"
            
            lines.append("\(stagePrefix)[Stage \(index + 1): \(mode)]")
            for (subIndex, id) in stage.enumerated() {
                let isLastChild = subIndex == stage.count - 1
                let itemPrefix = isLastChild ? "└── " : "├── "
                lines.append("\(childPrefix)\(itemPrefix)\(id)")
            }
        }
        
        return lines.joined(separator: "\n")
    }
}
