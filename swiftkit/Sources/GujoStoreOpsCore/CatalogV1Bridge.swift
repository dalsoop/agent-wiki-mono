import Foundation
import PluginKit

/// catalog-v1 (`index.json`) → `OpsPackage` 변환.
/// Software Ops API 가 준비되기 전 읽기 전용 브릿지이자 PluginKit 어댑터.
public enum CatalogV1Bridge: Sendable {
    public static let defaultBaseURL = CatalogArtifactURL.defaultIndexBaseURL

    public static func parseIndex(_ data: Data, baseURL: URL) throws -> [OpsPackage] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StoreOpsError.decode("root not object")
        }
        if let format = root["format"] as? String, format != "catalog-v1" {
            throw StoreOpsError.decode("format \(format)")
        }
        let packagesObj = root["packages"] as? [String: Any] ?? [:]
        if packagesObj.isEmpty { throw StoreOpsError.empty }

        var out: [OpsPackage] = []
        for (pkgName, raw) in packagesObj {
            guard let entry = raw as? [String: Any] else { continue }
            let name = entry["name"] as? String ?? pkgName
            let summary = entry["summary"] as? String
                ?? (entry["description"] as? String).map { String($0.prefix(120)) }
                ?? ""
            let versions = entry["versions"] as? [[String: Any]] ?? []
            let latest = versions.max {
                (intValue($0["versionCode"]) ?? 0) < (intValue($1["versionCode"]) ?? 0)
            }
            let apk = latest?["apk"] as? [String: Any]
            let apkRel = apk?["url"] as? String
            let size = intValue(apk?["size"]).map(Int64.init)
            let artifact = resolve(apkRel, against: baseURL)
            let install = baseURL
                .appendingPathComponent("install")
                .appendingPathComponent("\(pkgName).apk")
            let priceKrw = intValue(entry["price_krw"]) ?? intValue(latest?["price_krw"])
            let isSubscription = (entry["is_subscription_included"] as? Bool) ?? false
            let priceCents: Int?
            if let priceKrw {
                priceCents = StoreOpsPricing.convertKRWToUSDCents(krw: priceKrw, isSubscriptionIncluded: isSubscription)
            } else if let directCents = intValue(entry["price_usd_cents"]) {
                priceCents = directCents
            } else {
                priceCents = nil
            }
            let rawDuration = intValue(entry["access_duration_days"]) ?? intValue(latest?["access_duration_days"])
            let durationDays = rawDuration != nil ? StoreOpsPricing.normalizeAccessDurationDays(rawDuration) : nil

            out.append(OpsPackage(
                packageName: pkgName,
                displayName: name,
                summary: summary,
                platform: "android",
                versionName: latest?["versionName"] as? String,
                versionCode: intValue(latest?["versionCode"]),
                installURL: install,
                artifactURL: artifact,
                sizeBytes: size,
                status: "published",
                priceUsdCents: priceCents,
                accessDurationDays: durationDays
            ))
        }
        out.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return out
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let n = any as? NSNumber { return n.intValue }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func resolve(_ rel: String?, against base: URL) -> URL? {
        guard let rel, !rel.isEmpty else { return nil }
        if let abs = URL(string: rel), abs.scheme != nil { return abs }
        return URL(string: rel, relativeTo: base)?.absoluteURL
    }
}

/// CatalogV1 및 StoreOps를 PluginRegistry에 연동하는 AppPlugin
public struct CatalogV1Plugin: AppPlugin {
    public let id: String = "catalog-v1-bridge"
    public let name: String = "Catalog V1 Bridge"
    public let version: String = "1.0.0"
    public let actions: [String] = [
        "catalog.parseIndex",
        "catalog.packages"
    ]
    public let dependencies: [String] = []

    public init() {}

    public func execute(action: String, argv: [String] = []) async throws -> [String: Sendable] {
        switch action {
        case "parseIndex", "catalog.parseIndex":
            // argv 규약(순정화 96f2895c05): argv[0]=base64(index data), argv[1]=baseURL
            guard argv.count >= 2,
                  let data = Data(base64Encoded: argv[0]),
                  let baseURL = URL(string: argv[1]) else {
                throw PluginError.executionFailed(
                    pluginId: id,
                    reason: "argv 부족 — argv[0]=base64(index data), argv[1]=baseURL 필요")
            }
            let pkgs = try CatalogV1Bridge.parseIndex(data, baseURL: baseURL)
            return [
                "status": "ok",
                "count": pkgs.count,
                "packages": try JSONEncoder().encode(pkgs)
            ]
        default:
            throw PluginError.actionNotFound(action: action, pluginId: id)
        }
    }
}
