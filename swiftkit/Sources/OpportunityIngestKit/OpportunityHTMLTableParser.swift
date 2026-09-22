import Foundation
import HTTPClientKit
import WebCrawlKit
import OpportunityIntelKit

/// 정적 공고 게시판(HTML table tr/td 또는 ul/ol li 리스트) 구조에서
/// 제목, 링크, 마감일, 담당기관 텍스트를 추출하는 경량 휴리스틱 파서
public enum OpportunityHTMLTableParser {

    /// 파싱된 원시 행 데이터
    public struct ParsedRow: Sendable, Equatable {
        public var title: String
        public var url: String
        public var provider: String?
        public var category: String?
        public var deadline: String?
        public var postDate: String?
        public var status: String?
        public var summary: String?

        public init(
            title: String,
            url: String,
            provider: String? = nil,
            category: String? = nil,
            deadline: String? = nil,
            postDate: String? = nil,
            status: String? = nil,
            summary: String? = nil
        ) {
            self.title = title
            self.url = url
            self.provider = provider
            self.category = category
            self.deadline = deadline
            self.postDate = postDate
            self.status = status
            self.summary = summary
        }
    }

    /// HTML 게시판(테이블 및 리스트) 파싱 후 [OpportunityIntelItem] 생성
    public static func parse(
        html: String,
        baseURL: URL,
        defaultProvider: String = "공고게시판",
        defaultCategory: String = "gov-grants"
    ) -> [OpportunityIntelItem] {
        let rows = parseRows(html: html, baseURL: baseURL)
        return rows.compactMap { row in
            convertToItem(row: row, baseURL: baseURL, defaultProvider: defaultProvider, defaultCategory: defaultCategory)
        }
    }

    /// HTML 문자열로부터 공고 행 추출
    public static func parseRows(html: String, baseURL: URL) -> [ParsedRow] {
        var results = parseTableRows(html: html, baseURL: baseURL)
        appendFallbackListRows(html: html, baseURL: baseURL, into: &results)
        return results
    }

    private static func appendFallbackListRows(html: String, baseURL: URL, into results: inout [ParsedRow]) {
        guard results.count < 3 else { return }
        let listRows = parseListRows(html: html, baseURL: baseURL)
        for lr in listRows {
            if !results.contains(where: { $0.url == lr.url || $0.title == lr.title }) {
                results.append(lr)
            }
        }
    }

    /// 원격 URL에서 HTML을 수신하여 공고 추출
    public static func fetchAndParse(
        url: URL,
        defaultProvider: String = "공고게시판",
        defaultCategory: String = "gov-grants",
        client: any HTTPClient = URLSessionHTTPClient()
    ) async throws -> [OpportunityIntelItem] {
        var headers = WebFetch.standardBrowserHeaders
        headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"

        let (status, body) = try await client.send(method: "GET", url: url, headers: headers, body: nil)
        guard (200..<300).contains(status) else { return [] }
        let html = String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
        guard !html.isEmpty else { return [] }

        return parse(html: html, baseURL: url, defaultProvider: defaultProvider, defaultCategory: defaultCategory)
    }

    // MARK: - Table Row Parsing

    private static func parseTableRows(html: String, baseURL: URL) -> [ParsedRow] {
        let trPattern = #"<tr[^>]*>([\s\S]*?)</tr>"#
        guard let trRegex = try? NSRegularExpression(pattern: trPattern, options: .caseInsensitive) else { return [] }
        let nsHTML = html as NSString
        let matches = trRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        var headerMap: [String: Int] = [:]
        var rows: [ParsedRow] = []

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let trContent = nsHTML.substring(with: match.range(at: 1))

            if trContent.contains("<th") {
                let ths = extractHeaderCells(trContent)
                if !ths.isEmpty {
                    headerMap = buildHeaderMap(ths)
                    continue
                }
            }

            let cells = HTMLExtract.cells(in: trContent)
            guard !cells.isEmpty else { continue }

            let links = HTMLExtract.links(in: trContent, base: baseURL.absoluteString)
            guard let bestLink = selectBestLink(links: links, cells: cells) else {
                continue
            }

            let resolvedURL = OpportunityURLResolver.resolve(relative: bestLink.href, baseURL: baseURL) ?? bestLink.href
            let title = cleanTitle(bestLink.text)
            guard !title.isEmpty, isUsableTitle(title) else { continue }

            let deadline = extractField(named: "deadline", cells: cells, headerMap: headerMap) ?? heuristicDeadline(in: trContent, cells: cells)
            let provider = extractField(named: "provider", cells: cells, headerMap: headerMap) ?? heuristicProvider(in: cells)
            let category = extractField(named: "category", cells: cells, headerMap: headerMap)
            let status = extractField(named: "status", cells: cells, headerMap: headerMap) ?? heuristicStatus(in: trContent)
            let postDate = extractField(named: "date", cells: cells, headerMap: headerMap)

            rows.append(ParsedRow(
                title: title,
                url: resolvedURL,
                provider: provider,
                category: category,
                deadline: deadline,
                postDate: postDate,
                status: status,
                summary: trContent
            ))
        }

        return rows
    }

    // MARK: - List Row Parsing

    private static func parseListRows(html: String, baseURL: URL) -> [ParsedRow] {
        let liPattern = #"<li[^>]*>([\s\S]*?)</li>"#
        guard let liRegex = try? NSRegularExpression(pattern: liPattern, options: .caseInsensitive) else { return [] }
        let nsHTML = html as NSString
        let matches = liRegex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))

        var rows: [ParsedRow] = []

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let liContent = nsHTML.substring(with: match.range(at: 1))

            let links = HTMLExtract.links(in: liContent, base: baseURL.absoluteString)
            guard let bestLink = selectBestLink(links: links, cells: []) else { continue }

            let title = cleanTitle(bestLink.text)
            guard isUsableTitle(title) else { continue }

            let resolvedURL = OpportunityURLResolver.resolve(relative: bestLink.href, baseURL: baseURL) ?? bestLink.href
            let deadline = extractDateRangeDeadline(in: liContent) ?? heuristicDeadline(in: liContent, cells: [])
            let status = heuristicStatus(in: liContent)
            let provider = extractAgencyFromSpan(in: liContent) ?? heuristicProvider(in: [liContent])

            rows.append(ParsedRow(
                title: title,
                url: resolvedURL,
                provider: provider,
                category: nil,
                deadline: deadline,
                postDate: nil,
                status: status,
                summary: liContent
            ))
        }

        return rows
    }

    // MARK: - Heuristics & Helpers

    private static func selectBestLink(links: [(href: String, text: String)], cells: [String]) -> (href: String, text: String)? {
        let filtered = links.filter { link in
            let href = link.href.lowercased()
            let txt = link.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if href.contains("javascript:void") && txt.isEmpty { return false }
            if ["첨부", "다운로드", "pdf", "hwp", "상세보기", "바로가기", "이전", "다음", "view", "more"].contains(txt.lowercased()) {
                return false
            }
            return !txt.isEmpty
        }

        return filtered.max(by: { $0.text.count < $1.text.count })
    }

    private static func cleanTitle(_ raw: String) -> String {
        var s = HTMLExtract.decodeEntities(raw)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsableTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count < 4 { return false }
        let lower = trimmed.lowercased()
        let navKeywords = [
            "목록", "공지사항", "게시판", "번호", "작성일", "조회수",
            "이용약관", "개인정보처리방침", "자료실", "회원가입", "로그인", "통합회원",
            "새창으로", "바로가기", "상담하기", "자주하는 질문", "사이트맵",
            "매뉴얼", "알림마당", "고객센터", "찾아오시는길", "소식", "카드뉴스", "신고센터"
        ]
        if navKeywords.contains(where: { lower.contains($0) }) { return false }
        return true
    }

    private static func extractHeaderCells(_ tr: String) -> [String] {
        let ns = tr as NSString
        guard let re = try? NSRegularExpression(pattern: #"<th[^>]*>([\s\S]*?)</th>"#, options: .caseInsensitive) else { return [] }
        return re.matches(in: tr, range: NSRange(location: 0, length: ns.length)).map { m in
            var inner = ns.substring(with: m.range(at: 1))
            inner = inner.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            inner = HTMLExtract.decodeEntities(inner)
            return inner.components(separatedBy: .whitespacesAndNewlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        }
    }

    private static func convertToItem(
        row: ParsedRow,
        baseURL: URL,
        defaultProvider: String,
        defaultCategory: String
    ) -> OpportunityIntelItem {
        let provider = row.provider ?? defaultProvider
        let host = OpportunityURLResolver.extractHost(from: row.url) ?? provider.lowercased()
        let canonical = host.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")

        let idHash = String(format: "%08x", abs(row.url.hashValue))
        let id = "\(canonical):\(idHash)"

        let signals = OpportunitySignalParser.parse(title: row.title, body: row.summary ?? "")
        let actualVal = signals.pricesOrGrants.first
        let rate = signals.discountOrSupportRates.first
        let code = signals.codes.first

        let normalizedDeadline = row.deadline.map(normalizeDate)
        let liveness = resolveLiveness(status: row.status, deadline: normalizedDeadline)

        let todayStr = ISO8601DateFormatter().string(from: Date()).prefix(10).description
        let firstSeen = row.postDate.map(normalizeDate) ?? todayStr

        return OpportunityIntelItem(
            id: id,
            provider: provider,
            canonical: canonical,
            title: row.title,
            summary: row.title,
            url: row.url,
            category: row.category ?? defaultCategory,
            standardValue: signals.pricesOrGrants.count > 1 ? signals.pricesOrGrants[1] : nil,
            actualValue: actualVal,
            discountOrSupportRate: rate,
            opportunityCode: code,
            deadline: normalizedDeadline,
            prerequisites: nil,
            score: 80,
            liveness: liveness,
            firstSeen: firstSeen,
            lastSeen: todayStr,
            tags: signals.tags
        )
    }
}

// MARK: - IngestNode Integration

/// HTML Table 기반 기회 수집 노드
public struct HTMLTableOpportunityIngestNode: OpportunityIngestNode {
    public var nodeId: String
    public var category: String
    public var pageURL: URL
    public var defaultProvider: String
    public var client: any HTTPClient

    public init(
        nodeId: String,
        category: String = "gov-grants",
        pageURL: URL,
        defaultProvider: String = "공고게시판",
        client: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.nodeId = nodeId
        self.category = category
        self.pageURL = pageURL
        self.defaultProvider = defaultProvider
        self.client = client
    }

    public func ingest() async throws -> [OpportunityIntelItem] {
        try await OpportunityHTMLTableParser.fetchAndParse(
            url: pageURL,
            defaultProvider: defaultProvider,
            defaultCategory: category,
            client: client
        )
    }
}
