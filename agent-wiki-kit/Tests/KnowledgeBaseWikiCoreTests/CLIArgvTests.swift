import Foundation
import Testing
@testable import KnowledgeBaseWikiCore

@Suite struct CLIArgvTests {
    @Test func peelsLeadingWorldAndAsOnly() {
        let p = CLIArgv.peelLeadingGlobals(
            ["--as", "agent:x", "--world", "gujo-wiki", "weight", "set", "--world", "swift-app-mono", "--w", "2"],
            defaultAuthor: "default")
        #expect(p.author == "agent:x")
        #expect(p.world == "gujo-wiki")
        #expect(p.rest == ["weight", "set", "--world", "swift-app-mono", "--w", "2"])
    }

    @Test func leavesMidCommandWorldIntact() {
        let p = CLIArgv.peelLeadingGlobals(
            ["weight", "set", "--agent", "a", "--world", "w", "--w", "1.5"],
            defaultAuthor: "d")
        #expect(p.world == nil)
        #expect(p.rest.contains("--world"))
    }

    @Test func noGlobalsPassthrough() {
        let p = CLIArgv.peelLeadingGlobals(["search", "q", "--fleet"], defaultAuthor: "d")
        #expect(p.author == "d")
        #expect(p.rest == ["search", "q", "--fleet"])
    }

    @Test func recognizesHelpTokensWithoutTreatingOrdinaryTitlesAsHelp() {
        #expect(CLIArgv.isHelpToken("help"))
        #expect(CLIArgv.isHelpToken("--help"))
        #expect(CLIArgv.isHelpToken("-h"))
        #expect(!CLIArgv.isHelpToken("help wanted"))
    }

    @Test func positionalArgumentsSkipOptionValues() {
        let args = [
            "gujo", "blob", "pull", "abc123", "--root", "/Users/me/gujo-wiki",
            "--json", "def456",
        ]
        #expect(CLIArgv.positionals(
            in: args, startingAt: 3, optionsWithValues: ["--root"]
        ) == ["abc123", "def456"])
        #expect(CLIArgv.positionals(
            in: ["gujo", "blob", "push", "--root", "/tmp/world", "--json"],
            startingAt: 3, optionsWithValues: ["--root"]
        ).isEmpty)
    }

    @Test func repositoryDestinationKeysStayValidatedByCore() {
        #expect(RepositoryDestinationKey.isValid("tasks"))
        #expect(RepositoryDestinationKey.isValid("promotion"))
        #expect(!RepositoryDestinationKey.isValid("task"))
    }
}
