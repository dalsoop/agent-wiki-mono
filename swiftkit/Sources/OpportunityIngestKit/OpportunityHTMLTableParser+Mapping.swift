import Foundation
import OpportunityIntelKit
import WebCrawlKit

extension OpportunityHTMLTableParser {

    private struct HeaderRule {
        let keywords: [String]
        let key: String
    }

    private static let headerRules: [HeaderRule] = [
        HeaderRule(keywords: ["제목", "공고명", "사업명"], key: "title"),
        HeaderRule(keywords: ["마감", "접수기한", "신청기한"], key: "deadline"),
        HeaderRule(keywords: ["기관", "부서", "담당", "주관"], key: "provider"),
        HeaderRule(keywords: ["구분", "분류", "분야"], key: "category"),
        HeaderRule(keywords: ["등록일", "작성일", "게시일"], key: "date"),
        HeaderRule(keywords: ["상태", "진행"], key: "status")
    ]

    static func buildHeaderMap(_ ths: [String]) -> [String: Int] {
        var map: [String: Int] = [:]
        for (i, th) in ths.enumerated() {
            let lower = th.replacingOccurrences(of: " ", with: "").lowercased()
            for rule in headerRules {
                if rule.keywords.contains(where: { lower.contains($0) }) {
                    map[rule.key] = i
                    break
                }
            }
        }
        return map
    }

    static func extractField(named key: String, cells: [String], headerMap: [String: Int]) -> String? {
        guard let idx = headerMap[key], idx < cells.count else { return nil }
        let val = cells[idx].trimmingCharacters(in: .whitespacesAndNewlines)
        return val.isEmpty ? nil : val
    }

    static func heuristicDeadline(in html: String, cells: [String]) -> String? {
        if let match = extractDateRangeDeadline(in: html) {
            return match
        }
        let foundDates = extractDatesFromCells(cells)
        return resolveFoundDeadline(foundDates: foundDates, cells: cells)
    }

    private static func extractDatesFromCells(_ cells: [String]) -> [String] {
        let datePattern = #"\b(\d{4}[-./]\d{1,2}[-./]\d{1,2})\b"#
        guard let dateRe = try? NSRegularExpression(pattern: datePattern, options: []) else { return [] }
        var foundDates: [String] = []
        for cell in cells {
            let ns = cell as NSString
            let m = dateRe.matches(in: cell, range: NSRange(location: 0, length: ns.length))
            for match in m {
                let d = ns.substring(with: match.range)
                foundDates.append(normalizeDate(d))
            }
        }
        return foundDates
    }

    private static func resolveFoundDeadline(foundDates: [String], cells: [String]) -> String? {
        if foundDates.count >= 2 { return foundDates.last }
        guard foundDates.count == 1 else { return nil }
        let hasDeadlineCell = cells.contains { $0.contains("마감") }
        return hasDeadlineCell ? foundDates.first : nil
    }

    static func extractDateRangeDeadline(in text: String) -> String? {
        if let match = HTMLExtract.firstMatch(#"[~～]\s*(\d{4}[-./]\d{1,2}[-./]\d{1,2})"#, in: text) {
            return normalizeDate(match)
        }
        if let match = HTMLExtract.firstMatch(#"(?:마감|접수마감|신청기한)(?:일|일자)?\s*[:：]?\s*(\d{4}[-./]\d{1,2}[-./]\d{1,2})"#, in: text) {
            return normalizeDate(match)
        }
        return nil
    }

    static func extractAgencyFromSpan(in text: String) -> String? {
        let pattern = #"<span[^>]*class=["'][^"']*(?:agency|provider|dept|organ|writer)[^"']*["'][^>]*>([\s\S]*?)</span>"#
        guard let match = HTMLExtract.firstMatch(pattern, in: text) else { return nil }
        let clean = match.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    static func heuristicProvider(in cells: [String]) -> String? {
        let agencySuffixes = ["부", "처", "청", "원", "진흥원", "테크노파크", "센터", "공사", "공단", "재단", "협회", "연구원"]
        let nonAgencies: Set<String> = ["바우처", "벤처", "캡처", "피처", "크래처", "신청처", "접수처", "문의처"]
        for rawCell in cells {
            let plain = rawCell.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            let tokens = plain.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            for token in tokens {
                let clean = token.trimmingCharacters(in: .punctuationCharacters)
                guard clean.count >= 2, clean.count <= 25, !nonAgencies.contains(clean) else { continue }
                if let matched = matchAgencySuffix(clean, suffixes: agencySuffixes) {
                    return matched
                }
            }
        }
        return nil
    }

    private static func matchAgencySuffix(_ clean: String, suffixes: [String]) -> String? {
        for suffix in suffixes where clean.hasSuffix(suffix) {
            return clean
        }
        return nil
    }

    static func heuristicStatus(in text: String) -> String? {
        for s in ["접수중", "모집중", "마감임박", "접수마감", "마감", "종료"] {
            if text.contains(s) { return s }
        }
        return nil
    }

    static func normalizeDate(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-")
        let parts = cleaned.components(separatedBy: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return raw
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func resolveLiveness(status: String?, deadline: String?) -> OpportunityLiveness {
        if let live = livenessFromStatus(status) { return live }
        guard let deadline, let days = OpportunityScheduleAudit.daysUntilDeadline(deadline) else {
            return .alive
        }
        return livenessFromDays(days)
    }

    private static func livenessFromStatus(_ status: String?) -> OpportunityLiveness? {
        guard let st = status else { return nil }
        if st.contains("마감") || st.contains("종료") { return .expired }
        if st.contains("마감임박") { return .caution }
        return nil
    }

    private static func livenessFromDays(_ days: Int) -> OpportunityLiveness {
        if days < 0 { return .expired }
        return days <= 3 ? .caution : .alive
    }
}
