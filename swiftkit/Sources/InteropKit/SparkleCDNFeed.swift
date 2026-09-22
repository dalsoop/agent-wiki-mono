import Foundation

/// 공개 Sparkle CDN 객체 경로 규약 — ship 주입(`SUFeedURL`)과 CDN 발행이 **같은 함수**를 쓴다.
///
/// 경로: `apps/<번들ID 점→슬래시>/appcast.xml`
/// 예: `net.ranode.appbuildmanager` → `https://cdn.ranode.net/apps/net/ranode/appbuildmanager/appcast.xml`
///
/// DistributionCore·SparklePublishKit 에 각각 두지 않는다(서로 의존하면 사이클).
public enum SparkleCDNFeed {
    /// Cloudflare Universal SSL 이 덮는 1레벨 서브도메인. 2레벨(`*.cdn.ranode.net`)은 인증서가 없다.
    public static let defaultHost = "cdn.ranode.net"
    public static var defaultBaseURL: String { "https://\(defaultHost)" }

    public static func trimSlash(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// 번들 ID → S3/공개 경로 slug (점 → 슬래시).
    public static func objectSlug(bundleID: String) -> String {
        bundleID.replacingOccurrences(of: ".", with: "/")
    }

    /// slug → 번들 ID (슬래시 → 점).
    public static func bundleID(fromObjectSlug slug: String) -> String {
        slug.replacingOccurrences(of: "/", with: ".")
    }

    /// 손님 피드와 개발자 피드를 갈라 둔다. 개발자 객체는 `dev/` 접두어.
    public enum Lane: String, Sendable, Equatable {
        case production
        case developer

        /// 기본은 개발 레인. `SHIP_MODE=publish` 또는 `SPARKLE_LANE=production` 만 손님 `apps/`.
        public static func fromEnvironment(
            _ env: [String: String] = ProcessInfo.processInfo.environment
        ) -> Lane {
            let lane = (env["SPARKLE_LANE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if lane == "production" { return .production }
            if lane == "developer" { return .developer }
            let mode = (env["SHIP_MODE"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if mode == "publish" { return .production }
            if mode == "develop" || mode == "dev" || mode == "developer" { return .developer }
            return .developer
        }
    }

    /// `apps/<slug>/appcast.xml`
    public static func appcastObjectKey(bundleID: String) -> String {
        "apps/\(objectSlug(bundleID: bundleID))/appcast.xml"
    }

    /// 레인을 받는 appcast 객체 키 — `.developer` 는 `dev/` 접두(`dev/apps/…`).
    public static func appcastObjectKey(bundleID: String, lane: Lane) -> String {
        lane == .developer
            ? "dev/\(appcastObjectKey(bundleID: bundleID))"
            : appcastObjectKey(bundleID: bundleID)
    }

    /// `apps/<slug>/archives/<zipName>` — 레인이 개발자면 `dev/` 접두.
    public static func archiveObjectKey(bundleID: String, zipName: String, lane: Lane = .production) -> String {
        let prefix = lane == .developer ? "dev/" : ""
        return "\(prefix)apps/\(objectSlug(bundleID: bundleID))/archives/\(zipName)"
    }

    public static func feedURL(bundleID: String, baseURL: String = defaultBaseURL) -> String {
        "\(normalizePublicBaseURL(baseURL))/\(appcastObjectKey(bundleID: bundleID))"
    }

    /// 레인을 받는 피드 URL. `.developer` 는 `dev/` 접두 경로 — 발행 백엔드가 개발
    /// appcast 를 내려놓는 곳이다. 기본(인자 없음)은 손님 `apps/` 정본이고, **레인을
    /// 명시할 때만** dev 경로가 나온다. 발행은 `apps/` 에만 올리므로, 명시 없이 dev 를
    /// 골라 담으면 설치본이 영구 404 를 돈다(실측 2026-08-22: 설치본 7개 `/dev/apps/` 404).
    public static func feedURL(bundleID: String, baseURL: String = defaultBaseURL, lane: Lane) -> String {
        "\(normalizePublicBaseURL(baseURL))/\(appcastObjectKey(bundleID: bundleID, lane: lane))"
    }

    /// `SPARKLE_UPDATES_BASE_URL=https://cdn.ranode.net/dev` 가
    /// `…/dev/apps/…/appcast.xml` 을 만든다. 발행 객체 경로는 `apps/` 뿐이다.
    public static func normalizePublicBaseURL(_ raw: String) -> String {
        var s = trimSlash(raw)
        guard let host = URL(string: s)?.host, host == defaultHost else { return s }
        if s.hasSuffix("/dev") {
            s.removeLast(4)
            s = trimSlash(s)
        }
        return s
    }

    /// 설치본이 GET 하는 경로가 발행 정본(`apps/<slug>/appcast.xml`)과 다른가.
    /// 실측 2026-08-22: 설치본 7개가 `/dev/apps/` 를 가리키고 전부 404, 발행은 `/apps/`.
    public static func isDevObjectPath(_ url: String) -> Bool {
        let path = URL(string: url)?.path ?? url
        return path.contains("/dev/apps/")
    }

    public static func matchesPublishPath(_ url: String, bundleID: String, baseURL: String = defaultBaseURL) -> Bool {
        trimSlash(url) == feedURL(bundleID: bundleID, baseURL: baseURL)
    }
}
