import Foundation
import XCTest
@testable import PackageIdentityKit

final class AppBundleIDTests: XCTestCase {
    func testKnownConstants() {
        XCTAssertEqual(AppBundleID.fleetDock.rawValue, "net.ranode.fleet-dock")
        XCTAssertEqual(AppBundleID.agentWorkTodo.rawValue, "net.ranode.agent-work-todo")
        XCTAssertEqual(AppBundleID.wireguard.rawValue, "net.ranode.wireguard")
        XCTAssertEqual(AppBundleID.keepAwake.rawValue, "net.ranode.keep-awake")
        XCTAssertEqual(AppBundleID.screenshotSwift.rawValue, "net.ranode.screenshotswift")
        XCTAssertEqual(AppBundleID.agentRoomTerminal.rawValue, "net.ranode.agent-room-terminal")
        XCTAssertEqual(AppBundleID.agentBrowser.rawValue, "net.ranode.agentbrowser")
        XCTAssertEqual(AppBundleID.agentChat.rawValue, "net.ranode.agent-chat")
        XCTAssertEqual(AppBundleID.appRelaunchWatch.rawValue, "net.ranode.app-relaunch-watch")
    }

    func testAppIdentityBundleIDInterface() {
        XCTAssertEqual(AppIdentity.bundleID(for: .fleetDock), "net.ranode.fleet-dock")
        XCTAssertEqual(AppIdentity.bundleID(for: .agentWorkTodo), "net.ranode.agent-work-todo")
        XCTAssertEqual(AppIdentity.BundleID.fleetDock.rawValue, "net.ranode.fleet-dock")
    }

    func testBundleIDForSlug() {
        // Direct match
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "fleet-dock"), "net.ranode.fleet-dock")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "fleet-dock-swift"), "net.ranode.fleet-dock")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "agent-work-todo"), "net.ranode.agent-work-todo")

        // Overrides
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "vpn-wireguard-swift"), "net.ranode.wireguard")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "vpn-wireguard"), "net.ranode.wireguard")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "wireguard"), "net.ranode.wireguard")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "screenshotswift"), "net.ranode.screenshotswift")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "screenshot-swift"), "net.ranode.screenshotswift")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "gitlab-manager-swift"), "net.ranode.gitlab-status-ui")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "gitlab-project-viewer"), "net.ranode.gitlab-project-viewer")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "token-usage-menubar-swift"), "net.ranode.llm-token-status-manager")

        // Prefix already present
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "net.ranode.custom-app"), "net.ranode.custom-app")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "ai.gujo.custom-app"), "ai.gujo.custom-app")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "kr.internal.custom-app"), "kr.internal.custom-app")

        // Fallback
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "new-future-app-swift"), "net.ranode.new-future-app")
        XCTAssertEqual(AppIdentity.bundleID(forSlug: "new-future-app-ios"), "net.ranode.new-future-app")
    }

    func testExpressibleByStringLiteral() {
        let id: AppBundleID = "net.ranode.custom"
        XCTAssertEqual(id.rawValue, "net.ranode.custom")
        XCTAssertEqual(id.description, "net.ranode.custom")
    }
}
