import XCTest
@testable import InteropKit

final class SparkleCDNFeedPathTests: XCTestCase {
    func testDevBaseURLDoesNotProduceDevObjectPath() {
        let canonical = SparkleCDNFeed.feedURL(
            bundleID: "net.ranode.menubar-below-notch",
            baseURL: SparkleCDNFeed.defaultBaseURL + "/dev")
        XCTAssertEqual(
            canonical,
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.menubar-below-notch"))
        XCTAssertTrue(SparkleCDNFeed.isDevObjectPath(
            SparkleCDNFeed.defaultBaseURL + "/dev/apps/net/ranode/menubar-below-notch/appcast.xml"))
        XCTAssertFalse(SparkleCDNFeed.isDevObjectPath(
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.menubar-below-notch")))
        XCTAssertTrue(SparkleCDNFeed.matchesPublishPath(
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.foo"),
            bundleID: "net.ranode.foo"))
        XCTAssertFalse(SparkleCDNFeed.matchesPublishPath(
            SparkleCDNFeed.defaultBaseURL + "/dev/apps/net/ranode/foo/appcast.xml",
            bundleID: "net.ranode.foo"))
    }
}
