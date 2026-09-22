import XCTest
@testable import DoctorKit

/// 자격 도달 축 — agent-vault 판정을 doctor 로 옮길 때 의미가 안 바뀌는지.
final class VaultConsumerProviderTests: XCTestCase {
    private func json(rows: String, installed: Int, declared: Int) -> String {
        """
        {"ok":true,"result":{"rows":[\(rows)],"installedApps":\(installed),"declaredConsumers":\(declared)}}
        """
    }

    func testUnregisteredConsumerIsFail() {
        let out = json(
            rows: #"{"key":"dns-zone-manager","state":"unregistered","executablePath":"/opt/homebrew/bin/dns-zone-manager"}"#,
            installed: 175, declared: 2)
        let f = VaultConsumerReportMapper.map(stdout: out, exitCode: 1, source: "t")
        let fail = f.first { $0.severity == .fail }
        XCTAssertNotNil(fail)
        XCTAssertTrue(fail?.title.contains("등록돼 있지 않다") == true)
        XCTAssertNotNil(fail?.remedy, "판정만 하고 할 일을 안 알려주면 보고서다")
    }

    func testOrphanedRegistrationIsWarnNotFail() {
        let out = json(
            rows: #"{"key":"app:gone@macbook","state":"orphanedRegistration","executablePath":"/opt/homebrew/bin/gone"}"#,
            installed: 175, declared: 2)
        let f = VaultConsumerReportMapper.map(stdout: out, exitCode: 1, source: "t")
        XCTAssertEqual(f.first { $0.category == .credentialReach && $0.severity == .warn }?.title.contains("유령 등록"), true)
        XCTAssertNil(f.first { $0.severity == .fail }, "유령 등록은 앱을 죽이지 않는다 — 등급을 섞지 않는다")
    }

    /// **선언 안 한 앱은 안 잡힌다.** 통과했다고 안심시키면 거짓이다.
    func testBlindSpotIsAlwaysReported() {
        let out = json(rows: "", installed: 175, declared: 2)
        let f = VaultConsumerReportMapper.map(stdout: out, exitCode: 0, source: "t")
        let info = f.first { $0.severity == .info }
        XCTAssertNotNil(info, "173개가 사각인데 'ok' 하나로 끝내면 안 된다")
        XCTAssertTrue(info?.detail.contains("173") == true)
    }

    func testAllDeclaredAndRegisteredIsOk() {
        let out = json(rows: "", installed: 3, declared: 3)
        let f = VaultConsumerReportMapper.map(stdout: out, exitCode: 0, source: "t")
        XCTAssertEqual(f.count, 1)
        XCTAssertEqual(f.first?.severity, .ok)
    }

    /// exit 1 은 "손댈 게 있다" 는 정상 신호다 — 그걸 파싱 실패로 오해하면 안 된다.
    func testNonZeroExitWithValidJSONIsNotAParseError() {
        let out = json(rows: "", installed: 3, declared: 3)
        let f = VaultConsumerReportMapper.map(stdout: out, exitCode: 1, source: "t")
        XCTAssertFalse(f.contains { $0.title.contains("읽을 수 없다") })
    }

    func testGarbageOutputIsReportedNotSwallowed() {
        let f = VaultConsumerReportMapper.map(stdout: "not json", exitCode: 2, source: "t")
        XCTAssertEqual(f.first?.severity, .warn)
        XCTAssertTrue(f.first?.title.contains("읽을 수 없다") == true)
    }

    /// vault 가 없는 기계에서는 이 축을 조용히 생략한다.
    func testMissingCLISkipsAxis() async {
        let p = VaultConsumerProvider(
            resolveOnPath: { _, _ in nil },
            runCLI: { _, _, _ in (0, "should not run") })
        let f = await p.run()
        XCTAssertTrue(f.isEmpty)
    }
}

extension VaultConsumerProviderTests {
    /// 구버전 vault 는 `consumers` 를 모른다 — 거짓 경보 대신 재설치를 알린다.
    func testOldVaultCLIUsageErrorIsInfoWithRemedy() {
        let f = VaultConsumerReportMapper.map(
            stdout: "usage: agent-vault …", exitCode: 64, source: "t")
        XCTAssertEqual(f.first?.severity, .info)
        XCTAssertTrue(f.first?.remedy?.contains("ship agent-vault-swift") == true)
        XCTAssertFalse(f.contains { $0.severity == .warn || $0.severity == .fail })
    }
}
