import Foundation
import OrganKit

/// 프로세스 내에서 등록된 Interop Adapter(`AppPlugin`)들을 관리하고 실행하는 Adapter Table
public final class PluginRegistry: @unchecked Sendable {
    public static let shared = PluginRegistry()
    
    private let lock = NSLock()
    private var plugins: [String: any AppPlugin] = [:]
    private var rejected: [String: [String]] = [:]

    public init() {}

    /// 등록은 모든 플러그인이 지나는 **단일 문**이다 — in-process 든
    /// `capabilities --json` 으로 발견된 CLI 어댑터든 여기를 지난다. 그래서 액션 이름
    /// 검사도 여기서 한다.
    ///
    /// 왜 필요한가: `no-dotted-action-in-plugin` 은 소스 텍스트를 본다. 그런데 CLI 가
    /// 런타임에 보고한 이름은 소스에 리터럴로 없다 — 그 린트가 **원리적으로 볼 수 없는
    /// 자리**다. OrganKit 의 `PluginAction` 문에 통과시켜 실행 불가능한 이름을 기록한다.
    ///
    /// 지금은 **기록만** 한다. 디스패치를 막으면 이미 도는 앱의 동작이 바뀌므로,
    /// 차단 승격은 따로 판정한다.
    public func register(_ plugin: any AppPlugin) {
        let refused = PluginAction.partition(plugin.actions).rejected
            .map { "\($0.raw) — \($0.reason)" }
        lock.lock()
        defer { lock.unlock() }
        plugins[plugin.id] = plugin
        if refused.isEmpty {
            rejected.removeValue(forKey: plugin.id)
        } else {
            rejected[plugin.id] = refused
        }
    }

    /// 등록된 플러그인이 내건 액션 이름 중 **실행 가능한 토큰이 아닌 것**과 그 사유.
    /// 비어 있지 않으면 그 플러그인(대개 CLI)의 `capabilities` 가 가상 이름을 보고한
    /// 것이다. Kit 이 임의로 로그를 찍지 않고, 호출부·GUI 가 표면에 올릴 수 있게 둔다.
    public func rejectedActions(id: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return rejected[id] ?? []
    }

    /// 함대 전체 진단용 — 어떤 플러그인이 가상 이름을 내걸고 있는지 한 번에 본다.
    public func allRejectedActions() -> [String: [String]] {
        lock.lock()
        defer { lock.unlock() }
        return rejected
    }
    
    public func unregister(id: String) {
        lock.lock()
        defer { lock.unlock() }
        plugins.removeValue(forKey: id)
        rejected.removeValue(forKey: id)
    }
    
    public func get(id: String) -> (any AppPlugin)? {
        lock.lock()
        defer { lock.unlock() }
        return plugins[id]
    }
    
    public func allPlugins() -> [any AppPlugin] {
        lock.lock()
        defer { lock.unlock() }
        return Array(plugins.values)
    }

    public func plan(for targetId: String) throws -> DependencyResolver.ExecutionPlan {
        lock.lock()
        guard plugins[targetId] != nil else {
            lock.unlock()
            throw PluginError.pluginNotFound(targetId)
        }
        var depMap: [String: [String]] = [:]
        for (id, p) in plugins {
            depMap[id] = p.dependencies
        }
        lock.unlock()
        return try DependencyResolver().resolveExecutionPlan(targets: [targetId], dependencyMap: depMap)
    }
    
    private func findPlugin(forAction action: String) -> (any AppPlugin)? {
        lock.lock()
        defer { lock.unlock() }
        return plugins.values.first { $0.actions.contains(action) }
    }
    
    public func execute(
        action: String,
        argv: [String] = [],
        context: PluginExecutionContext = .current
    ) async throws -> [String: Sendable] {
        guard let plugin = findPlugin(forAction: action) else {
            throw PluginError.actionNotFound(action: action, pluginId: "unknown")
        }
        return try await plugin.execute(action: action, argv: argv)
    }
    
    public func execute(
        pluginId: String,
        action: String,
        argv: [String] = [],
        context: PluginExecutionContext = .current
    ) async throws -> [String: Sendable] {
        guard let plugin = get(id: pluginId) else {
            throw PluginError.pluginNotFound(pluginId)
        }
        return try await plugin.execute(action: action, argv: argv)
    }

    public func execute(
        pluginId: String,
        action: String,
        payload: [String: Any],
        context: PluginExecutionContext = .current
    ) async throws -> [String: Any] {
        var argv: [String] = []
        for (key, val) in payload {
            argv.append(contentsOf: ["--\(key)", "\(val)"])
        }
        argv.append("--json")
        let res = try await execute(pluginId: pluginId, action: action, argv: argv, context: context)
        return res as [String: Any]
    }
    
    public static func execute(
        action: String,
        argv: [String] = [],
        context: PluginExecutionContext = .current
    ) async throws -> [String: Sendable] {
        try await shared.execute(action: action, argv: argv, context: context)
    }
    
    public static func execute(
        pluginId: String,
        action: String,
        argv: [String] = [],
        context: PluginExecutionContext = .current
    ) async throws -> [String: Sendable] {
        try await shared.execute(pluginId: pluginId, action: action, argv: argv, context: context)
    }
}
