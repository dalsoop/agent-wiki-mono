import XCTest
@testable import SessionKit

final class ResumeRequestParserTests: XCTestCase {
    func testAgyEqualsAndSpace() {
        let eq = ResumeRequestParser.parse("agy --conversation=eabf41c3-43a3-4acf-8e92-d3c80dbb1efc")
        XCTAssertEqual(eq?.runtime, .agy)
        XCTAssertEqual(eq?.sessionID, "eabf41c3-43a3-4acf-8e92-d3c80dbb1efc")
        let sp = ResumeRequestParser.parse("agy --conversation eabf41c3-43a3-4acf-8e92-d3c80dbb1efc")
        XCTAssertEqual(sp, eq)
    }

    func testClaudeResumeAndShortFlag() {
        let full = ResumeRequestParser.parse("claude --resume 5e2fdd07-aaaa-bbbb-cccc-ddddeeeeffff")
        XCTAssertEqual(full?.runtime, .claude)
        XCTAssertEqual(full?.sessionID, "5e2fdd07-aaaa-bbbb-cccc-ddddeeeeffff")
        let short = ResumeRequestParser.parse("claude -r 5e2fdd07-aaaa-bbbb-cccc-ddddeeeeffff")
        XCTAssertEqual(short, full)
    }

    func testCodexSubcommandAndGrokFlag() {
        let codex = ResumeRequestParser.parse("codex resume 0193abcd-1111-2222-3333-444455556666")
        XCTAssertEqual(codex?.runtime, .codex)
        let grok = ResumeRequestParser.parse("grok --resume 0193abcd-1111-2222-3333-444455556666")
        XCTAssertEqual(grok?.runtime, .grok)
    }

    func testConversationWithoutExecutableIsAgy() {
        let req = ResumeRequestParser.parse("--conversation=eabf41c3-43a3-4acf-8e92-d3c80dbb1efc")
        XCTAssertEqual(req?.runtime, .agy)
        XCTAssertEqual(req?.sessionID, "eabf41c3-43a3-4acf-8e92-d3c80dbb1efc")
    }

    func testSharedResumeFlagLeavesRuntimeNil() {
        let req = ResumeRequestParser.parse("--resume 5e2fdd07-aaaa-bbbb-cccc-ddddeeeeffff")
        XCTAssertEqual(req?.runtime, nil)
        XCTAssertEqual(req?.sessionID, "5e2fdd07-aaaa-bbbb-cccc-ddddeeeeffff")
    }

    func testBareSessionIDAndRejectSentence() {
        let id = ResumeRequestParser.parse("eabf41c3-43a3-4acf-8e92-d3c80dbb1efc")
        XCTAssertEqual(id?.runtime, nil)
        XCTAssertEqual(id?.sessionID, "eabf41c3-43a3-4acf-8e92-d3c80dbb1efc")
        XCTAssertNil(ResumeRequestParser.parse("이어서 해줘"))
        XCTAssertNil(ResumeRequestParser.parse("resume later please"))
    }

    func testResumeArgumentsFollowFirstToken() {
        XCTAssertEqual(AIRuntime.claude.resumeArguments(sessionID: "abc"), ["--resume", "abc"])
        XCTAssertEqual(AIRuntime.codex.resumeArguments(sessionID: "abc"), ["resume", "abc"])
        XCTAssertEqual(AIRuntime.grok.resumeArguments(sessionID: "abc"), ["--resume", "abc"])
        XCTAssertEqual(AIRuntime.agy.resumeArguments(sessionID: "abc"), ["--conversation", "abc"])
    }
}
