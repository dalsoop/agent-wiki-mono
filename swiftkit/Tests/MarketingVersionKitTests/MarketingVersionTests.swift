import XCTest
@testable import MarketingVersionKit

final class MarketingVersionTests: XCTestCase {
    func testRefuseReason() {
        XCTAssertNil(MarketingVersion.refuseReason("1.0.0"))
        XCTAssertNil(MarketingVersion.refuseReason("2.10.3"))
        XCTAssertNotNil(MarketingVersion.refuseReason(nil))
        XCTAssertNotNil(MarketingVersion.refuseReason("1"))
        XCTAssertNotNil(MarketingVersion.refuseReason("1.0"))
        XCTAssertNotNil(MarketingVersion.refuseReason("1.00"))
        XCTAssertNotNil(MarketingVersion.refuseReason("0.1.0"))
        XCTAssertNotNil(MarketingVersion.refuseReason("1.2"))
        XCTAssertNotNil(MarketingVersion.refuseReason("1.0.0-beta"))
        XCTAssertNotNil(MarketingVersion.refuseReason("01.0.0"))
        XCTAssertNil(MarketingVersion.parse("1.00"))
        XCTAssertNotNil(MarketingVersion.parse("1.0.0"))
    }

    func testRefuseIfSameWhileSourceStaleIsLintOnly() {
        XCTAssertNil(
            MarketingVersion.refuseIfSameWhileSourceStale(
                staged: "1.0.0", installed: "1.0.0", sourceIsStale: false
            )
        )
        XCTAssertNotNil(
            MarketingVersion.refuseIfSameWhileSourceStale(
                staged: "1.0.0", installed: "1.0.0", sourceIsStale: true
            )
        )
        XCTAssertNil(
            MarketingVersion.refuseIfNotAscending(staged: "1.0.0", installed: "1.0.0")
        )
    }

    func testRefuseIfNotAscending() {
        XCTAssertNil(MarketingVersion.refuseIfNotAscending(staged: "1.0.0", installed: nil))
        XCTAssertNil(MarketingVersion.refuseIfNotAscending(staged: "1.0.0", installed: "1.0.0"))
        XCTAssertNil(MarketingVersion.refuseIfNotAscending(staged: "1.0.1", installed: "1.0.0"))
        XCTAssertNotNil(MarketingVersion.refuseIfNotAscending(staged: "1.0.0", installed: "1.0.1"))
        XCTAssertNotNil(MarketingVersion.refuseIfNotAscending(staged: "1.9.9", installed: "2.0.0"))
    }

    func testDevelopmentPlaceholder() {
        XCTAssertTrue(MarketingVersion.isDevelopmentPlaceholder("0.1.0"))
        XCTAssertTrue(MarketingVersion.isDevelopmentPlaceholder("0"))
        XCTAssertFalse(MarketingVersion.isDevelopmentPlaceholder("1.0.0"))
    }

    func testSparkleAppcastPicksNewestBuild() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss><channel>
        <item><sparkle:shortVersionString>1.0.3</sparkle:shortVersionString><sparkle:version>10</sparkle:version></item>
        <item><sparkle:shortVersionString>1.0.6</sparkle:shortVersionString><sparkle:version>20</sparkle:version></item>
        </channel></rss>
        """
        let newest = SparkleAppcast.newest(xml)
        XCTAssertEqual(newest?.shortVersion, "1.0.6")
        XCTAssertEqual(newest?.build, "20")
    }

    func testSparkleAppcastReadsEnclosureURL() {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <rss><channel>
        <item>
          <sparkle:shortVersionString>1.0.4</sparkle:shortVersionString>
          <sparkle:version>1787398660</sparkle:version>
          <enclosure url="https://cdn.example.test/a.zip" length="5088596" type="application/octet-stream"/>
        </item>
        </channel></rss>
        """
        let newest = SparkleAppcast.newest(xml)
        XCTAssertEqual(newest?.enclosureURL, "https://cdn.example.test/a.zip")
        XCTAssertEqual(newest?.enclosureLength, 5088596)
    }

    func testShortVersionFromPlistXML() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>CFBundleShortVersionString</key><string>1.2.3</string>
        </dict></plist>
        """
        XCTAssertEqual(MarketingVersion.shortVersion(fromPlistXML: xml), "1.2.3")
        XCTAssertNil(MarketingVersion.shortVersion(fromPlistXML: "<plist></plist>"))
    }
}
