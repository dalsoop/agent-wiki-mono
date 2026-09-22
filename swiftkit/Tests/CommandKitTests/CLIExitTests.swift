import XCTest
@testable import CommandKit

/// 종료 코드는 **함대의 공용 언어**다 — 뜻이 갈리면 "고쳐야 할 목록" 이 거짓이 된다.
final class CLIExitTests: XCTestCase {
    /// sysexits 표준값과 맞아야 셸·다른 도구와도 뜻이 통한다.
    func testStandardValues() {
        XCTAssertEqual(CLIExit.ok, 0)
        XCTAssertEqual(CLIExit.finding, 1)
        XCTAssertEqual(CLIExit.usage, 64)
        XCTAssertEqual(CLIExit.unavailable, 69)
    }

    /// **네 갈래는 배타적이다.** 64·69 를 발견으로 세면 진짜 문제가 묻힌다
    /// (실측 2026-08-05: "문제 14건" 중 실제 코드 결함은 1건이었다).
    func testOnlyRealProblemsCountAsFindings() {
        XCTAssertFalse(CLIExit.isFinding(CLIExit.ok))
        XCTAssertFalse(CLIExit.isFinding(CLIExit.usage))
        XCTAssertFalse(CLIExit.isFinding(CLIExit.unavailable))
        XCTAssertTrue(CLIExit.isFinding(CLIExit.finding))
        XCTAssertTrue(CLIExit.isFinding(2))   // shadow 는 발견이 있으면 2로 끝낸다
    }

    /// 상대가 없어서 못 하는 것을 가른다.
    func testUnavailableSignals() {
        XCTAssertTrue(CLIExit.looksUnavailable(
            "ssh: connect to host x port 22: Network is unreachable"))
        XCTAssertTrue(CLIExit.looksUnavailable(
            "dial tcp 127.0.0.1:26443: connect: connection refused"))
        XCTAssertTrue(CLIExit.looksUnavailable("no API key; configure GUI"))
    }

    /// **애매하면 발견으로 남긴다** — 조용히 미설정으로 치우면 진짜 고장이 숨는다.
    func testAmbiguousFailuresStayFindings() {
        XCTAssertFalse(CLIExit.looksUnavailable("manifest.json 없음"))
        XCTAssertFalse(CLIExit.looksUnavailable("exit status 1"))
        XCTAssertFalse(CLIExit.looksUnavailable(""))
    }
}
