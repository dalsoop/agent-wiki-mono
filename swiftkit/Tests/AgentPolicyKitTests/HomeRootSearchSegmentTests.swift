import XCTest
@testable import AgentPolicyKit

final class HomeRootSearchSegmentTests: XCTestCase {
    private var home: String { NSHomeDirectory() }
    private var policy: AgentToolPolicy {
        AgentToolPolicy(denyHomeRootSearch: true)
    }

    private func verdict(_ cmd: String) -> AgentPolicyStore.Verdict {
        policy.verdict(for: AgentToolCall(command: cmd), home: home)
    }

    // MARK: - 재현 5건 (오탐 1, 정탐 2, 정상 2)

    /// grep 은 stdin 을 읽고 df 에 home 인자가 전달된 복합 명령에서 오탐 차단되지 않아야 한다.
    func testFalsePositiveDfHomeDoesNotBlockGrep() {
        let cmd = "grep -v x | head -2; df -h \(home)"
        XCTAssertTrue(verdict(cmd).isAllowed, "grep 은 홈을 검색하지 않으므로 허용되어야 함")
    }

    /// grep 으로 홈 루트를 직접 검색하는 명령은 차단되어야 한다 (정탐).
    func testGrepHomeRootIsBlocked() {
        let cmd = "grep -rn foo \(home)"
        let v = verdict(cmd)
        XCTAssertFalse(v.isAllowed)
        XCTAssertEqual(v.reason, "HOME 루트 검색 금지 — 소유 CLI로 조회하세요")
    }

    /// find 로 홈 루트를 검색하는 명령은 차단되어야 한다 (정탐).
    func testFindHomeRootIsBlocked() {
        let cmd = "find \(home) -name x"
        let v = verdict(cmd)
        XCTAssertFalse(v.isAllowed)
        XCTAssertEqual(v.reason, "HOME 루트 검색 금지 — 소유 CLI로 조회하세요")
    }

    /// 파이프라인에서 grep 이 표준입력 필터로 쓰인 경우 정상 허용되어야 한다.
    func testGitLsTreePipedToGrepIsAllowed() {
        let cmd = "git ls-tree -r HEAD | grep '\\.swift$'"
        XCTAssertTrue(verdict(cmd).isAllowed)
    }

    /// sed 실행 및 환경변수 할당 후 python3 실행은 정상 허용되어야 한다.
    func testSedAndEnvAssignmentBeforePythonIsAllowed() {
        let cmd = "sed -e 's/foo/bar/g' file.txt; T=\(home)/.claude/settings.json; python3 - \"$T\""
        XCTAssertTrue(verdict(cmd).isAllowed)
    }

    // MARK: - 따옴표 및 Heredoc 격리

    /// 따옴표 안의 문자는 단순 문자열 인자이므로 검색 명령으로 오탐하지 않는다.
    func testQuotedGrepInsideEchoIsAllowed() {
        let cmd = "echo \"grep x ~\""
        XCTAssertTrue(verdict(cmd).isAllowed)
    }

    /// heredoc 본문 안의 내용은 실행되지 않으므로 차단하지 않는다.
    func testHeredocBodyContainingGrepIsAllowed() {
        let cmd = """
        cat <<'EOF'
        grep -r x ~
        EOF
        """
        XCTAssertTrue(verdict(cmd).isAllowed)
    }

    // MARK: - rg 및 find 경로 상세 판정

    /// rg foo ~/ 는 홈 루트 검색이므로 차단된다.
    func testRgHomeRootWithTrailingSlashIsBlocked() {
        let cmd = "rg foo ~/"
        let v = verdict(cmd)
        XCTAssertFalse(v.isAllowed)
        XCTAssertEqual(v.reason, "HOME 루트 검색 금지 — 소유 CLI로 조회하세요")
    }

    /// rg foo ~/src 는 홈 하위 경로 검색이므로 허용된다.
    func testRgHomeSubdirectoryIsAllowed() {
        let cmd = "rg foo ~/src"
        XCTAssertTrue(verdict(cmd).isAllowed)
    }

    /// find ~ -maxdepth 1 은 홈 루트 검색이므로 차단된다.
    func testFindTildeWithMaxdepthIsBlocked() {
        let cmd = "find ~ -maxdepth 1"
        let v = verdict(cmd)
        XCTAssertFalse(v.isAllowed)
        XCTAssertEqual(v.reason, "HOME 루트 검색 금지 — 소유 CLI로 조회하세요")
    }

    // MARK: - 추가 변형 검증 ($HOME, ${HOME}, 백틱, $() 등)

    func testDollarHomeSearchIsBlocked() {
        XCTAssertFalse(verdict("rg pattern $HOME").isAllowed)
        XCTAssertFalse(verdict("rg pattern ${HOME}").isAllowed)
        XCTAssertFalse(verdict("find $HOME/ -name foo").isAllowed)
        XCTAssertFalse(verdict("find ${HOME}/ -name foo").isAllowed)
    }

    func testSubshellCommandSubstitutionIsBlocked() {
        let cmd1 = "echo $(find ~ -maxdepth 1)"
        XCTAssertFalse(verdict(cmd1).isAllowed)

        let cmd2 = "echo `rg foo ~/`"
        XCTAssertFalse(verdict(cmd2).isAllowed)
    }

    func testSessionHuntOnlyBlocksSearchCommands() {
        let safeCmd = "uptime; df -h \(home)/.codex \(home)/.claude \(home)/.grok"
        XCTAssertTrue(verdict(safeCmd).isAllowed)

        let huntCmd = "rg token \(home)/.codex \(home)/.claude \(home)/.grok"
        let v = verdict(huntCmd)
        XCTAssertFalse(v.isAllowed)
        XCTAssertEqual(v.reason, "세션 디렉터리 동시 훑기 금지 — 소유 CLI로 조회하세요")
    }

    // MARK: - grep -r 과 래퍼(timeout 등) 빈틈

    /// grep 의 -r 은 값을 받지 않는다. `grep -r foo ~` 의 ~ 는 경로 피연산자다.
    func testGrepRecursiveFlagThenHomeIsBlocked() {
        XCTAssertFalse(verdict("grep -r foo ~").isAllowed)
        XCTAssertFalse(verdict("grep -R foo \(home)").isAllowed)
        XCTAssertFalse(verdict("egrep -r 'a|b' ~/").isAllowed)
        XCTAssertFalse(verdict("grep -r --include '*.md' foo $HOME").isAllowed)
    }

    /// rg 의 -r 은 --replace 라 값을 받는다. 치환 문자열 뒤의 하위 경로는 허용한다.
    func testRgReplaceFlagKeepsTakingValue() {
        XCTAssertTrue(verdict("rg -r bar foo ~/src").isAllowed)
        XCTAssertFalse(verdict("rg -r bar foo ~").isAllowed)
    }

    /// timeout·env·nice 등 실행 래퍼 뒤의 검색 명령도 판정한다.
    func testWrappedHomeSearchIsBlocked() {
        XCTAssertFalse(verdict("timeout 10 rg foo ~").isAllowed)
        XCTAssertFalse(verdict("timeout -s KILL 5s grep -r foo ~").isAllowed)
        XCTAssertFalse(verdict("gtimeout --kill-after=2 10 find ~ -name x").isAllowed)
        XCTAssertFalse(verdict("env LC_ALL=C grep -r foo ~").isAllowed)
        XCTAssertFalse(verdict("nice -n 10 timeout 30 rg foo $HOME").isAllowed)
        XCTAssertFalse(verdict("nohup rg foo ~ > /dev/null").isAllowed)
        XCTAssertFalse(verdict("command rg foo ~").isAllowed)
        XCTAssertFalse(verdict("ls; timeout 15 rg -l token ~ | head").isAllowed)
    }

    /// 래퍼 뒤라도 하위 경로 검색, stdin 필터, 조회 명령은 허용한다.
    func testWrappedSafeCommandsAreAllowed() {
        XCTAssertTrue(verdict("timeout 10 rg foo ~/src").isAllowed)
        XCTAssertTrue(verdict("timeout 10 grep -r foo ./Sources").isAllowed)
        XCTAssertTrue(verdict("env LC_ALL=C sort file | grep -r foo").isAllowed)
        XCTAssertTrue(verdict("command -v rg ~").isAllowed)
        XCTAssertTrue(verdict("timeout 5 ls ~").isAllowed)
    }

    /// 래퍼 뒤의 세션 디렉터리 동시 훑기도 막는다.
    func testWrappedSessionHuntIsBlocked() {
        let cmd = "timeout 15 rg token \(home)/.codex \(home)/.claude \(home)/.grok"
        XCTAssertEqual(verdict(cmd).reason, "세션 디렉터리 동시 훑기 금지 — 소유 CLI로 조회하세요")
    }
}
