import XCTest
@testable import AgentWikiReaderCore

/// 읽기 전용 프록시의 agent-law 판정 — docs/contracts.md "agent-law 명령"의 프록시 거부 목록.
final class AgentLawProxyTests: XCTestCase {
    func testBlocksAgentLawWrites() {
        let writes: [[String]] = [
            ["enact", "--title", "x"], ["amend", "abc", "--title", "x"], ["repeal", "abc"], ["restore", "b1"],
            ["finding", "abc", "--subject", "project"], ["exhibit", "put", "f"], ["redact", "abc", "--reason", "r"],
            ["archive"], ["sync"], ["dream", "run"], ["dream", "resume"], ["court", "appeal", "abc"],
            ["court", "propose", "abc"], ["court", "hear"], ["court", "decide", "x"], ["judgment", "register"],
            ["promote", "abc", "--to", "agent-law"], ["world", "add", "agent-law", "--key", "law"],
            ["world", "tenant-map", "personal", "x"], ["world", "device", "register", "mac"],
            ["world", "dream-device", "mac"], ["hook", "session"], ["--world", "agent-law", "enact"],
            ["summon", "--record", "3"], ["contents"],
        ]
        for args in writes {
            XCTAssertFalse(AgentWikiReaderService.isReadOnlyInvocation(args), "\(args)")
        }
    }

    func testAllowsAgentLawReads() {
        let reads: [[String]] = [
            ["audit"], ["history", "abc"], ["exhibit", "get", "abc"], ["court", "list"], ["judgment", "list"],
            ["judgment", "show", "abc"], ["dream", "status"], ["report", "models"], ["show", "abc"],
            ["--world", "agent-law", "search", "q"], ["cited-by", "abc"], ["path", "a", "b"],
        ]
        for args in reads {
            XCTAssertTrue(AgentWikiReaderService.isReadOnlyInvocation(args), "\(args)")
        }
    }
}
