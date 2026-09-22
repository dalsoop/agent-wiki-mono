import Foundation
import StateRootKit

/// 테넌트 신원 정보 및 격리 환경변수 주입기 (L0 얇은 래퍼)
public struct PluginExecutionContext: Sendable {
    /// 테넌트 식별자 ("host" 또는 Isolation 키 "tenant:wife")
    public let tenantId: String
    public let roomId: String?
    
    /// 현재 활성 테넌트 컨텍스트 (StateRootKit 정본 연동)
    public static var current: PluginExecutionContext {
        let tenant = StateRootKit.currentTenantID() ?? "host"
        return PluginExecutionContext(tenantId: tenant)
    }
    
    public init(
        tenantId: String = "host",
        roomId: String? = nil
    ) {
        self.tenantId = tenantId
        self.roomId = roomId
    }
    
    /// 서브프로세스 실행 시 주입할 격리 환경변수 세트
    /// (SWIFT_APP_STATE_ROOT를 어댑터가 임의로 생성하거나 덮어쓰지 않고 상속 환경 그대로 전달)
    public func makeEnvironment(inherited: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = inherited
        env["TENANT_ID"] = tenantId
        if let r = roomId { env["ROOM_ID"] = r }
        return env
    }
}
