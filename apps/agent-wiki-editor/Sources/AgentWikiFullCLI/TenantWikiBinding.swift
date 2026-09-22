import Foundation
import StateRootKit

/// 활성 테넌트 방의 agent-wiki world 이름 해석 (PluginKit / StateRoot 기반 격리).
public enum TenantWikiBinding: Sendable {
    public static func activeWorldName() -> String? {
        if let env = ProcessInfo.processInfo.environment["ACTIVE_TENANT_WIKI_WORLD"], !env.isEmpty {
            return env
        }
        let contextURL = StateRootKit.url(".config/agent-tenant-isolation/context.json")
        guard let data = try? Data(contentsOf: contextURL) else { return nil }
        let json: [String: Any]?
        do {
            json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            json = nil
        }
        guard let json,
              let activeSlug = json["activeSlug"] as? String ?? json["tenantID"] as? String else {
            return nil
        }
        let ledgerURL = StateRootKit.url(".config/agent-tenant-isolation/tenants.json")
        guard let ledgerData = try? Data(contentsOf: ledgerURL) else { return "person-\(activeSlug)" }
        let ledgerJson: [String: Any]?
        do {
            ledgerJson = try JSONSerialization.jsonObject(with: ledgerData) as? [String: Any]
        } catch {
            ledgerJson = nil
        }
        guard let ledgerJson,
              let tenants = ledgerJson["tenants"] as? [[String: Any]],
              let matching = tenants.first(where: { ($0["id"] as? String) == activeSlug || ($0["slug"] as? String) == activeSlug }),
              let room = matching["room"] as? [String: Any],
              let wikiWorld = room["wikiWorld"] as? String else {
            return "person-\(activeSlug)"
        }
        return wikiWorld
    }
}
