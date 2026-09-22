import Foundation
import EndpointRouterKit

/// catalog APK URL 정규화.
///
/// edge catalog 는 HTTP 정본(EndpointRouterKit catalog-kr).
/// Ops API 가 HTTPS 를 내려주면 클라이언트 TLS 검증이 깨진다(cert SAN 불일치).
/// 런북: gujo-wiki `a6f410e0` (HTTPS client verify 불안정 → HTTP).
public enum CatalogArtifactURL {
    /// EndpointRouterKit 원장(catalog-kr/catalog-parquet 키)에서 호스트를 읽는다.
    /// 키는 번들 폴백 표에 보장되어 있다 — 코드 리터럴 폴백은 두지 않는다.
    public static let hostKR = hostFromKey("catalog-kr")
    /// 기존 호출부(온보딩 플레이북) 호환. 값은 catalog-kr 과 같다.
    public static let hostJP = hostKR
    public static let hostParquet = hostFromKey("catalog-parquet")

    private static func hostFromKey(_ key: String) -> String {
        if let url = EndpointRouter.url(key), let host = url.host {
            return host
        }
        // 원장·번들 표에 키가 보장된다 — 도달하지 않는 최후 경로.
        return EndpointRouter.defaults[key] ?? key
    }

    /// 내부 catalog 호스트 — HTTPS 이면 HTTP 로 내린다.
    public static let internalHosts: Set<String> = [hostKR, hostParquet]

    public static let defaultIndexBaseURL =
        EndpointRouter.url("catalog-parquet") ?? URL(fileURLWithPath: "/invalid-catalog-parquet")

    public static func downloadURL(from url: URL) -> URL {
        guard let host = url.host?.lowercased(), internalHosts.contains(host) else {
            return url
        }
        guard (url.scheme ?? "").lowercased() == "https" else {
            return url
        }
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        parts?.scheme = "http"
        return parts?.url ?? url
    }
}
