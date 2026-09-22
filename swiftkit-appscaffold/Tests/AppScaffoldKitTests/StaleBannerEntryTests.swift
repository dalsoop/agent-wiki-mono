import XCTest
import InstallHealthKit
@testable import AppScaffoldKit

/// CLI 진입 한 줄(`GujoManaged.exitIfNotEntitledSync`)이 낡음 배너를 낸다.
///
/// 배너를 DualEntryKit 에 두면 **GUI 앱 파일**만 부른다(실측: CLI 타깃은 그걸 안 부르고
/// `GujoManaged.exitIfNotEntitledSync()` 를 첫 줄로 쓴다 — 327앱). 그래서 함대 CLI 가
/// 한 대도 배너를 못 냈다. 진입점을 잘못 고르면 기능이 있어도 없는 것과 같다.
final class StaleBannerEntryTests: XCTestCase {
    private var indexURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("banner-entry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        indexURL = dir.appendingPathComponent("stale-index.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: indexURL.deletingLastPathComponent())
    }

    func testHelpPathStillWarns() {
        // `--help` 는 게이트를 곧장 통과하는 경로다. 그래도 낡음은 알려야 한다 —
        // 사람이 가장 먼저 치는 명령이 help 다.
        StaleInstallIndex.write([(cli: "demo-cli", reason: "소스가 더 바뀜")], at: indexURL)
        var out = ""
        StaleInstallIndex.warnIfStale(
            arguments: ["/opt/homebrew/bin/demo-cli", "--help"],
            environment: [:], at: indexURL, emit: { out += $0 })
        XCTAssertTrue(out.contains("demo-cli"))
    }

    func testFreshCLIStaysSilentOnEveryCommand() {
        StaleInstallIndex.write([(cli: "other", reason: "소스가 더 바뀜")], at: indexURL)
        for command in ["--help", "version", "capabilities", "run"] {
            var out = ""
            StaleInstallIndex.warnIfStale(
                arguments: ["/opt/homebrew/bin/demo-cli", command],
                environment: [:], at: indexURL, emit: { out += $0 })
            XCTAssertTrue(out.isEmpty, "\(command) 에서 최신 CLI 가 떠들면 배너가 소음이 된다")
        }
    }

    func testEnforcedFailClosedBlocksStaleCLI() {
        StaleInstallIndex.write([(cli: "demo-cli", reason: "소스가 더 바뀜")], at: indexURL)
        var out = ""
        var exitCode: Int32? = nil
        StaleInstallIndex.warnIfStale(
            arguments: ["demo-cli", "--help"],
            environment: [StaleInstallIndex.enforceEnvironmentKey: "1"],
            at: indexURL,
            emit: { out += $0 },
            exitHandler: { exitCode = $0 }
        )
        XCTAssertEqual(exitCode, 70, "Fail-Closed 활성화 시 EX_SOFTWARE(70)으로 프로세스를 중단해야 한다")
        XCTAssertTrue(out.contains("실행을 차단합니다 (Fail-Closed)"), out)
    }
}
