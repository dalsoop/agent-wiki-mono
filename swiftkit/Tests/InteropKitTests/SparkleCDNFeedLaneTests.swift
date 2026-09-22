import XCTest
@testable import InteropKit

/// Sparkle CDN 레인 판정 — 손님 `apps/` 정본과 개발 `dev/apps/` 를 갈라 주는 규약.
/// 기본(인자 없는 `feedURL`)은 손님 정본이고, dev 경로는 **레인을 명시할 때만** 나온다.
/// 발행 백엔드는 `apps/` 에만 올리므로 명시 없이 dev 를 골라 담으면 설치본이
/// 영구 404 를 돈다(실측 2026-08-22: 설치본 7개 `/dev/apps/` 404).
final class SparkleCDNFeedLaneTests: XCTestCase {
    func testExplicitDeveloperLaneUsesDevPrefix() {
        XCTAssertEqual(
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.foo", lane: .developer),
            "https://cdn.ranode.net/dev/apps/net/ranode/foo/appcast.xml"
        )
        XCTAssertEqual(
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.foo", baseURL: "https://x.test/", lane: .developer),
            "https://x.test/dev/apps/net/ranode/foo/appcast.xml"
        )
    }

    func testProductionLaneMatchesPlainFeedURL() {
        XCTAssertEqual(
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.foo", lane: .production),
            SparkleCDNFeed.feedURL(bundleID: "net.ranode.foo")
        )
    }

    func testLaneFromEnvironment() {
        XCTAssertEqual(SparkleCDNFeed.Lane.fromEnvironment([:]), .developer)
        XCTAssertEqual(SparkleCDNFeed.Lane.fromEnvironment(["SHIP_MODE": "developer"]), .developer)
        XCTAssertEqual(SparkleCDNFeed.Lane.fromEnvironment(["SHIP_MODE": "publish"]), .production)
    }

    func testDevObjectPathDetection() {
        XCTAssertTrue(SparkleCDNFeed.isDevObjectPath(
            "https://cdn.ranode.net/dev/apps/net/ranode/foo/appcast.xml"
        ))
        XCTAssertFalse(SparkleCDNFeed.isDevObjectPath(
            "https://cdn.ranode.net/apps/net/ranode/foo/appcast.xml"
        ))
    }
}
