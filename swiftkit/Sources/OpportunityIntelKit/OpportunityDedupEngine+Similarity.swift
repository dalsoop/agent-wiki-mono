import Foundation

extension OpportunityDedupEngine {

    // MARK: - 기관/제공자 정규화 및 비교

    public static func isSameProvider(_ a: OpportunityIntelItem, _ b: OpportunityIntelItem) -> Bool {
        let p1 = normalizeProvider(a.provider)
        let p2 = normalizeProvider(b.provider)
        if p1 == p2 && !p1.isEmpty { return true }
        return checkCanonicalOrAlias(a: a, b: b, p1: p1, p2: p2)
    }

    private static func checkCanonicalOrAlias(a: OpportunityIntelItem, b: OpportunityIntelItem, p1: String, p2: String) -> Bool {
        let c1 = a.canonical.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let c2 = b.canonical.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !c1.isEmpty && c1 == c2 { return true }
        return checkProviderAlias(p1, p2)
    }

    private static func normalizeProvider(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "(주)", with: "")
            .replacingOccurrences(of: "주식회사", with: "")
            .replacingOccurrences(of: "inc.", with: "")
            .replacingOccurrences(of: "llc", with: "")
            .trimmingCharacters(in: .punctuationCharacters)
    }

    private static func checkProviderAlias(_ a: String, _ b: String) -> Bool {
        let aliases: [Set<String>] = [
            ["중소벤처기업부", "중기부", "mss"],
            ["과학기술정보통신부", "과기정통부", "과기부", "msit"],
            ["산업통상자원부", "산업부", "motie"],
            ["정보통신산업진흥원", "nipa"],
            ["창업진흥원", "kised", "k-startup"],
            ["한국지능정보사회진흥원", "nia"],
            ["정보통신기획평가원", "iitp"],
            ["한국산업기술진흥원", "kiat"],
            ["한국연구재단", "nrf"],
            ["openai", "openaiinc"],
            ["anthropic", "anthropicpbc"]
        ]
        for set in aliases {
            if set.contains(a) && set.contains(b) {
                return true
            }
        }
        let isSubstring = a.contains(b) || b.contains(a)
        let hasMinLength = min(a.count, b.count) >= 3
        return isSubstring && hasMinLength
    }

    // MARK: - 제목 정규화 및 유사도

    public static func isSimilarTitle(_ t1: String, _ t2: String) -> Bool {
        let norm1 = normalizeTitle(t1)
        let norm2 = normalizeTitle(t2)
        if norm1 == norm2 && !norm1.isEmpty { return true }
        if hasSubstringInclusion(norm1, norm2) { return true }
        return checkTokenOrDistanceSimilarity(norm1: norm1, norm2: norm2)
    }

    private static func hasSubstringInclusion(_ s1: String, _ s2: String) -> Bool {
        guard min(s1.count, s2.count) >= 8 else { return false }
        return s1.contains(s2) || s2.contains(s1)
    }

    private static func checkTokenOrDistanceSimilarity(norm1: String, norm2: String) -> Bool {
        if checkDiceSimilarity(norm1: norm1, norm2: norm2) { return true }
        return checkLevenshteinSimilarity(norm1: norm1, norm2: norm2)
    }

    private static func checkDiceSimilarity(norm1: String, norm2: String) -> Bool {
        let tokens1 = Set(norm1.split(separator: " ").map(String.init))
        let tokens2 = Set(norm2.split(separator: " ").map(String.init))
        let total = tokens1.count + tokens2.count
        guard total > 0 else { return false }
        let intersection = tokens1.intersection(tokens2)
        let dice = Double(2 * intersection.count) / Double(total)
        return dice >= 0.6
    }

    private static func checkLevenshteinSimilarity(norm1: String, norm2: String) -> Bool {
        let maxLen = max(norm1.count, norm2.count)
        guard maxLen > 0 else { return false }
        let dist = levenshteinDistance(norm1, norm2)
        let sim = 1.0 - (Double(dist) / Double(maxLen))
        return sim >= 0.75
    }

    public static func normalizeTitle(_ title: String) -> String {
        var s = title.lowercased()
        s = s.replacingOccurrences(of: #"[\[\(\<【][^\]\)\>】]*[\]\)\>】]"#, with: " ", options: .regularExpression)

        let noiseKeywords = [
            "재공고", "수정공고", "긴급공고", "사업공고", "모집공고", "선정공고",
            "공고", "모집안내", "모집", "안내", "지원사업", "사업", "안내문"
        ]
        for kw in noiseKeywords {
            s = s.replacingOccurrences(of: kw, with: " ")
        }

        let mapped = s.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var dist = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(dist[i - 1][j] + 1, dist[i][j - 1] + 1, dist[i - 1][j - 1] + 1)
                }
            }
        }
        return dist[a.count][b.count]
    }

    // MARK: - URL 정규화 및 비교

    public static func normalizeURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            return trimmed.lowercased()
        }
        let host = (url.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        var path = url.path.lowercased()
        if path.hasSuffix("/") && path.count > 1 {
            path.removeLast()
        }
        let cleanQuery = buildCleanQuery(for: url)
        return "\(host)\(path)\(cleanQuery)"
    }

    private static func buildCleanQuery(for url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return "" }
        let ignoredKeys: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "ref", "fbclid", "gclid", "t", "timestamp", "spm", "source"
        ]
        let validItems = queryItems
            .filter { !ignoredKeys.contains($0.name.lowercased()) }
            .sorted(by: { $0.name < $1.name })
        guard !validItems.isEmpty else { return "" }
        return "?" + validItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
    }

    public static func isSimilarURL(_ u1: String, _ u2: String) -> Bool {
        guard let url1 = URL(string: u1), let url2 = URL(string: u2) else { return false }
        let h1 = (url1.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        let h2 = (url2.host ?? "").lowercased().replacingOccurrences(of: "www.", with: "")
        guard h1 == h2 && !h1.isEmpty else { return false }

        let p1 = url1.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        let p2 = url2.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return !p1.isEmpty && p1 == p2
    }

    // MARK: - 마감일 및 금액 병합 헬퍼

    private static let dateFormats: [String] = ["yyyy-MM-dd", "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy.MM.dd"]

    private static func parseDate(_ dateStr: String) -> Date? {
        for fmt in dateFormats {
            let df = DateFormatter()
            df.dateFormat = fmt
            df.timeZone = TimeZone(identifier: "Asia/Seoul") ?? TimeZone.current
            if let d = df.date(from: dateStr) {
                return d
            }
        }
        return nil
    }

    public static func selectLatestDeadline(between d1: String?, and d2: String?) -> String? {
        guard let d1, !d1.isEmpty else { return d2 }
        guard let d2, !d2.isEmpty else { return d1 }

        if let date1 = parseDate(d1), let date2 = parseDate(d2) {
            return date1 >= date2 ? d1 : d2
        }
        return d1 >= d2 ? d1 : d2
    }

    public static func extractMaxGrantValue(from item: OpportunityIntelItem) -> Double {
        var maxVal: Double = 0
        if let actual = item.actualValue {
            maxVal = max(maxVal, parseNumericAmount(actual))
        }
        if let standard = item.standardValue {
            maxVal = max(maxVal, parseNumericAmount(standard))
        }
        return maxVal
    }

    public static func parseNumericAmount(_ text: String) -> Double {
        let clean = text.replacingOccurrences(of: ",", with: "")
        if let eok = parseEokAmount(clean) { return eok }
        return parseSubEokAmount(clean)
    }

    private static func parseEokAmount(_ clean: String) -> Double? {
        guard let match = clean.range(of: #"([0-9]+(?:\.[0-9]+)?)\s*억(?:\s*([0-9]+)\s*천만)?"#, options: .regularExpression) else {
            return nil
        }
        let sub = String(clean[match])
        let parts = sub.components(separatedBy: "억")
        let okNum = Double(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0
        var extra: Double = 0
        if parts.count > 1 {
            let rest = parts[1].replacingOccurrences(of: "천만", with: "").trimmingCharacters(in: .whitespaces)
            extra = (Double(rest) ?? 0) * 10_000_000
        }
        return (okNum * 100_000_000) + extra
    }

    private struct AmountPattern {
        let pattern: String
        let remove: String
        let multiplier: Double
    }

    private static let subEokPatterns: [AmountPattern] = [
        AmountPattern(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*천만"#, remove: "천만", multiplier: 10_000_000),
        AmountPattern(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*백만"#, remove: "백만", multiplier: 1_000_000),
        AmountPattern(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*만"#, remove: "만", multiplier: 10_000),
        AmountPattern(pattern: #"[0-9]{5,}\s*원?"#, remove: "원", multiplier: 1),
        AmountPattern(pattern: #"\$\s*([0-9]+(?:\.[0-9]+)?)"#, remove: "$", multiplier: 1_400)
    ]

    private static func parseSubEokAmount(_ clean: String) -> Double {
        for p in subEokPatterns {
            if let match = clean.range(of: p.pattern, options: .regularExpression) {
                let numStr = String(clean[match]).replacingOccurrences(of: p.remove, with: "").trimmingCharacters(in: .whitespaces)
                if let n = Double(numStr) { return n * p.multiplier }
            }
        }
        return 0
    }
}
