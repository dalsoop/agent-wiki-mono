import Foundation
import StateRootKit

/// 출처 원장(`source-sites.json`)이 켜 둔 사이트만 수집한다. 원장이 없으면 기업마당은 켠 것으로 본다.
public enum SourceSiteGate: Sendable {
    public static var defaultSitesFile: URL {
        StateRootKit.url(".swift-app-state").appendingPathComponent("source-sites.json")
    }

    public static func isEnabled(id: String, file: URL = defaultSitesFile) -> Bool {
        guard FileManager.default.fileExists(atPath: file.path),
              let data = FileLoad.data(contentsOf: file),
              let root = FileLoad.jsonObject(from: data) as? [String: Any],
              let rows = root["sites"] as? [[String: Any]] else {
            return id == "bizinfo"
        }
        guard let row = rows.first(where: { ($0["id"] as? String) == id }) else {
            return id == "bizinfo"
        }
        return (row["enabled"] as? Bool) ?? false
    }
}
