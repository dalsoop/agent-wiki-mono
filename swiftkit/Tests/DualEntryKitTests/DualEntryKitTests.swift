import XCTest
@testable import DualEntryKit


/// 위임 표식 — `DualEntryDelegate` 와 `DualEntryRules` 가 싸우지 않게.
///
/// 실측(2026-08-05): rightclick 은 `reload` 를 PATH 로도(설치본에 없음),
/// 앱 본체로도(가드가 차단) 실행할 수 없었다. 두 장치가 각자 옳게 동작한 결과다.
final class DualEntryDelegationMarkerTests: XCTestCase {
    private let profile = DualEntryProfile(
        mode: .helpers,
        guiExecutableName: "SampleApp",
        cliProductName: "sample",
        cliAliases: [],
        cliSubcommands: ["reload"],
        stampHomeRelativeDir: ".dual-entry-delegation-test",
        stampFileName: "cli-install-version",
        maxSafeCLIBytes: 5_000_000
    )
    private let guiPath = "/Applications/Sample.app/Contents/MacOS/SampleApp"

    func testAbsoluteGUIPathWithSubcommandIsBlockedByDefault() {
        XCTAssertTrue(DualEntryRules.isMisusedAsCLI(
            profile: profile, arguments: [guiPath, "reload"], environment: [:]
        ), "PATH 심링크로 아무나 부르는 것은 여전히 막아야 한다")
    }

    func testDelegationMarkerAllowsTheSameInvocation() {
        XCTAssertFalse(DualEntryRules.isMisusedAsCLI(
            profile: profile, arguments: [guiPath, "reload"],
            environment: [DualEntryRules.delegationMarkerKey: DualEntryRules.delegationMarkerValue]
        ), "자기 앱 CLI 가 명시적으로 넘긴 것은 오호출이 아니다")
    }

    /// 표식 값이 다르면 통과시키지 않는다 — 아무 값이나 세팅해 우회하지 못하게.
    func testWrongMarkerValueStillBlocks() {
        XCTAssertTrue(DualEntryRules.isMisusedAsCLI(
            profile: profile, arguments: [guiPath, "reload"],
            environment: [DualEntryRules.delegationMarkerKey: "yes"]
        ))
    }

    /// argv0 이 CLI 이름인 경우(= PATH 가 GUI 를 가리킴)는 표식이 있어도 위험하지만,
    /// 그 상황은 애초에 우리 delegate 가 만들지 않는다. 표식은 delegate 만 심는다.
    func testMarkerIsScopedToDelegateNotAmbient() {
        XCTAssertEqual(DualEntryRules.delegationMarkerKey, "SWIFT_APP_DUAL_ENTRY_DELEGATED")
    }
}
