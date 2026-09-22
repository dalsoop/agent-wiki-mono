import DoctorContract
import Foundation
import XCTest
@testable import AgentCLIKit

/// 앱이 자기를 진단하는 공용 provider 세트.
///
/// **왜 provider 인가**: 검사를 `doctor` 함수 안에 if 로 쌓으면 그 함수가 쓰레기통이
/// 되고, 룰마다 출력 모양이 갈린다(2026-08-11 실측: 하루에 검사 여섯 갈래가 생겼고
/// 전부 다른 스키마였다). 꽂는 자리를 두고 finding 하나로 모은다.
final class AppSelfDoctorTests: XCTestCase {

    // MARK: - PATH 진입점

    func testMissingBinaryIsAFailWithARemedy() async {
        let findings = await PathBinaryProvider(cliName: "nope", isExecutable: { _ in false }).run()
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(findings.first?.severity, .fail)
        // 처방 없는 판정은 사람이 또 찾게 만든다.
        XCTAssertEqual(findings.first?.remedy?.isEmpty, false)
    }

    func testPresentBinaryProducesNoFinding() async {
        let findings = await PathBinaryProvider(cliName: "x", isExecutable: { _ in true }).run()
        XCTAssertTrue(findings.isEmpty)
    }

    // MARK: - 리소스 자리

    private func resourceProvider(
        entry: [String], real: [String]
    ) -> ResourceBundleProvider {
        ResourceBundleProvider(
            cliName: "x",
            mainBundleURL: URL(fileURLWithPath: "/bin"),
            resourceURL: nil,
            executableURL: URL(fileURLWithPath: "/helpers/x"),
            names: { path in path.hasPrefix("/bin") ? entry : real }
        )
    }

    /// 리소스를 안 쓰는 앱은 볼 것이 없다 — 대부분이 여기다.
    func testAppWithoutResourceBundlesIsClean() async {
        let findings = await resourceProvider(entry: [], real: ["x"]).run()
        XCTAssertTrue(findings.isEmpty)
    }

    /// **실경로 옆에만 있으면 이 자리로 부를 때 죽는다.** product-evaluation-studio 가 이것이었다.
    func testBundleOnlyNextToRealPathIsAFail() async {
        let findings = await resourceProvider(entry: [], real: ["App_Core.bundle"]).run()
        XCTAssertEqual(findings.first?.severity, .fail)
        XCTAssertEqual(findings.first?.source, "resource-bundle")
        XCTAssertTrue(findings.first?.detail.contains("App_Core.bundle") == true)
    }

    /// 양쪽에 다 있으면 해석된다 — 심링크여도 문제 없다.
    func testBundleReachableFromEntryIsClean() async {
        let findings = await resourceProvider(
            entry: ["App_Core.bundle"], real: ["App_Core.bundle"]
        ).run()
        XCTAssertTrue(findings.isEmpty)
    }

    // MARK: - 상태 미러

    /// 미러가 없다고 앱이 고장난 건 아니다 — **경고지 실패가 아니다.**
    /// 실패로 세면 미러를 안 쓰는 앱이 전부 빨강이 되고 아무도 안 본다.
    func testMissingStateMirrorIsWarnNotFail() async {
        let findings = await StateMirrorProvider(
            appKey: "x", directory: "/nope", exists: { _ in false }
        ).run()
        XCTAssertEqual(findings.first?.severity, .warn)
    }

    // MARK: - 조립

    /// 저자 없이 도는 기본 세트가 실제로 넷인가 — 하나가 빠지면 조용히 안 돈다.
    func testStandardProvidersCoverPathResourcesMirrorAndMarketingVersion() {
        let ids = AppSelfDoctor.standardProviders(cliName: "x", appKey: "x").map(\.id)
        XCTAssertEqual(
            Set(ids),
            ["path-binary", "resource-bundle", "state-mirror", "cli-marketing-version"]
        )
    }

    // MARK: - 마케팅 version 줄

    func testHelpersCliStampIsAFail() async {
        let findings = await CLIMarketingVersionProvider(
            cliName: "demo",
            isExecutable: { _ in true },
            marketingVersion: { _ in "1.4.15" },
            runVersion: { _ in "demo helpers-cli 1" }
        ).run()
        XCTAssertEqual(findings.first?.severity, .fail)
        XCTAssertEqual(findings.first?.source, "cli-marketing-version")
        XCTAssertTrue(findings.first?.title.contains("helpers-cli") == true)
    }

    func testVersionLineMatchingMarketingIsClean() async {
        let findings = await CLIMarketingVersionProvider(
            cliName: "demo",
            isExecutable: { _ in true },
            marketingVersion: { _ in "1.4.15" },
            runVersion: { _ in "demo 1.4.15" }
        ).run()
        XCTAssertTrue(findings.isEmpty)
    }

    func testVersionLineMissingMarketingIsAFail() async {
        let findings = await CLIMarketingVersionProvider(
            cliName: "demo",
            isExecutable: { _ in true },
            marketingVersion: { _ in "1.4.15" },
            runVersion: { _ in "demo 1" }
        ).run()
        XCTAssertEqual(findings.first?.severity, .fail)
        XCTAssertTrue(findings.first?.detail.contains("1.4.15") == true)
    }

    func testSkipsWhenBinaryMissing() async {
        let findings = await CLIMarketingVersionProvider(
            cliName: "demo",
            isExecutable: { _ in false },
            marketingVersion: { _ in "1.4.15" },
            runVersion: { _ in XCTFail("must not spawn"); return nil }
        ).run()
        XCTAssertTrue(findings.isEmpty)
    }

    func testFlagVersionMismatchIsAFail() async {
        let findings = await CLIMarketingVersionProvider(
            cliName: "demo",
            isExecutable: { _ in true },
            marketingVersion: { _ in "1.4.15" },
            runCommand: { _, args in
                args == ["version"] ? "demo 1.4.15"
                    : args == ["--version"] ? "demo 1"
                    : #"{"ok":true,"result":{"version":"1.4.15"}}"#
            }
        ).run()
        XCTAssertTrue(findings.contains { $0.title.contains("--version") })
    }

    func testUnsupportedFlagVersionIsSkipped() async {
        let findings = await CLIMarketingVersionProvider(
            cliName: "demo",
            isExecutable: { _ in true },
            marketingVersion: { _ in "1.4.15" },
            runCommand: { _, args in
                args == ["version"] ? "demo 1.4.15"
                    : args == ["--version"] ? "알 수 없는 옵션: --version"
                    : #"{"ok":true,"result":{"version":"1.4.15"}}"#
            }
        ).run()
        XCTAssertTrue(findings.isEmpty)
    }

    func testCapabilitiesVersionMismatchIsAFail() async {
        let findings = await CLIMarketingVersionProvider(
            cliName: "demo",
            isExecutable: { _ in true },
            marketingVersion: { _ in "1.4.15" },
            runCommand: { _, args in
                args == ["version"] || args == ["--version"] ? "demo 1.4.15"
                    : #"{"ok":true,"result":{"version":"helpers-cli 1"}}"#
            }
        ).run()
        XCTAssertTrue(findings.contains { $0.title.contains("capabilities") })
    }

    func testCapabilitiesMarketingVersionIsClean() async {
        let findings = await CLIMarketingVersionProvider(
            cliName: "demo",
            isExecutable: { _ in true },
            marketingVersion: { _ in "1.4.15" },
            runCommand: { _, args in
                args == ["version"] || args == ["--version"] ? "demo 1.4.15"
                    : #"{"ok":true,"result":{"version":"1.4.15"}}"#
            }
        ).run()
        XCTAssertTrue(findings.isEmpty)
    }

    /// 앱 고유 검사는 뒤에 덧붙는다 — 공용 세트를 건드리지 않고.
    func testExtraProvidersAreAppended() async {
        struct Stub: DoctorProvider {
            let id = "stub"
            func run() async -> [DoctorFinding] {
                [DoctorFinding(
                    category: .runtime,
                    severity: .fail,
                    body: .init(
                        subject: "s",
                        title: "t",
                        detail: "d"
                    ),
                    source: "stub"
                )]
            }
        }
        let report = await AppSelfDoctor.scan(cliName: "x", appKey: "x", extra: [Stub()])
        XCTAssertTrue(report.findings.contains { $0.source == "stub" })
    }
}
