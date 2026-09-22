import XCTest
@testable import PluginKit
@testable import StateMirrorKit

struct MockPlugin: AppPlugin {
    let id: String
    let name: String
    let version: String
    let actions: [String]
    let dependencies: [String]
    
    init(id: String, actions: [String] = [], dependencies: [String] = []) {
        self.id = id
        self.name = id
        self.version = "1.0.0"
        self.actions = actions
        self.dependencies = dependencies
    }
    
    func execute(action: String, argv: [String] = []) async throws -> [String: Sendable] {
        return ["status": "ok", "caller": id, "action": action]
    }
}

final class PluginKitTests: XCTestCase {
    
    func testDependencyResolverSingleStage() throws {
        let resolver = DependencyResolver()
        let depMap: [String: [String]] = [
            "AppA": ["AppB", "AppC"],
            "AppB": [],
            "AppC": []
        ]
        
        let plan = try resolver.resolveExecutionPlan(targets: ["AppA"], dependencyMap: depMap)
        
        XCTAssertEqual(plan.stages.count, 2)
        XCTAssertEqual(plan.stages[0], ["AppB", "AppC"])
        XCTAssertEqual(plan.stages[1], ["AppA"])
    }
    
    func testDependencyResolverComplexThreeApps() throws {
        let resolver = DependencyResolver()
        let depMap: [String: [String]] = [
            "Main": ["Build"],
            "Build": ["Auth"],
            "Auth": []
        ]
        
        let plan = try resolver.resolveExecutionPlan(targets: ["Main"], dependencyMap: depMap)
        
        XCTAssertEqual(plan.stages.count, 3)
        XCTAssertEqual(plan.stages[0], ["Auth"])
        XCTAssertEqual(plan.stages[1], ["Build"])
        XCTAssertEqual(plan.stages[2], ["Main"])
    }
    
    func testCycleDetection() {
        let resolver = DependencyResolver()
        let depMap: [String: [String]] = [
            "AppA": ["AppB"],
            "AppB": ["AppC"],
            "AppC": ["AppA"]
        ]
        
        XCTAssertThrowsError(try resolver.resolveExecutionPlan(targets: ["AppA"], dependencyMap: depMap)) { error in
            guard case PluginError.cycleDetected = error else {
                XCTFail("Expected cycleDetected error but got \(error)")
                return
            }
        }
    }
    
    func testRegistryIntegration() async throws {
        let registry = PluginRegistry()
        registry.register(MockPlugin(id: "AuthPlugin", actions: ["auth.token"]))
        registry.register(MockPlugin(id: "BuildPlugin", actions: ["build.package"], dependencies: ["AuthPlugin"]))
        
        let authPlugin = registry.get(id: "AuthPlugin")
        XCTAssertNotNil(authPlugin)
        let res = try await authPlugin?.execute(action: "auth.token", argv: [])
        XCTAssertEqual(res?["status"] as? String, "ok")
    }
    
    func testDualChannelAndFleetHubSummary() async throws {
        let context = PluginExecutionContext(tenantId: "tenant-demo")
        let mirrorPath = StateMirror.path(app: "agent-vault")
        let dir = (mirrorPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        
        let stateJSON = """
        {"tokenStatus": "valid", "expiresIn": "3600s", "user": "admin"}
        """
        try stateJSON.write(toFile: mirrorPath, atomically: true, encoding: .utf8)
        
        let adapter = CLIProcessPluginAdapter(
            id: "agent-vault",
            name: "Agent Vault",
            version: "1.0.0",
            actions: ["auth.token"],
            executablePath: "/bin/echo"
        )
        
        let fastState = adapter.readFastState(context: context)
        XCTAssertNotNil(fastState)
        XCTAssertEqual(fastState?["tokenStatus"] as? String, "valid")
        XCTAssertEqual(fastState?["user"] as? String, "admin")
        
        let registry = PluginRegistry()
        registry.register(adapter)
        
        let hub = PluginFleetHub()
        let summary = hub.collectSummary(for: context, registry: registry)
        
        XCTAssertEqual(summary.tenantId, "tenant-demo")
        XCTAssertEqual(summary.totalPlugins, 1)
        XCTAssertEqual(summary.healthyCount, 1)
        XCTAssertEqual(summary.cards.first?.fastState["tokenStatus"], "valid")
    }
}
