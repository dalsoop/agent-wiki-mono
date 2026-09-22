import Foundation

/// 소비자 앱 화면에서 등록된 Interop 어댑터 목록과 상태를 수집하는 편의 모델
public struct PluginFleetHub: Sendable {
    
    public struct PluginStatusCard: Codable, Sendable, Identifiable {
        public var id: String { pluginId }
        public let pluginId: String
        public let name: String
        public let version: String
        public let isHealthy: Bool
        public let fastState: [String: String]
        public let actions: [String]
        public let dependencies: [String]
    }
    
    public struct TenantHubSummary: Codable, Sendable {
        public let tenantId: String
        public let totalPlugins: Int
        public let healthyCount: Int
        public let cards: [PluginStatusCard]
    }
    
    public init() {}
    
    /// 지정된 테넌트의 등록된 어댑터 상태를 일괄 수집 (프로세스 스폰 0회)
    public func collectSummary(
        for context: PluginExecutionContext,
        registry: PluginRegistry
    ) -> TenantHubSummary {
        let plugins = registry.allPlugins()
        var cards: [PluginStatusCard] = []
        var healthy = 0
        
        for p in plugins {
            var stringState: [String: String] = [:]
            var isOk = true
            
            if let fast = p.readFastState(context: context) {
                for (k, v) in fast {
                    stringState[k] = "\(v)"
                }
            } else if let adapter = p as? CLIProcessPluginAdapter {
                isOk = FileManager.default.isExecutableFile(atPath: adapter.executablePath)
            }
            
            if isOk { healthy += 1 }
            
            cards.append(
                PluginStatusCard(
                    pluginId: p.id,
                    name: p.name,
                    version: p.version,
                    isHealthy: isOk,
                    fastState: stringState,
                    actions: p.actions,
                    dependencies: p.dependencies
                )
            )
        }
        
        return TenantHubSummary(
            tenantId: context.tenantId,
            totalPlugins: plugins.count,
            healthyCount: healthy,
            cards: cards
        )
    }
}
