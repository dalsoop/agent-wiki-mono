import Foundation
import StateRootKit

/// dal-* 장기 앱 공용 테넌트 규약.
/// 경로에는 slug만 쓰고, 레코드에는 canonical(`tenant:` 유지 가능)을 쓴다.
public struct DalTenant: Sendable, Equatable, Hashable {
    /// 저장·표시용. `tenant:personal` 또는 이미 slug면 그대로.
    public let canonical: String
    /// 파일 경로용. `personal`
    public let slug: String

    public init(canonical: String, slug: String) {
        self.canonical = canonical
        self.slug = slug
    }

    public static func parse(_ raw: String) throws -> DalTenant {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DalKitError.emptyTenant }
        let slug: String
        if trimmed.hasPrefix("tenant:") {
            slug = String(trimmed.dropFirst("tenant:".count))
        } else {
            slug = trimmed
        }
        let cleaned = slug
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw DalKitError.emptyTenant }
        guard !cleaned.contains("..") else { throw DalKitError.invalidTenant(trimmed) }
        guard cleaned.unicodeScalars.allSatisfy({
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-")).contains($0)
        }) else {
            throw DalKitError.invalidTenant(trimmed)
        }
        let canonical = trimmed.hasPrefix("tenant:") ? "tenant:\(cleaned)" : cleaned
        return DalTenant(canonical: canonical, slug: cleaned)
    }

    public static func resolve(
        explicit: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) throws -> DalTenant {
        if let explicit, !explicit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return try parse(explicit)
        }
        if let env = environment["TENANT_ID"], !env.isEmpty {
            return try parse(env)
        }
        if let fromFile = tenantIDFromContext(environment: environment, homeDirectory: homeDirectory) {
            return try parse(fromFile)
        }
        throw DalKitError.tenantRequired
    }

    /// `~/.dal/<app>/tenants/<slug>/` — StateRoot 아래에 다른 테넌트를 중첩하지 않는다.
    public static func dataDirectory(
        app: String,
        tenant: DalTenant,
        homeDirectory: String? = nil
    ) -> URL {
        let base = homeDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? URL(fileURLWithPath: StateRootKit.resolveHost(), isDirectory: true)
        return base
            .appendingPathComponent(".dal", isDirectory: true)
            .appendingPathComponent(app, isDirectory: true)
            .appendingPathComponent("tenants", isDirectory: true)
            .appendingPathComponent(tenant.slug, isDirectory: true)
    }

    private static func tenantIDFromContext(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: String? = nil
    ) -> String? {
        let path = StateRootKit.hostPath(
            ".agent-tenant-isolation-manager/current-context.json",
            environment: environment,
            homeDirectory: homeDirectory
        )
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = DalJSON.object(from: data),
              let id = obj["tenantID"] as? String,
              !id.isEmpty
        else { return nil }
        return id
    }
}
