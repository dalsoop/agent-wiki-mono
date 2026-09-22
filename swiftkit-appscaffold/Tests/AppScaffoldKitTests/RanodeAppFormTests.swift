import Foundation
import SwiftUI
import Testing
import XCTest
@testable import AppScaffoldKit

@MainActor
@Suite struct RanodeAppFormTests {
    private struct SampleWindowApp: FleetManagedApp {
        static let service = "net.ranode.sample-window-app"
        static let productName = "Sample Window App"
        var root: some View { Text("window-root") }
    }

    private struct SampleMenuBarApp: FleetManagedMenuBarApp {
        static let service = "net.ranode.sample-menubar-app"
        static let productName = "Sample MenuBar App"
        var menuContent: some View { Text("menu") }
        var menuLabel: some View { Image(systemName: "app") }
        var root: some View { Text("window") }
    }

    @Test func windowAppFormDefaultsSatisfyContract() {
        let (isValid, reasons) = RanodeAppFormContract.verifyFormDefaults(for: SampleWindowApp.self)
        #expect(isValid, "Reasons: \(reasons.joined(separator: ", "))")
        #expect(SampleWindowApp.windowID == "main")
        #expect(SampleWindowApp.windowTitle == "Sample Window App")
        #expect(SampleWindowApp.service == "net.ranode.sample-window-app")
    }

    @Test func menuBarAppFormDefaultsSatisfyContract() {
        let (isValid, reasons) = RanodeAppFormContract.verifyMenuBarFormDefaults(for: SampleMenuBarApp.self)
        #expect(isValid, "Reasons: \(reasons.joined(separator: ", "))")
        #expect(SampleMenuBarApp.windowID == "main")
        #expect(SampleMenuBarApp.windowTitle == "Sample MenuBar App")
        #expect(SampleMenuBarApp.service == "net.ranode.sample-menubar-app")
    }

    @Test func appPathsContractVerification() {
        let sqliteURL = URL(fileURLWithPath: "/Users/test/Library/Application Support/net.ranode.sample/app.sqlite")
        #expect(AppPathsContract.verifyDurableSqlitePath(sqliteFile: sqliteURL, expectedBundleID: "net.ranode.sample"))

        let pass = AppPathsContract.verifyStateRootOverride(
            stateDirectory: { env in
                let base = env["SWIFT_APP_STATE_ROOT"] ?? "/tmp"
                return URL(fileURLWithPath: base).appendingPathComponent("state", isDirectory: true)
            },
            expectedDirName: "state",
            stateFile: { name, env in
                let base = env["SWIFT_APP_STATE_ROOT"] ?? "/tmp"
                return URL(fileURLWithPath: base).appendingPathComponent("state/\(name)")
            }
        )
        #expect(pass)
    }

    @Test func stateMirrorContractVerification() {
        #expect(StateMirrorContract.verifyStateMirrorPath(slug: "sample-window-app"))
        let url = StateMirrorContract.stateMirrorURL(for: "sample-window-app")
        #expect(url.lastPathComponent == "sample-window-app.json")
    }

    @Test func assertConformsOverloads() {
        let windowPass = RanodeAppFormContract.assertConforms(
            appType: SampleWindowApp.self,
            slug: "sample-window-app"
        )
        #expect(windowPass)

        let menuBarPass = RanodeAppFormContract.assertConforms(
            menuBarAppType: SampleMenuBarApp.self,
            slug: "sample-menubar-app"
        )
        #expect(menuBarPass)
    }
}

final class RanodeAppFormHarnessTests: XCTestCase, RanodeAppContractTestCase {
    private struct SampleWindowApp: FleetManagedApp {
        static let service = "net.ranode.sample-window-app"
        static let productName = "Sample Window App"
        var root: some View { Text("window-root") }
    }

    private struct SampleMenuBarApp: FleetManagedMenuBarApp {
        static let service = "net.ranode.sample-menubar-app"
        static let productName = "Sample MenuBar App"
        var menuContent: some View { Text("menu") }
        var menuLabel: some View { Image(systemName: "app") }
        var root: some View { Text("window") }
    }

    @MainActor
    func testAppContractOneLiner() {
        assertRanodeAppContract(
            for: SampleWindowApp.self,
            slug: "sample-window-app",
            sqliteFile: URL(fileURLWithPath: "/Users/test/Library/Application Support/net.ranode.sample-window-app/app.sqlite"),
            stateDirectory: { env in
                let base = env["SWIFT_APP_STATE_ROOT"] ?? "/tmp"
                return URL(fileURLWithPath: base).appendingPathComponent("state", isDirectory: true)
            },
            expectedDirName: "state",
            stateFile: { name, env in
                let base = env["SWIFT_APP_STATE_ROOT"] ?? "/tmp"
                return URL(fileURLWithPath: base).appendingPathComponent("state/\(name)")
            }
        )
    }

    @MainActor
    func testMenuBarAppContractOneLiner() {
        assertRanodeMenuBarAppContract(
            for: SampleMenuBarApp.self,
            slug: "sample-menubar-app"
        )
    }

    func testStandardContractOneLiner() {
        assertRanodeContract(
            windowID: "main",
            productName: "Sample Window App",
            windowTitle: "Sample Window App",
            service: "net.ranode.sample-window-app",
            slug: "sample-window-app"
        )
    }
}
