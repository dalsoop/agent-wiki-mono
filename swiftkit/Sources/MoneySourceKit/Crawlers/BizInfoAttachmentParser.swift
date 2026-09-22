import Foundation
import WebCrawlKit

public struct BizInfoAttachment: Equatable, Sendable {
    public var atchFileId: String
    public var fileSn: String
    public var fileName: String

    public var ext: String {
        (fileName as NSString).pathExtension.lowercased()
    }

    public var isHangulForm: Bool {
        ext == "hwp" || ext == "hwpx"
    }

    public init(atchFileId: String, fileSn: String, fileName: String) {
        self.atchFileId = atchFileId
        self.fileSn = fileSn
        self.fileName = fileName
    }
}

public enum BizInfoAttachmentParser {
    public static func parse(html: String) -> [BizInfoAttachment] {
        var out: [BizInfoAttachment] = []
        var seen = Set<String>()
        let pattern = #"/cmm/fms/fileDown\.do\?atchFileId=([^&\"']+)&fileSn=(\d+)[^>]*title="첨부파일 ([^"]+) 다운로드""#
        let regex = RegexLoad.regularExpression(pattern: pattern)
        let ns = html as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let regex {
            for match in regex.matches(in: html, range: full) {
                guard match.numberOfRanges >= 4 else { continue }
                let id = ns.substring(with: match.range(at: 1))
                let sn = ns.substring(with: match.range(at: 2))
                let name = unescape(ns.substring(with: match.range(at: 3)))
                let key = "\(id)#\(sn)"
                if seen.insert(key).inserted {
                    out.append(BizInfoAttachment(atchFileId: id, fileSn: sn, fileName: name))
                }
            }
        }
        if !out.isEmpty { return out }

        let loose = RegexLoad.regularExpression(pattern: #"atchFileId=([^&\"']+)&fileSn=(\d+)"#)
        if let loose {
            for match in loose.matches(in: html, range: full) {
                let id = ns.substring(with: match.range(at: 1))
                let sn = ns.substring(with: match.range(at: 2))
                let key = "\(id)#\(sn)"
                guard seen.insert(key).inserted else { continue }
                let nearby = nearbyName(in: ns, around: match.range)
                out.append(BizInfoAttachment(atchFileId: id, fileSn: sn, fileName: nearby))
            }
        }
        return out
    }

    private static func nearbyName(in html: NSString, around range: NSRange) -> String {
        let start = max(0, range.location - 80)
        let end = min(html.length, range.location + range.length + 220)
        let window = html.substring(with: NSRange(location: start, length: end - start))
        if let named = HTMLExtract.firstMatch(#"첨부파일 ([^"]+) 다운로드"#, in: window) {
            return unescape(named)
        }
        if let named = HTMLExtract.firstMatch(#">([^<]+\.(?:hwp|hwpx|pdf|zip))<"#, in: window) {
            return unescape(named)
        }
        return "attachment.bin"
    }

    private static func unescape(_ raw: String) -> String {
        raw.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
