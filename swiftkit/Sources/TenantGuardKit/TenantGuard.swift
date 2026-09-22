import Foundation
import os
import StateRootKit

/// CLI 진입 시 테넌트 컨텍스트가 설정돼 있는지 검사하는 가드.
///
/// `GujoManaged.exitIfNotEntitledSync()` 바로 뒤에 호출하는 구조다 — 결제 게이트를
/// 통과한 뒤, 테넌트 격리가 필요한 앱만 이 가드를 추가로 건다.
///
/// **opt-in**: `TenantGuard.isRequired` 가 `false`(기본)이면 `requireContext()` 는
/// 아무것도 하지 않고 바로 반환한다. 테넌트 격리가 필요한 앱만 진입점에서
/// `TenantGuard.isRequired = true` 로 켜고 `TenantGuard.requireContext()` 를 부른다.
public enum TenantGuard {
    private static let isRequiredLock = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// `true` 로 설정한 앱만 `requireContext()` 가 실제 검사를 수행한다.
    /// 기본 `false` — 기존 앱은 영향 없다.
    public static var isRequired: Bool {
        get { isRequiredLock.withLock { $0 } }
        set { isRequiredLock.withLock { $0 = newValue } }
    }

    /// 해석 순서 (SSOT):
    /// 1. `ROOM_TENANT` 환경변수 (방 수준 테넌트)
    /// 2. `AGENT_TENANT` 환경변수 (에이전트 수준 테넌트)
    /// 3. `TENANT_ID` 환경변수 (환경 테넌트)
    /// 4. `~/.agent-tenant-isolation-manager/current-context.json` 의 `tenantID` 필드
    ///
    /// 게이트를 열지 않는다 — 관측 레코드에 찍을 값만 돌려준다.
    public static func resolvedTenantID(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String? {
        if let roomTenant = environment["ROOM_TENANT"], !roomTenant.isEmpty {
            return roomTenant
        }
        if let agentTenant = environment["AGENT_TENANT"], !agentTenant.isEmpty {
            return agentTenant
        }
        if let envTenant = environment["TENANT_ID"], !envTenant.isEmpty {
            return envTenant
        }
        let contextPath = StateRootKit.hostPath(
            ".agent-tenant-isolation-manager/current-context.json",
            environment: environment,
            homeDirectory: homeDirectory
        )
        guard let data = FileManager.default.contents(atPath: contextPath), !data.isEmpty else {
            return nil
        }
        struct MinimalContext: Decodable {
            var tenantID: String
        }
        guard let ctx = try? JSONDecoder().decode(MinimalContext.self, from: data),
              !ctx.tenantID.isEmpty else {
            return nil
        }
        return ctx.tenantID
    }

    /// 테넌트 컨텍스트가 있는지 확인한다. 없으면 stderr 에 안내를 쓰고 `exit(78)` 한다.
    ///
    /// 해석 순서는 `resolvedTenantID` 와 같다.
    ///
    /// 둘 다 없으면 exit code 78(`EX_CONFIG` — 설정 에러).
    public static func requireContext(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) {
        guard isRequired else { return }

        let agentID = environment["AGENT_ID"]

        if let resolved = resolvedTenantID(environment: environment, homeDirectory: homeDirectory) {
            let reason: String
            if environment["ROOM_TENANT"]?.isEmpty == false {
                reason = "ROOM_TENANT env"
            } else if environment["AGENT_TENANT"]?.isEmpty == false {
                reason = "AGENT_TENANT env"
            } else if environment["TENANT_ID"]?.isEmpty == false {
                reason = "TENANT_ID env"
            } else {
                reason = "current-context.json"
            }
            let slug = resolved.hasPrefix("tenant:") ? String(resolved.dropFirst(7)) : resolved
            TenantAuditLog.record(
                tenantSlug: slug, tenantID: resolved, agentID: agentID,
                action: .allowed, reason: reason, homeDirectory: homeDirectory
            )
            return
        }

        TenantAuditLog.record(
            tenantSlug: nil, tenantID: nil, agentID: agentID,
            action: .denied, reason: "no tenant context", homeDirectory: homeDirectory
        )

        FileHandle.standardError.write(
            Data("테넌트 컨텍스트 없음 — agent-tenant-isolation-manager context set <tenant> 실행 필요\n".utf8)
        )
        exit(78)
    }
}
