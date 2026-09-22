import Foundation
import KnowledgeBaseWikiCore
import StateRootKit

/// Studio 창의 기본 쓰기 world. gujo 로 폴백하지 않는다.
public enum StudioWriteWorld: Sendable {
    public static func inferred(
        tenantID: String? = ProcessInfo.processInfo.environment["TENANT_ID"],
        contextURL: URL = StateRootKit.url(for: ".agent-tenant-isolation-manager/current-context.json")
    ) -> String {
        WikiWorldPresentation.inferredPersonWorld(tenantID: tenantID, contextURL: contextURL)
    }

    public static func slug(fromTenantID raw: String?) -> String? {
        WikiWorldPresentation.slug(fromTenantID: raw)
    }
}
