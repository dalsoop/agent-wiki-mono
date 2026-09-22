import Foundation
import WebCrawlKit
import MoneyInflowKit

public enum CrawlError: Error, LocalizedError, Sendable {
    case http(Int)
    case decode
    public var errorDescription: String? {
        switch self {
        case .http(let s): return "HTTP \(s)"
        case .decode: return "파싱 오류"
        }
    }
}

public struct BizInfoCrawler: Sendable {
    public static let baseURL = BizInfoEndpoints.crawlURLString
    public init() {}

    /// pages 개 페이지를 긁어 공고를 모은다(페이지당 ~15건).
    public func crawl(pages: Int = BizInfoEndpoints.defaultCrawlPages) async throws -> [GovernmentProgram] {
        var all = [GovernmentProgram]()
        var seen = Set<String>()
        for page in 1...max(1, pages) {
            let url = BizInfoEndpoints.crawlPageURL(page)
            let html: String
            do {
                html = try await WebFetch.get(url, timeout: BizInfoEndpoints.fetchTimeoutSeconds)
            } catch {
                if all.isEmpty { throw CrawlError.http(0) }
                break
            }
            let rows = Self.parse(html: html)
            if rows.isEmpty { break }
            if page > 1, let first = rows.first, first.id == all.first?.id { break }
            if !all.isEmpty, rows.allSatisfy({ seen.contains($0.id) }) { break }
            for p in rows { seen.insert(p.id) }
            all.append(contentsOf: rows)
        }
        return all
    }

    /// HTML 에서 공고 행을 파싱(WebCrawlKit.HTMLExtract 사용).
    public static func parse(html: String) -> [GovernmentProgram] {
        let nshtml = html as NSString
        let idMatches = HTMLExtract.allMatches(#"pblancId=(PBLN_\d+)"#, in: html)

        var out = [GovernmentProgram]()
        for id in idMatches {
            guard let idRange = nshtml.range(of: "pblancId=\(id)").nilIfNotFound,
                  let rowRange = HTMLExtract.enclosingRange(containing: idRange.location, in: nshtml) else { continue }
            let rowHTML = nshtml.substring(with: rowRange)

            let titleAttr = HTMLExtract.firstMatch(#"<a[^>]*title="([^"]+)""#, in: rowHTML) ?? ""
            let detailPath = HTMLExtract.firstMatch(#"href=\s*"([^"]*selectSIIA200Detail[^"]*)"#, in: rowHTML) ?? ""
            let periodRaw = HTMLExtract.firstMatch(#"(\d{4}-\d{2}-\d{2}\s*~\s*\d{4}-\d{2}-\d{2})"#, in: rowHTML) ?? ""

            let cells = HTMLExtract.cells(in: rowHTML)
            let categoryText = cells.count > 1 ? cells[1] : ""
            let provider = cells.count > 5 ? cells[5] : (cells.count > 4 ? cells[4] : "")
            let agency = cells.count > 4 ? cells[4] : ""
            let regDate = cells.count > 6 ? cells[6] : ""

            let cleanAttr = titleAttr.replacingOccurrences(of: " 페이지 이동", with: "")
                .replacingOccurrences(of: " 상세페이지 이동", with: "")
            let displayTitle = (cells.count > 2 && !cells[2].isEmpty) ? cells[2] : (cleanAttr.isEmpty ? id : cleanAttr)
            let detailURL = detailPath.isEmpty ? nil : URL(string: BizInfoEndpoints.origin + detailPath)

            let catAndTitle = categoryText + " " + displayTitle
            out.append(GovernmentProgram(
                id: id,
                title: displayTitle,
                providerName: provider.isEmpty ? agency : provider,
                summary: "",
                categories: GovernmentProgram.categories(from: catAndTitle),
                regions: GovernmentProgram.regions(from: displayTitle),
                targetAudienceText: displayTitle,
                period: ApplicationPeriod.parse(periodRaw.replacingOccurrences(of: "-", with: "")),
                detailURL: detailURL,
                providerAgency: agency,
                applyURL: detailURL,
                registrationDate: regDate,
                hashTags: nil
            ))
        }
        return out
    }
}

private extension NSRange {
    var nilIfNotFound: NSRange? { location == NSNotFound ? nil : self }
}
