import Foundation
import Testing

@testable import AppScaffoldKit

/// 채택 판정의 계약.
///
/// trait 뒤에 두지 않는다 — 이 스캐너는 자기가 managed 인지와 무관하게 돌아야 한다.
/// (실측 2026-08-05: `GujoManagedTests` 는 `#if GujoManaged` 안에 있어서 기본
/// `swift test` 에서 **조용히 안 돌고 있었다**. 같은 함정을 반복하지 않는다.)
@Suite struct GujoManagedAdoptionTests {

    // MARK: - trait 판정

    @Test func traitIsReadFromTheTraitsArrayNotFromProseThatMentionsIt() {
        let mentionsOnly = """
        // GujoManaged 를 쓸지 고민 중이다. traits 는 아직 안 켰다.
        let package = Package(name: "demo")
        """
        #expect(GujoManagedAdoption.declaresTrait(mentionsOnly) == false)

        let enabled = """
        .package(path: "../swiftkit-appscaffold", traits: ["GujoManaged", "SelfUpdating"])
        """
        #expect(GujoManagedAdoption.declaresTrait(enabled))
    }

    /// 의존이 여럿이면 `traits:` 도 여럿이다 — 첫 배열에 없다고 멈추면 안 된다.
    @Test func traitIsFoundInAnyOfSeveralTraitArrays() {
        let package = """
        .package(path: "../other", traits: ["SelfUpdating"]),
        .package(path: "../swiftkit-appscaffold", traits: ["GujoManaged"]),
        """
        #expect(GujoManagedAdoption.declaresTrait(package))
    }

    // MARK: - 주석·문자열은 호출이 아니다

    /// **이 스캐너의 첫 오탐이 이 규칙을 만들었다.** 콘솔 앱이 안내 문구에
    /// `.gujoManaged()` 를 적었다는 이유로 자기를 managed 로 셌다.
    @Test func aCallInsideAStringLiteralIsNotACall() {
        let source = #"""
        Text("루트 뷰 뒤에 .gujoManaged() 한 줄만 붙이면 된다")
        """#
        #expect(GujoManagedAdoption.mentions(".gujoManaged()", in: source) == false)
    }

    @Test func aCallInsideACommentIsNotACall() {
        #expect(GujoManagedAdoption.mentions(
            ".gujoManaged()", in: "// TODO: .gujoManaged() 붙이기") == false)
    }

    @Test func arealCallIsStillFound() {
        #expect(GujoManagedAdoption.mentions(".gujoManaged()", in: "ContentView().gujoManaged()"))
    }

    /// 같은 줄에 문자열과 코드가 같이 있으면 **코드 쪽만** 본다.
    @Test func codeBesideAStringOnTheSameLineStillCounts() {
        let line = #"ContentView().gujoManaged()  // "gujoManaged" 설명"#
        #expect(GujoManagedAdoption.mentions(".gujoManaged()", in: line))
    }

    /// 문자열 안의 `//` 는 주석 시작이 아니다 — URL 이 흔하다.
    @Test func aSlashInsideAStringDoesNotStartAComment() {
        let line = #"let url = "https://x" ; view.gujoManaged()"#
        #expect(GujoManagedAdoption.mentions(".gujoManaged()", in: line))
    }

    // MARK: - 상태

    @Test func callingTheGateIsWhatMakesAnAppManaged() {
        #expect(record(trait: true, calls: true).state == .managed)
    }

    /// **오늘의 발견 87개.** 배선은 끌어오고 관리는 안 받는다. 컴파일이 안 깨져서
    /// 아무도 몰랐다 — 그래서 이 상태에 이름을 준다.
    @Test func enablingTheTraitWithoutCallingTheGateIsItsOwnState() {
        #expect(record(trait: true, calls: false).state == .traitOnly)
    }

    @Test func neitherIsSimplyNotAdopted() {
        #expect(record(trait: false, calls: false).state == .notAdopted)
    }

    // MARK: - 스캐폴드 채택도 채택이다

    /// `RanodeApp` 을 쓰면 `RanodeAppShell` 이 게이트를 대신 건다. 이걸 미채택으로
    /// 세면 "앱마다 한 줄을 붙여라" 라고 거꾸로 재촉하게 된다 — 통일화의 반대다.
    @Test func conformingToTheScaffoldCountsAsAdoption() {
        #expect(GujoManagedAdoption.conformsToScaffold(
            "struct DemoApp: RanodeApp {"))
        #expect(GujoManagedAdoption.conformsToScaffold(
            "struct DemoApp: RanodeMenuBarApp {"))
        #expect(GujoManagedAdoption.conformsToScaffold(
            "struct DemoApp: RanodeWindowGroupApp {"))
        #expect(GujoManagedAdoption.conformsToScaffold(
            "struct DemoApp: RanodeMenuBarWindowGroupApp {"))
    }

    /// AppKit `@main` 진입은 `.gujoManaged()` 대신 status/handOff 를 쓴다.
    @Test func appKitStatusAndHandOffCountAsGateCalls() throws {
        let fixture = try Fixture(
            packageTraits: true, gateCall: false, cli: nil, cliAsksLedger: false,
            appKitGate: true)
        defer { fixture.remove() }
        let r = try #require(GujoManagedAdoption.record(appDirectory: fixture.appDir))
        #expect(r.state == .managed)
    }

    /// `*CommandLine` · `{cli}-cli` 폴더도 dual-entry CLI 로 센다.
    @Test func commandLineAndKebabCliFoldersCountAsCLISources() {
        let cmd = URL(fileURLWithPath: "/apps/demo/Sources/DemoCommandLine/main.swift")
        #expect(GujoManagedAdoption.isCLISource(cmd, cliName: "demo"))
        let kebab = URL(fileURLWithPath: "/apps/demo/Sources/demo-cli/main.swift")
        #expect(GujoManagedAdoption.isCLISource(kebab, cliName: "demo"))
        let absolute = URL(fileURLWithPath: "/apps/vpn/Sources/WireGuardCLI/CLI.swift")
        #expect(GujoManagedAdoption.isCLISource(
            absolute, cliName: "/opt/homebrew/bin/vpn-wireguardctl"))
    }

    @Test func iOSFleetDirectoryNamesAreDetected() {
        #expect(GujoManagedAdoption.isIOSFleetApp(directory: "excalidraw-ios"))
        #expect(GujoManagedAdoption.isIOSFleetApp(directory: "clipboard-ios-capture-poc"))
        #expect(GujoManagedAdoption.isIOSFleetApp(directory: "pim-calendar-ios"))
        #expect(GujoManagedAdoption.isIOSFleetApp(directory: "env-vault-swift") == false)
    }

    /// iOS 앱은 GUI 게이트 금지 · CLI 원장 조회만으로 managed(정책 2026-08-05).
    @Test func iOSAppWithCLIGateOnlyCountsAsManaged() throws {
        let fixture = try Fixture(
            packageTraits: true, gateCall: false, cli: "demo-ios", cliAsksLedger: true,
            directoryName: "demo-ios")
        defer { fixture.remove() }
        let r = try #require(GujoManagedAdoption.record(appDirectory: fixture.appDir))
        #expect(r.cliConsultsLedger)
        #expect(r.state == .managed)
    }

    /// macOS 앱은 CLI 만 있어도 GUI 게이트 없으면 trait-only 유지.
    @Test func macOSAppWithCLIGateOnlyStaysTraitOnly() throws {
        let fixture = try Fixture(
            packageTraits: true, gateCall: false, cli: "demo", cliAsksLedger: true,
            directoryName: "demo-swift")
        defer { fixture.remove() }
        let r = try #require(GujoManagedAdoption.record(appDirectory: fixture.appDir))
        #expect(r.cliConsultsLedger)
        #expect(r.state == .traitOnly)
    }

    /// 접두 일치로 오탐하면 안 된다 — `RanodeAppBootstrap` 은 프로토콜이 아니다.
    @Test func aTypeThatMerelyStartsWithTheProtocolNameIsNotConformance() {
        #expect(GujoManagedAdoption.conformsToScaffold(
            "struct DemoApp: App { RanodeAppBootstrap.runOnce() }") == false)
    }

    @Test func aPlainSwiftUIAppIsNotAdoptedByItself() {
        #expect(GujoManagedAdoption.conformsToScaffold("struct DemoApp: App {") == false)
    }

    // MARK: - CLI 구멍

    /// `gujoManaged()` 는 `View` extension 이라 **창만** 막는다. dual-entry 앱은
    /// CLI 라는 두 번째 진입점이 있고 그쪽은 원장에 안 묻는다 — 구조적 의존의 구멍.
    @Test func aManagedAppWithADualEntryCLIThatNeverAsksIsFlagged() {
        let r = GujoManagedAdoption.AppRecord(
            directory: "demo-swift", traitEnabled: true, callsGate: true,
            cliName: "demo", cliConsultsLedger: false)
        #expect(r.hasUngatedCLI)
    }

    @Test func aCLIThatAsksTheLedgerIsNotAHole() {
        let r = GujoManagedAdoption.AppRecord(
            directory: "demo-swift", traitEnabled: true, callsGate: true,
            cliName: "demo", cliConsultsLedger: true)
        #expect(r.hasUngatedCLI == false)
    }

    /// GUI 조차 안 막는 앱을 "CLI 구멍" 으로 세면 숫자가 부풀어 우선순위를 흐린다.
    @Test func anUnmanagedAppIsNotCountedAsACLIHole() {
        let r = GujoManagedAdoption.AppRecord(
            directory: "demo-swift", traitEnabled: false, callsGate: false,
            cliName: "demo", cliConsultsLedger: false)
        #expect(r.hasUngatedCLI == false)
    }

    // MARK: - 디스크에서 읽기

    @Test func readsTraitCallAndCLIFromARealAppDirectory() throws {
        let fixture = try Fixture(
            packageTraits: true, gateCall: true, cli: "demo", cliAsksLedger: false)
        defer { fixture.remove() }

        let r = try #require(GujoManagedAdoption.record(appDirectory: fixture.appDir))
        #expect(r.state == .managed)
        #expect(r.cliName == "demo")
        #expect(r.hasUngatedCLI)
    }

    /// `Package.swift` 가 없으면 앱이 아니다 — `apps/` 밑엔 앱 아닌 디렉터리도 있다.
    @Test func aDirectoryWithoutAManifestIsNotAnApp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("adoption-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(GujoManagedAdoption.record(appDirectory: root) == nil)
    }

    @Test func summaryCountsEachStateAndTheCLIHolesSeparately() {
        let records = [
            record(trait: true, calls: true),
            record(trait: true, calls: false),
            record(trait: false, calls: false),
            GujoManagedAdoption.AppRecord(
                directory: "d", traitEnabled: true, callsGate: true,
                cliName: "d", cliConsultsLedger: false),
        ]
        let s = GujoManagedAdoption.summarize(records)
        #expect(s.total == 4)
        #expect(s.managed == 2)
        #expect(s.traitOnly == 1)
        #expect(s.notAdopted == 1)
        #expect(s.ungatedCLI == 1)
    }


    // MARK: - 옛 LicenseKit 경로

    @Test func packageProductLicenseKitIsDetected() {
        let package = #".product(name: "LicenseKit", package: "swiftkit")"#
        #expect(GujoManagedAdoption.declaresLicenseKitDependency(package))
        #expect(GujoManagedAdoption.declaresLicenseKitDependency(
            "// .product(name: \"LicenseKit\")") == false)
    }

    @Test func importLicenseKitInCodeCountsAsLegacyAPI() {
        #expect(GujoManagedAdoption.sourceUsesLegacyLicenseAPI(in: "import LicenseKit"))
        #expect(!GujoManagedAdoption.sourceUsesLegacyLicenseAPI(
            in: "//" + " import LicenseKit"))
    }

    @Test func gujoManagedWithLicenseKitDepIsLegacyPath() {
        let r = GujoManagedAdoption.AppRecord(
            directory: "demo", traitEnabled: true, callsGate: true,
            cliName: nil, cliConsultsLedger: false,
            dependsOnLicenseKit: true, usesLegacyLicenseAPI: false)
        #expect(r.hasLegacyLicensePath)
    }

    @Test func usesLegacyAPIAloneIsLegacyPathEvenWithoutTrait() {
        let r = GujoManagedAdoption.AppRecord(
            directory: "demo", traitEnabled: false, callsGate: false,
            cliName: nil, cliConsultsLedger: false,
            dependsOnLicenseKit: false, usesLegacyLicenseAPI: true)
        #expect(r.hasLegacyLicensePath)
    }

    @Test func readsLegacyLicenseFactsFromDisk() throws {
        let fixture = try Fixture(
            packageTraits: true, gateCall: true, cli: nil, cliAsksLedger: false,
            licenseKitDep: true, legacyLicenseAPI: true)
        defer { fixture.remove() }
        let r = try #require(GujoManagedAdoption.record(appDirectory: fixture.appDir))
        #expect(r.dependsOnLicenseKit)
        #expect(r.usesLegacyLicenseAPI)
        #expect(r.hasLegacyLicensePath)
    }

    @Test func summaryCountsLegacyLicensePath() {
        let records = [
            GujoManagedAdoption.AppRecord(
                directory: "a", traitEnabled: true, callsGate: true,
                cliName: nil, cliConsultsLedger: false,
                dependsOnLicenseKit: true, usesLegacyLicenseAPI: false),
            record(trait: true, calls: true),
        ]
        let s = GujoManagedAdoption.summarize(records)
        #expect(s.legacyLicensePath == 1)
    }

    // MARK: -

    private func record(trait: Bool, calls: Bool) -> GujoManagedAdoption.AppRecord {
        GujoManagedAdoption.AppRecord(
            directory: "demo-swift", traitEnabled: trait, callsGate: calls,
            cliName: nil, cliConsultsLedger: false)
    }

    private struct Fixture {
        let root: URL
        let directoryName: String
        var appDir: URL { root.appendingPathComponent(directoryName) }

        init(
            packageTraits: Bool, gateCall: Bool, cli: String?, cliAsksLedger: Bool,
            licenseKitDep: Bool = false, legacyLicenseAPI: Bool = false,
            appKitGate: Bool = false,
            directoryName: String = "demo-swift"
        ) throws {
            let fm = FileManager.default
            self.directoryName = directoryName
            root = fm.temporaryDirectory.appendingPathComponent("adoption-\(UUID().uuidString)")
            let gui = appDir.appendingPathComponent("Sources/Demo")
            let cliDir = appDir.appendingPathComponent("Sources/DemoCLI")
            try fm.createDirectory(at: gui, withIntermediateDirectories: true)
            try fm.createDirectory(at: cliDir, withIntermediateDirectories: true)

            let traits = packageTraits ? #", traits: ["GujoManaged"]"# : ""
            var package = """
            .package(path: "../swiftkit-appscaffold"\(traits))
            .executable(name: "demo", targets: ["DemoCLI"])
            .executableTarget(name: "DemoCLI")
            """
            if licenseKitDep {
                package += "\n.product(name: \"LicenseKit\", package: \"swiftkit\")"
            }
            try package.write(
                to: appDir.appendingPathComponent("Package.swift"),
                atomically: true, encoding: .utf8)
            var guiSource = gateCall ? "ContentView().gujoManaged()" : "struct DemoApp: App { ContentView() }"
            if appKitGate {
                guiSource = """
                let status = await GujoManaged.status()
                if !status.isAvailable { GujoManaged.handOff(status: status) }
                """
            }
            if legacyLicenseAPI {
                guiSource = "import LicenseKit\n" + guiSource + "\n_ = LicenseManager()"
            }
            try guiSource.write(
                to: gui.appendingPathComponent("App.swift"),
                atomically: true, encoding: .utf8)
            // CLI 정본 게이트는 exitIfNotEntitled* — status 는 GUI/AppKit 패턴.
            try (cliAsksLedger ? "GujoManaged.exitIfNotEntitledSync()" : "run()")
                .write(to: cliDir.appendingPathComponent("main.swift"),
                       atomically: true, encoding: .utf8)
            if let cli {
                try #"{"cli": "\#(cli)"}"#
                    .write(to: appDir.appendingPathComponent("interop.json"),
                           atomically: true, encoding: .utf8)
            }
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func spriteAnimateFolderMatchesSpriteAnimatorCLI() {
        let url = URL(fileURLWithPath: "/apps/sprite-animator-swift/Sources/spriteanimate/main.swift")
        #expect(GujoManagedAdoption.isCLISource(url, cliName: "sprite-animator"))
    }

    @Test func packageIdentityGUIProductStemIsCLI() throws {
        // GUI=`AgentE2ERunnerApp` → Sources/AgentE2ERunner 는 CLI 제품
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gujo-cli-id-\(UUID().uuidString)", isDirectory: true)
        let packaging = dir.appendingPathComponent("Packaging", isDirectory: true)
        let sources = dir.appendingPathComponent("Sources/AgentE2ERunner", isDirectory: true)
        try FileManager.default.createDirectory(at: packaging, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let identity = """
        {"gui_product":"AgentE2ERunnerApp","cli_product":"agent-e2e-runner","cli":"agent-e2e-runner"}
        """
        try identity.write(to: packaging.appendingPathComponent("package-identity.json"), atomically: true, encoding: .utf8)
        let main = sources.appendingPathComponent("main.swift")
        try "GujoManaged.exitIfNotEntitledSync()\n".write(to: main, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(GujoManagedAdoption.isCLISource(main, cliName: "agent-e2e-runner"))
    }

    /// GUI 창이 없는 패키지는 CLI 원장 조회만으로 managed.
    @Test func cliOnlyPackageWithLedgerGateIsManaged() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("adoption-clionly-\(UUID().uuidString)")
        let appDir = root.appendingPathComponent("pipeline-swift")
        let cliDir = appDir.appendingPathComponent("Sources/PipelineCLI")
        try fm.createDirectory(at: cliDir, withIntermediateDirectories: true)
        try """
        .package(path: "../swiftkit-appscaffold", traits: ["GujoManaged"])
        .executable(name: "pipeline", targets: ["PipelineCLI"])
        .executableTarget(name: "PipelineCLI")
        """.write(to: appDir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "GujoManaged.exitIfNotEntitledSync()\n"
            .write(to: cliDir.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try #"{"cli": "pipeline"}"#
            .write(to: appDir.appendingPathComponent("interop.json"), atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: root) }
        let r = try #require(GujoManagedAdoption.record(appDirectory: appDir))
        #expect(r.state == .managed)
        #expect(r.cliConsultsLedger)
    }

    @Test func libraryOnlyPackageIsNotAFleetApp() {
        #expect(GujoManagedAdoption.declaresExecutable(
            ".library(name: \"Core\", targets: [\"Core\"])") == false)
        #expect(GujoManagedAdoption.declaresExecutable(
            ".executable(name: \"demo\", targets: [\"DemoCLI\"])"))
    }

    @Test func licenseKitKeepersAreNotLegacyResidue() {
        #expect(GujoManagedAdoption.isLicenseKitKeeper(directory: "license-key-wallet-swift"))
        #expect(GujoManagedAdoption.isLicenseKitKeeper(directory: "swift-app-store-swift"))
        #expect(GujoManagedAdoption.isLicenseKitKeeper(directory: "gujo-account-manager-swift"))
        #expect(GujoManagedAdoption.isLicenseKitKeeper(directory: "gujo-skill-store-swift"))
        let r = GujoManagedAdoption.AppRecord(
            directory: "license-key-wallet-swift", traitEnabled: true, callsGate: true,
            cliName: "license-key-wallet", cliConsultsLedger: true,
            dependsOnLicenseKit: true, usesLegacyLicenseAPI: true)
        #expect(r.hasLegacyLicensePath == false)
    }
}
