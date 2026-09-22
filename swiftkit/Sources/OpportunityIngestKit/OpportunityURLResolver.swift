import Foundation
import WebCrawlKit

/// 웹 크롤링 및 피드 파싱 시 상대경로 URL을 안전하게 절대경로로 결합하고 정규화하는 엔진
public enum OpportunityURLResolver {

    /// 상대경로(또는 불완전한 절대경로)를 베이스 URL과 결합하여 표준화된 절대 URL 문자열을 반환한다.
    public static func resolve(relative: String, baseURL: URL) -> String? {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let absolute = resolveSchemeOrProtocolRelative(trimmed, baseURL: baseURL) {
            return OfferURLNormalizer.normalize(absolute)
        }

        guard let combined = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL else { return nil }
        return OfferURLNormalizer.normalize(combined.absoluteString)
    }

    private static func resolveSchemeOrProtocolRelative(_ trimmed: String, baseURL: URL) -> String? {
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        if trimmed.hasPrefix("//") {
            let scheme = baseURL.scheme ?? "https"
            return "\(scheme):\(trimmed)"
        }
        return nil
    }

    /// 공고/딜 URL의 도메인 호스트명 추출 (예: "k-startup.go.kr", "chatgpt.com")
    public static func extractHost(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        return url.host?.replacingOccurrences(of: "www.", with: "").lowercased()
    }
}
