import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// appcast.xml 에서 최신 `sparkle:version` / `sparkle:shortVersionString`.
/// 네트워크는 DistributionCore `SparkleFeedGate` 가 담당한다.
public enum SparkleAppcast: Sendable {
    public struct Release: Sendable, Equatable {
        public var shortVersion: String
        public var build: String
        public var enclosureURL: String?
        public var enclosureLength: Int?
        public init(
            shortVersion: String,
            build: String,
            enclosureURL: String? = nil,
            enclosureLength: Int? = nil
        ) {
            self.shortVersion = shortVersion
            self.build = build
            self.enclosureURL = enclosureURL
            self.enclosureLength = enclosureLength
        }
    }

    public static func newest(_ xml: String) -> Release? {
        guard let data = xml.data(using: .utf8) else { return nil }
        return newest(data)
    }

    public static func newest(_ data: Data) -> Release? {
        let parser = FeedParser()
        parser.parse(data)
        return newest(parser.items)
    }

    public static func newest(_ items: [Release]) -> Release? {
        guard var best = items.first else { return nil }
        for item in items.dropFirst() where isNewer(item, than: best) { best = item }
        return best
    }

    private static func isNewer(_ lhs: Release, than rhs: Release) -> Bool {
        if let a = Int(lhs.build), let b = Int(rhs.build) { return a > b }
        return lhs.build > rhs.build
    }
}

private final class FeedParser: NSObject, XMLParserDelegate {
    var items: [SparkleAppcast.Release] = []
    private var inItem = false
    private var short = ""
    private var build = ""
    private var enclosureURL = ""
    private var enclosureLength: Int?
    private var cur = ""

    func parse(_ data: Data) {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        cur = ""
        if elementName == "item" {
            inItem = true
            short = ""
            build = ""
            enclosureURL = ""
            enclosureLength = nil
        }
        if inItem, elementName == "enclosure" {
            enclosureURL = attributes["url"] ?? ""
            enclosureLength = Int(attributes["length"] ?? "")
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        cur += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let value = cur.trimmingCharacters(in: .whitespacesAndNewlines)
        if inItem {
            switch elementName {
            case "sparkle:version":
                build = value
            case "sparkle:shortVersionString":
                short = value
            case "item":
                inItem = false
                if !build.isEmpty || !short.isEmpty {
                    items.append(.init(
                        shortVersion: short,
                        build: build,
                        enclosureURL: enclosureURL.isEmpty ? nil : enclosureURL,
                        enclosureLength: enclosureLength
                    ))
                }
            default:
                break
            }
        }
        cur = ""
    }
}
