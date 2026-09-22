import Foundation

/// 기업마당(bizinfo.go.kr) 공개 페이지·오픈API 주소. 크롤러·샘플·설정 링크가 같이 쓴다.
public enum BizInfoEndpoints: Sendable {
    /// 호스트만 상수로 둔다. 전체 origin 은 아래에서 조립한다(KinfaSite 와 같은 형태).
    public static let host = "www.bizinfo.go.kr"
    public static let origin = "https://" + host
    public static let listingPath = "/see/seea/selectSEEA100.do"
    public static let listingMenuId = "80001001001"
    public static let listingURLString = "\(origin)\(listingPath)?menuId=\(listingMenuId)"
    public static let crawlURLString = "\(listingURLString)&schEndAt=N"
    public static let openAPIURLString = "\(origin)/uss/rss/bizinfoApi.do"
    public static let fetchTimeoutSeconds: TimeInterval = 20
    /// 기업마당 목록은 pageIndex 가 아니라 cpage 다. 접수중 목록이 100페이지를 넘는다.
    public static let defaultCrawlPages = 120
    public static let rowsPerPage = 15

    public static func crawlPageURL(_ page: Int) -> URL {
        URL(string: "\(crawlURLString)&cpage=\(max(1, page))&rows=\(rowsPerPage)")!
    }

    public static func detailURL(pblancId: String) -> URL {
        URL(string: "\(origin)/web/lay1/bbs/S1T122C128/AS/74/view.do?pblancId=\(pblancId)")!
    }

    public static func fileDownloadURL(atchFileId: String, fileSn: String) -> URL {
        URL(string: "\(origin)/cmm/fms/fileDown.do?atchFileId=\(atchFileId)&fileSn=\(fileSn)")!
    }

    public static var listingURL: URL { URL(string: listingURLString)! }
}
