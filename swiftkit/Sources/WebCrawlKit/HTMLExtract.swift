import Foundation

// 정규식 기반 HTML 파싱 헬퍼 — 경량(외부 HTML 파서 의존 없음), 정형 표/링크 구조에 적합.
// 각 크롤러가 따로 짜던 <td>/<a>/엔티티 처리를 한 곳으로. NSString NSRange 기반.

public enum HTMLExtract {

    /// HTML 엔티티 디코딩(자주 쓰는 것).
    public static func decodeEntities(_ s: String) -> String {
        var out = s
        for (e, c) in [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                       ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: e, with: c)
        }
        return out
    }

    /// 첫 번째 캡처 그룹을 반환(매치 없으면 nil).
    public static func firstMatch(_ pattern: String, in html: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
              m.numberOfRanges > 1 else { return nil }
        return (html as NSString).substring(with: m.range(at: 1))
    }

    /// 모든 매치의 첫 캡처 그룹.
    public static func allMatches(_ pattern: String, in html: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = html as NSString
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length))
            .compactMap { m -> String? in m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : nil }
    }

    /// `<td>...</td>` 셀 텍스트(태그 제거, 엔티티 디코드, 공백 정리).
    public static func cells(in rowHTML: String) -> [String] {
        let ns = rowHTML as NSString
        guard let re = try? NSRegularExpression(pattern: #"<td[^>]*>([\s\S]*?)</td>"#, options: []) else { return [] }
        return re.matches(in: rowHTML, range: NSRange(location: 0, length: ns.length)).map { m -> String in
            var inner = ns.substring(with: m.range(at: 1))
            inner = inner.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            inner = decodeEntities(inner)
            return inner.components(separatedBy: .whitespacesAndNewlines)
                .joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
    }

    /// HTML 내 `<base href="...">` 추출
    public static func extractBaseHref(from html: String) -> String? {
        firstMatch(#"<base[^>]+href=["']([^"']+)["']"#, in: html)
    }

    /// `<a href="...">text</a>` 링크 추출(href 는 base 또는 HTML 내 <base href> 상대경로 절대화).
    public static func links(in html: String, base: String? = nil) -> [(href: String, text: String)] {
        let ns = html as NSString
        guard let re = try? NSRegularExpression(pattern: #"<a[^>]*href=\s*["']([^"']+)["'][^>]*>([\s\S]*?)</a>"#, options: []) else { return [] }
        let effectiveBase = base ?? extractBaseHref(from: html)
        let baseURL = effectiveBase.flatMap { URL(string: $0) }
        return re.matches(in: html, range: NSRange(location: 0, length: ns.length)).compactMap { m -> (String, String)? in
            let raw = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty, !raw.hasPrefix("javascript:"), !raw.hasPrefix("#") else { return nil }
            var inner = ns.substring(with: m.range(at: 2))
            inner = decodeEntities(inner.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression))
                .components(separatedBy: .whitespacesAndNewlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            let href: String
            if let baseURL, let abs = URL(string: raw, relativeTo: baseURL)?.absoluteString { href = abs }
            else { href = raw }
            return (href, inner)
        }
    }

    /// loc 를 포함하는 가장 가까운 `<open>...</close>` 범위(기본 <tr></tr>).
    public static func enclosingRange(containing loc: Int, in s: NSString,
                                      open: String = "<tr", close: String = "</tr>") -> NSRange? {
        let lo = s.range(of: open, options: .backwards, range: NSRange(location: 0, length: loc))
        let hi = s.range(of: close, options: [], range: NSRange(location: loc, length: s.length - loc))
        if lo.location == NSNotFound || hi.location == NSNotFound { return nil }
        return NSRange(location: lo.location, length: hi.location + hi.length - lo.location)
    }

    /// <title>...</title> 또는 첫 <h1>.
    public static func title(in html: String) -> String? {
        if let t = firstMatch(#"<title[^>]*>([^<]+)</title>"#, in: html), !t.isEmpty { return decodeEntities(t) }
        if let h = firstMatch(#"<h1[^>]*>([^<]+)</h1>"#, in: html), !h.isEmpty { return decodeEntities(h) }
        return nil
    }
}
