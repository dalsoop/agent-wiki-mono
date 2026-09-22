import XCTest
import InstallHealthKit
@testable import DualEntryKit

/// 낡은 설치본이 **스스로 말하게** 하는 배너.
///
/// 이 저장소의 검사·연동은 설치본을 부른다. 낡으면 옛 코드의 답이 조용히 사실로
/// 굳는다 — 실측 2026-08-10: 낡은 감사기가 이미 고쳐진 결함 16건을 계속 보고했다.
final class StaleInstallBannerTests: XCTestCase {
    private var indexURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stale-index-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        indexURL = dir.appendingPathComponent("stale-index.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: indexURL.deletingLastPathComponent())
    }

    func testWarnsWhenThisCLIIsListedStale() {
        StaleInstallIndex.write([(cli: "agent-browser", reason: "소스가 더 바뀜")], at: indexURL)
        var out = ""
        StaleInstallIndex.warnIfStale(
            arguments: ["/opt/homebrew/bin/agent-browser", "list"],
            environment: [:], at: indexURL, emit: { out += $0 })
        XCTAssertTrue(out.contains("agent-browser"))
        XCTAssertTrue(out.contains("소스가 더 바뀜"), "왜 낡았는지가 배너의 값이다")
        XCTAssertTrue(out.contains("ship"), "다음 행동을 알려줘야 한다")
    }

    func testSilentForFreshCLI() {
        StaleInstallIndex.write([(cli: "other-cli", reason: "소스가 더 바뀜")], at: indexURL)
        var out = ""
        StaleInstallIndex.warnIfStale(
            arguments: ["/opt/homebrew/bin/agent-browser"],
            environment: [:], at: indexURL, emit: { out += $0 })
        XCTAssertTrue(out.isEmpty, "최신 CLI 가 매번 떠들면 배너가 소음이 되어 무시된다")
    }

    func testSilentWhenIndexMissing() {
        var out = ""
        StaleInstallIndex.warnIfStale(
            arguments: ["/opt/homebrew/bin/agent-browser"],
            environment: [:],
            at: indexURL.deletingLastPathComponent().appendingPathComponent("nope.json"),
            emit: { out += $0 })
        XCTAssertTrue(out.isEmpty, "색인이 없으면 낡았다고 말할 근거가 없다")
    }

    func testEnvironmentEscapeHatchSilencesBanner() {
        StaleInstallIndex.write([(cli: "agent-browser", reason: "소스가 더 바뀜")], at: indexURL)
        var out = ""
        StaleInstallIndex.warnIfStale(
            arguments: ["/opt/homebrew/bin/agent-browser"],
            environment: [StaleInstallIndex.silenceEnvironmentKey: "1"],
            at: indexURL, emit: { out += $0 })
        XCTAssertTrue(out.isEmpty)
    }

    func testWriteThenReadRoundTrip() {
        StaleInstallIndex.write(
            [(cli: "a", reason: "소스가 더 바뀜"), (cli: "b", reason: "제3자가 덮어씀")],
            at: indexURL)
        XCTAssertEqual(StaleInstallIndex.reason(for: "b", at: indexURL), "제3자가 덮어씀")
        XCTAssertNil(StaleInstallIndex.reason(for: "c", at: indexURL))
    }
}
