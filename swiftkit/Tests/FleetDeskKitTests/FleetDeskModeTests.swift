import Foundation
import Testing
@testable import FleetDeskKit

@Suite struct FleetDeskModeTests {
    @Test func hidesFleetButKeepsHubAndChrome() {
        #expect(FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.dns-guard", hideEnabled: true))
        #expect(FleetDeskMode.shouldHideDockIcon(bundleId: "com.dalsoop.graph", hideEnabled: true))
        #expect(!FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.agent-apps-bar", hideEnabled: true))
        #expect(!FleetDeskMode.shouldHideDockIcon(bundleId: "com.google.Chrome", hideEnabled: true))
        #expect(!FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.dns-guard", hideEnabled: false))
    }

    @Test func forcesAccessoryOnlyForHiddenFleetRegularRequest() {
        #expect(
            FleetDeskMode.forcesAccessory(
                bundleId: "net.ranode.iptime-router",
                hideEnabled: true,
                preferredRegular: true
            )
        )
        #expect(
            !FleetDeskMode.forcesAccessory(
                bundleId: "net.ranode.agent-apps-bar",
                hideEnabled: true,
                preferredRegular: true
            )
        )
        #expect(
            !FleetDeskMode.forcesAccessory(
                bundleId: "net.ranode.iptime-router",
                hideEnabled: true,
                preferredRegular: false
            )
        )
        #expect(
            !FleetDeskMode.forcesAccessory(
                bundleId: "net.ranode.agent-chat",
                hideEnabled: true,
                dockBundleIds: FleetDeskMode.defaultDockBundleIds,
                preferredRegular: true
            )
        )
    }

    @Test func keepsAllowlistedFleetOnDock() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-desk-allow-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try FleetDeskMode.setEnabled(true, at: url)
        #expect(
            !FleetDeskMode.shouldHideDockIcon(
                bundleId: "net.ranode.agent-worker-orchestrator",
                at: url
            )
        )
        #expect(FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.dns-guard", at: url))
        try FleetDeskMode.setDockAllowed("net.ranode.dns-guard", allowed: true, at: url)
        #expect(!FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.dns-guard", at: url))
        try FleetDeskMode.setDockAllowed("net.ranode.dns-guard", allowed: false, at: url)
        #expect(FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.dns-guard", at: url))
        try FleetDeskMode.setEnabled(false, at: url)
        #expect(FleetDeskMode.isOnDockAllowlist("net.ranode.agent-chat", at: url))
        #expect(!FleetDeskMode.isOnDockAllowlist("net.ranode.dns-guard", at: url))
    }

    @Test func posixHomeIsNotContainerOnlyGuess() {
        let home = FleetDeskStore.posixHome()
        #expect(home.path.hasPrefix("/"))
        #expect(FleetDeskStore.flagURL(home: home).lastPathComponent == "fleet-desk.json")
    }

    @Test func flagRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-desk-\(UUID().uuidString).json")
        try FleetDeskMode.setEnabled(true, at: url)
        #expect(FleetDeskMode.isEnabled(at: url))
        #expect(FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.x", at: url))
        try FleetDeskMode.setEnabled(false, at: url)
        #expect(!FleetDeskMode.isEnabled(at: url))
        try? FileManager.default.removeItem(at: url)
    }

    @Test func identitySplitsHubFromFleet() {
        #expect(FleetDeskIdentity.isHub("net.ranode.agent-apps-bar"))
        #expect(FleetDeskIdentity.isHub("net.ranode.AgentAppsBar"))
        #expect(FleetDeskIdentity.isFleet("net.ranode.dns-guard"))
        #expect(FleetDeskIdentity.isFleet("com.dalsoop.graph"))
        #expect(!FleetDeskIdentity.isFleet("com.google.Chrome"))
        #expect(!FleetDeskIdentity.isHub("net.ranode.dns-guard"))
    }

    @Test func hideBuildReadsLSUIElementAndHookSymbol() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-hide-build-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let lsui = root.appendingPathComponent("Menu.app")
        try FileManager.default.createDirectory(
            at: lsui.appendingPathComponent("Contents"),
            withIntermediateDirectories: true
        )
        try PropertyListSerialization.data(
            fromPropertyList: ["LSUIElement": true],
            format: .xml,
            options: 0
        ).write(to: lsui.appendingPathComponent("Contents/Info.plist"))
        #expect(FleetDeskHideBuild.canHideDockIcon(bundlePath: lsui.path))

        let hooked = root.appendingPathComponent("Hook.app")
        let macOS = hooked.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("prefix \(FleetDeskHideBuild.ctorSymbol) suffix".utf8)
            .write(to: macOS.appendingPathComponent("Hook"))
        #expect(FleetDeskHideBuild.canHideDockIcon(bundlePath: hooked.path))

        let plain = root.appendingPathComponent("Plain.app")
        try FileManager.default.createDirectory(
            at: plain.appendingPathComponent("Contents/MacOS"),
            withIntermediateDirectories: true
        )
        try Data("regular app".utf8)
            .write(to: plain.appendingPathComponent("Contents/MacOS/Plain"))
        #expect(!FleetDeskHideBuild.canHideDockIcon(bundlePath: plain.path))
    }

    @Test func liveTallyUsesPolicyNotProbe() {
        let apps = [
            FleetDeskNamedApp(bundleId: "net.ranode.dns-guard", name: "Dns"),
            FleetDeskNamedApp(bundleId: "net.ranode.agent-chat", name: "Chat"),
            FleetDeskNamedApp(bundleId: "net.ranode.agent-apps-bar", name: "Bar"),
        ]
        let live = FleetDeskLiveReport.tally(
            apps: apps,
            hideEnabled: true,
            dockBundleIds: ["net.ranode.agent-chat"],
            liveHidden: { $0 == "net.ranode.dns-guard" }
        )
        #expect(live.hideTargets == 1)
        #expect(live.applied == 1)
        #expect(live.pending == 0)
        let pending = FleetDeskLiveReport.tally(
            apps: apps,
            hideEnabled: true,
            dockBundleIds: ["net.ranode.agent-chat"],
            liveHidden: { _ in false }
        )
        #expect(pending.pending == 1)
    }

    @Test func processDockActionNeverRaisesMenuBar() {
        #expect(
            FleetDeskPolicy.processDockAction(shouldHide: true, infoPlistUIElement: true)
                == .forceAccessory
        )
        #expect(
            FleetDeskPolicy.processDockAction(shouldHide: true, infoPlistUIElement: false)
                == .forceAccessory
        )
        #expect(
            FleetDeskPolicy.processDockAction(shouldHide: false, infoPlistUIElement: true)
                == .leave
        )
        #expect(
            FleetDeskPolicy.processDockAction(shouldHide: false, infoPlistUIElement: false)
                == .forceRegular
        )
    }

    @Test func lsuiElementParsesPlistValues() {
        #expect(FleetDeskPolicy.isTruthyLSUIElement(true))
        #expect(FleetDeskPolicy.isTruthyLSUIElement(NSNumber(value: 1)))
        #expect(FleetDeskPolicy.isTruthyLSUIElement("1"))
        #expect(FleetDeskPolicy.isTruthyLSUIElement("true"))
        #expect(!FleetDeskPolicy.isTruthyLSUIElement(false))
        #expect(!FleetDeskPolicy.isTruthyLSUIElement("0"))
        #expect(!FleetDeskPolicy.isTruthyLSUIElement(nil))
    }

    @Test func probeParsesLsappinfoTypeOnly() {
        #expect(FleetDeskLiveProbe.parseUIElement("bundleID=\"x\" type=\"UIElement\" flavor=3"))
        #expect(!FleetDeskLiveProbe.parseUIElement("bundleID=\"x\" type=\"Foreground\" flavor=3"))
        #expect(!FleetDeskLiveProbe.parseUIElement(""))
        #expect(FleetDeskLiveProbe.parsePresence("type=\"Foreground\"") == .onDock)
        #expect(FleetDeskLiveProbe.parsePresence("type=\"UIElement\"") == .hidden)
        #expect(FleetDeskLiveProbe.parsePresence("") == .unknown)
    }

    @Test func pendingCountsOnlyAppsActuallyOnDock() {
        let apps = [
            FleetDeskNamedApp(bundleId: "net.ranode.dns-guard", name: "Dns"),
            FleetDeskNamedApp(bundleId: "net.ranode.ghost", name: "Ghost"),
        ]
        let live = FleetDeskLiveReport.tally(
            apps: apps,
            hideEnabled: true,
            dockBundleIds: [],
            liveHidden: { _ in false },
            onDock: { $0 == "net.ranode.dns-guard" }
        )
        #expect(live.hideTargets == 2)
        #expect(live.pending == 1)
        #expect(live.applied == 0)
        #expect(live.rows.first { $0.bundleId == "net.ranode.ghost" }?.pending == false)
    }

    @Test func hideAllFleetLeavesOnlyHub() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fleet-desk-hideall-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try FleetDeskMode.setEnabled(true, at: url)
        try FleetDeskMode.setDockAllowed("net.ranode.dns-guard", allowed: true, at: url)
        try FleetDeskMode.hideAllFleet(at: url)
        #expect(FleetDeskMode.isEnabled(at: url))
        #expect(FleetDeskMode.flag(at: url).dockBundleIds == [])
        #expect(FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.dns-guard", at: url))
        #expect(!FleetDeskMode.shouldHideDockIcon(bundleId: "net.ranode.agent-apps-bar", at: url))
    }
}
