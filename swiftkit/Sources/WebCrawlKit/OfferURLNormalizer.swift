import Foundation

/// 프로모션/할인/구독 딜 URL 정규화기
/// - utm_*, fbclid, gclid 등 광고 추적 파라미터는 제거하되
/// - coupon, promo, discount, plan, voucher 등 딜 식별 핵심 파라미터는 온전히 보존한다.
public enum OfferURLNormalizer {

    private static let trackingKeys: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "fbclid", "gclid", "igshid", "mc_eid", "_ga", "_gl", "msclkid", "ttclid",
        "twclid", "spm", "source", "ref_src", "feature"
    ]

    private static let preservedOfferKeys: Set<String> = [
        "coupon", "code", "promo", "promocode", "discount", "voucher",
        "plan", "tier", "billing", "period", "deal", "offer", "ref", "aff"
    ]

    /// 광고 추적 파라미터만 선별 제거하고 딜 식별 파라미터를 보존한 정규화 URL 문자열을 반환한다.
    public static func normalize(_ urlString: String) -> String {
        guard let comps = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return urlString
        }

        var clean = comps
        clean.fragment = nil
        clean.host = clean.host?.lowercased()
        clean.queryItems = filterQueryItems(clean.queryItems)

        var result = clean.string ?? urlString
        let isRootPath = clean.path == "/" || clean.path.isEmpty
        let shouldStripSlash = result.hasSuffix("/") && isRootPath && clean.query == nil
        if shouldStripSlash {
            result.removeLast()
        }
        return result
    }

    private static func filterQueryItems(_ items: [URLQueryItem]?) -> [URLQueryItem]? {
        guard let items, !items.isEmpty else { return nil }
        let filtered = items.filter { item in
            let key = item.name.lowercased()
            return !trackingKeys.contains(key) && !key.hasPrefix("utm_")
        }
        guard !filtered.isEmpty else { return nil }
        return filtered.sorted { $0.name < $1.name }
    }

    /// URL에 프로모션/쿠폰 코드가 포함되어 있는지 검사한다.
    public static func extractPromoCode(from urlString: String) -> String? {
        guard let comps = URLComponents(string: urlString),
              let items = comps.queryItems else { return nil }

        for item in items {
            let key = item.name.lowercased()
            if ["coupon", "code", "promo", "promocode", "voucher"].contains(key),
               let val = item.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !val.isEmpty {
                return val
            }
        }
        return nil
    }
}
