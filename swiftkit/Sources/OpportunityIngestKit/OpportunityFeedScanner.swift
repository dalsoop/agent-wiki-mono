import Foundation
import HTTPClientKit
import WebCrawlKit
import OpportunityIntelKit

/// 범용 RSS 2.0 / Atom XML 피드 스캐너
/// 정부지원사업(K-Startup, 나라장터, 기업마당 등) 피드 및 온라인 딜/할인 사이트 피드로부터
/// 공고/딜 제목, 링크, 작성일자, 카테고리를 추출하여 [OpportunityIntelItem] 규격으로 변환
public enum OpportunityFeedScanner {

    /// 원시 피드 아이템 구조체
    public struct RawFeedItem: Sendable, Equatable {
        public var title: String
        public var link: String
        public var guid: String
        public var pubDate: String
        public var category: String
        public var description: String
        public var author: String

        public init(
            title: String = "",
            link: String = "",
            guid: String = "",
            pubDate: String = "",
            category: String = "",
            description: String = "",
            author: String = ""
        ) {
            self.title = title
            self.link = link
            self.guid = guid
            self.pubDate = pubDate
            self.category = category
            self.description = description
            self.author = author
        }
    }

    /// XML Data로부터 OpportunityIntelItem 목록을 추출
    public static func scan(
        xmlData: Data,
        defaultProvider: String? = nil,
        defaultCategory: String = "feed",
        baseURL: URL? = nil
    ) -> [OpportunityIntelItem] {
        let delegate = FeedXMLParserDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = true
        parser.parse()

        let provider = defaultProvider ?? (!delegate.channelTitle.isEmpty ? delegate.channelTitle : "Feed")
        let effectiveBaseURL = baseURL ?? URL(string: delegate.channelLink)

        return delegate.items.compactMap { raw in
            convert(raw: raw, provider: provider, defaultCategory: defaultCategory, baseURL: effectiveBaseURL)
        }
    }

    /// XML 문자열로부터 OpportunityIntelItem 목록을 추출
    public static func scan(
        xmlString: String,
        defaultProvider: String? = nil,
        defaultCategory: String = "feed",
        baseURL: URL? = nil
    ) -> [OpportunityIntelItem] {
        guard let data = xmlString.data(using: .utf8) else { return [] }
        return scan(xmlData: data, defaultProvider: defaultProvider, defaultCategory: defaultCategory, baseURL: baseURL)
    }

    /// URL로부터 피드를 비동기 수신하여 OpportunityIntelItem 목록으로 추출
    public static func fetchAndScan(
        feedURL: URL,
        defaultProvider: String? = nil,
        defaultCategory: String = "feed",
        client: any HTTPClient = URLSessionHTTPClient()
    ) async throws -> [OpportunityIntelItem] {
        var headers = WebFetch.standardBrowserHeaders
        headers["Accept"] = "application/rss+xml, application/atom+xml, application/xml, text/xml;q=0.9, */*;q=0.8"

        let (status, body) = try await client.send(method: "GET", url: feedURL, headers: headers, body: nil)
        guard (200..<300).contains(status) else {
            return []
        }

        return scan(xmlData: body, defaultProvider: defaultProvider, defaultCategory: defaultCategory, baseURL: feedURL)
    }

    // MARK: - Private Conversion Logic

    private static func convert(
        raw: RawFeedItem,
        provider: String,
        defaultCategory: String,
        baseURL: URL?
    ) -> OpportunityIntelItem? {
        let cleanTitle = HTMLExtract.decodeEntities(raw.title)
            .components(separatedBy: .whitespacesAndNewlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleanTitle.isEmpty else { return nil }

        var rawURL = raw.link.trimmingCharacters(in: .whitespacesAndNewlines)
        if rawURL.isEmpty && raw.guid.hasPrefix("http") {
            rawURL = raw.guid.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let resolvedURL: String
        if let base = baseURL {
            resolvedURL = OpportunityURLResolver.resolve(relative: rawURL, baseURL: base) ?? rawURL
        } else {
            resolvedURL = OfferURLNormalizer.normalize(rawURL)
        }

        guard !resolvedURL.isEmpty else { return nil }

        let rawSummary = raw.description
        let plainSummary = HTMLExtract.decodeEntities(
            rawSummary.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        ).components(separatedBy: .whitespacesAndNewlines)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

        let signals = OpportunitySignalParser.parse(title: cleanTitle, body: plainSummary)
        let actualVal = signals.pricesOrGrants.first
        let rate = signals.discountOrSupportRates.first
        let code = signals.codes.first

        let pubDateStr = parseDateToYYYYMMDD(raw.pubDate)
        let deadlineStr = extractDeadline(from: "\(cleanTitle) \(plainSummary)")

        let host = OpportunityURLResolver.extractHost(from: resolvedURL) ?? provider.lowercased()
        let canonical = host.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")

        let idSeed = !raw.guid.isEmpty ? raw.guid : resolvedURL
        let idHash = String(format: "%08x", abs(idSeed.hashValue))
        let id = "\(canonical):\(idHash)"

        let category = !raw.category.isEmpty ? raw.category : defaultCategory
        let itemProvider = !raw.author.isEmpty ? raw.author : provider

        let todayStr = ISO8601DateFormatter().string(from: Date()).prefix(10).description
        let firstSeen = pubDateStr ?? todayStr
        let lastSeen = todayStr

        let liveness = determineLiveness(deadline: deadlineStr, text: "\(cleanTitle) \(plainSummary)")

        return OpportunityIntelItem(
            id: id,
            provider: itemProvider,
            canonical: canonical,
            title: cleanTitle,
            summary: plainSummary,
            url: resolvedURL,
            category: category,
            standardValue: signals.pricesOrGrants.count > 1 ? signals.pricesOrGrants[1] : nil,
            actualValue: actualVal,
            discountOrSupportRate: rate,
            opportunityCode: code,
            deadline: deadlineStr,
            prerequisites: nil,
            score: 85,
            liveness: liveness,
            firstSeen: firstSeen,
            lastSeen: lastSeen,
            tags: signals.tags
        )
    }

    // MARK: - Date & Liveness Helpers

    // MARK: - Date & Liveness Helpers

    public static func parseDateToYYYYMMDD(_ dateString: String) -> String? {
        let trimmed = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let match = HTMLExtract.firstMatch(#"^(\d{4}[-./]\d{1,2}[-./]\d{1,2})"#, in: trimmed) {
            return normalizeDate(match)
        }
        return parseFallbackDates(trimmed)
    }

    private static func parseFallbackDates(_ trimmed: String) -> String? {
        if let d = ISO8601DateFormatter().date(from: trimmed) {
            return formatYYYYMMDD(d)
        }
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy.MM.dd HH:mm:ss"
        ]
        for fmt in formats {
            let df = DateFormatter()
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = fmt
            if let d = df.date(from: trimmed) {
                return formatYYYYMMDD(d)
            }
        }
        return nil
    }

    public static func extractDeadline(from text: String) -> String? {
        let patterns = [
            #"[~～]\s*(\d{4}[-./]\d{1,2}[-./]\d{1,2})"#,
            #"(?:마감|접수마감|신청기한)(?:일|일자)?\s*[:：]?\s*(\d{4}[-./]\d{1,2}[-./]\d{1,2})"#,
            #"\d{4}[-./]\d{1,2}[-./]\d{1,2}\s*[~～]\s*(\d{4}[-./]\d{1,2}[-./]\d{1,2})"#
        ]
        for p in patterns {
            if let match = HTMLExtract.firstMatch(p, in: text) {
                return normalizeDate(match)
            }
        }
        return nil
    }

    public static func determineLiveness(deadline: String?, text: String) -> OpportunityLiveness {
        if let deadline, let days = OpportunityScheduleAudit.daysUntilDeadline(deadline) {
            return livenessFromDays(days)
        }
        return livenessFromText(text)
    }

    private static func livenessFromDays(_ days: Int) -> OpportunityLiveness {
        if days < 0 { return .expired }
        return days <= 3 ? .caution : .alive
    }

    private static func livenessFromText(_ text: String) -> OpportunityLiveness {
        let expiredKeywords = ["접수마감", "신청마감", "모집마감", "종료"]
        for kw in expiredKeywords {
            if text.contains(kw) { return .expired }
        }
        return text.contains("마감임박") ? .caution : .alive
    }

    private static func normalizeDate(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: ".", with: "-").replacingOccurrences(of: "/", with: "-")
        let parts = cleaned.components(separatedBy: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else {
            return raw
        }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private static func formatYYYYMMDD(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(identifier: "Asia/Seoul") ?? TimeZone.current
        return df.string(from: date)
    }
}

// MARK: - XMLParserDelegate Implementation

private final class FeedXMLParserDelegate: NSObject, XMLParserDelegate {
    var channelTitle: String = ""
    var channelLink: String = ""
    var channelDescription: String = ""
    var items: [OpportunityFeedScanner.RawFeedItem] = []

    private var inItem: Bool = false
    private var curElement: String = ""
    private var curText: String = ""

    private var curTitle: String = ""
    private var curLink: String = ""
    private var curGuid: String = ""
    private var curPubDate: String = ""
    private var curCategory: String = ""
    private var curDescription: String = ""
    private var curAuthor: String = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let lower = elementName.lowercased()
        curElement = lower
        curText = ""

        if lower == "item" || lower == "entry" {
            resetItemState()
        }
        if inItem {
            handleItemAttributes(element: lower, attributes: attributes)
        }
    }

    private func resetItemState() {
        inItem = true
        curTitle = ""
        curLink = ""
        curGuid = ""
        curPubDate = ""
        curCategory = ""
        curDescription = ""
        curAuthor = ""
    }

    private func handleItemAttributes(element: String, attributes: [String: String]) {
        if element == "link" {
            handleLinkAttribute(attributes)
        } else if element == "category" {
            handleCategoryAttribute(attributes)
        }
    }

    private func handleLinkAttribute(_ attributes: [String: String]) {
        guard let href = attributes["href"], !href.isEmpty else { return }
        let rel = attributes["rel"]
        let isAlternate = rel == "alternate" || rel == nil
        if isAlternate || curLink.isEmpty {
            curLink = href
        }
    }

    private func handleCategoryAttribute(_ attributes: [String: String]) {
        if let term = attributes["term"], !term.isEmpty {
            curCategory = term
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        curText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let s = String(data: CDATABlock, encoding: .utf8) {
            curText += s
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let lower = elementName.lowercased()
        let text = curText.trimmingCharacters(in: .whitespacesAndNewlines)

        if inItem {
            handleItemEnd(lower: lower, text: text)
        } else {
            handleChannelEnd(lower: lower, text: text)
        }
    }

    private func handleItemEnd(lower: String, text: String) {
        switch lower {
        case "title":
            curTitle = text
        case "link":
            setIfEmpty(&curLink, text)
        case "guid", "id":
            setIfEmpty(&curGuid, text)
        case "pubdate", "published", "updated", "dc:date", "date":
            setIfEmpty(&curPubDate, text)
        case "category", "dc:subject":
            setIfEmpty(&curCategory, text)
        case "description", "summary":
            setIfEmpty(&curDescription, text)
        case "content", "content:encoded":
            setIfNotEmpty(&curDescription, text)
        case "author", "dc:creator":
            setIfEmpty(&curAuthor, text)
        case "item", "entry":
            finishCurrentItem()
        default:
            break
        }
    }

    private func setIfEmpty(_ target: inout String, _ value: String) {
        if target.isEmpty { target = value }
    }

    private func setIfNotEmpty(_ target: inout String, _ value: String) {
        if !value.isEmpty { target = value }
    }

    private func finishCurrentItem() {
        inItem = false
        let item = OpportunityFeedScanner.RawFeedItem(
            title: curTitle,
            link: curLink,
            guid: curGuid,
            pubDate: curPubDate,
            category: curCategory,
            description: curDescription,
            author: curAuthor
        )
        items.append(item)
    }

    private func handleChannelEnd(lower: String, text: String) {
        switch lower {
        case "title":
            setIfEmpty(&channelTitle, text)
        case "link":
            setIfEmpty(&channelLink, text)
        case "description":
            setIfEmpty(&channelDescription, text)
        default:
            break
        }
    }
}

// MARK: - IngestNode Integration

/// Feed 기반 기회 수집 노드
public struct FeedOpportunityIngestNode: OpportunityIngestNode {
    public var nodeId: String
    public var category: String
    public var feedURL: URL
    public var defaultProvider: String?
    public var client: any HTTPClient

    public init(
        nodeId: String,
        category: String = "gov-grants",
        feedURL: URL,
        defaultProvider: String? = nil,
        client: any HTTPClient = URLSessionHTTPClient()
    ) {
        self.nodeId = nodeId
        self.category = category
        self.feedURL = feedURL
        self.defaultProvider = defaultProvider
        self.client = client
    }

    public func ingest() async throws -> [OpportunityIntelItem] {
        try await OpportunityFeedScanner.fetchAndScan(
            feedURL: feedURL,
            defaultProvider: defaultProvider,
            defaultCategory: category,
            client: client
        )
    }
}
