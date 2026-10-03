import Foundation
import Testing
@testable import WikiCLIShared

/// 명령 표면 분기 시험 — 폐지 이름(64), 형식별 분기, 쓰기 게이트 대상, capabilities, 두 CLI 의 허용 옵션.
/// 근거: docs/contracts.md "agent-law 명령 (ledger 3)", docs/standards.md "CLI 표면".
@Suite struct CommandSurfaceRoutingTests {

    @Test func retiredNamesGuideToNewNames() {
        let cases: [([String], String)] = [
            (["publish", "--title", "x"], "enact"),
            (["verify"], "audit"),
            (["rollback", "b1"], "restore"),
            (["classify", "abc"], "finding"),
            (["capture", "https://x"], "exhibit put"),
            (["blob", "put", "f"], "exhibit put"),
            (["blob", "gc"], "redact"),
            (["hook", "authoring"], "hook session"),
        ]
        for (arguments, next) in cases {
            let guidance = CommandSurfaceRouting.retiredGuidance(arguments)
            #expect(guidance?.contains(next) == true, "\(arguments)")
        }
        for arguments in [["enact"], ["blob", "get", "x"], ["hook", "session"], ["show", "x"], ["checkpoint"]] {
            #expect(CommandSurfaceRouting.retiredGuidance(arguments) == nil, "\(arguments)")
        }
    }

    @Test func ledgerTwoOnlyWritesRefusedOnLedgerThreeOnly() {
        for command in ["discuss", "learn", "review", "event", "task", "agent", "policy", "migrate", "tick"] {
            #expect(CommandSurfaceRouting.ledgerTwoOnlyGuidance([command], isLedgerThree: true) != nil, "\(command)")
            #expect(CommandSurfaceRouting.ledgerTwoOnlyGuidance([command], isLedgerThree: false) == nil, "\(command)")
        }
        for command in ["checkpoint", "enact", "show", "search", "audit", "promote", "history"] {
            #expect(CommandSurfaceRouting.ledgerTwoOnlyGuidance([command], isLedgerThree: true) == nil, "\(command)")
        }
    }

    @Test func writeCommandsGoThroughWriteGate() {
        for arguments in [["enact"], ["amend", "x"], ["repeal", "x"], ["restore", "b"], ["finding", "x"],
                          ["checkpoint"], ["promote", "x"], ["exhibit", "put", "f"], ["promotion", "publish", "x"],
                          ["event", "append"], ["agent", "run", "r"]] {
            #expect(CommandSurfaceRouting.isLedgerWrite(arguments), "\(arguments)")
        }
        for arguments in [["show", "x"], ["audit"], ["exhibit", "get", "x"], ["search", "q"], ["history", "x"],
                          ["promotion", "preview", "x"], ["task", "list"]] {
            #expect(!CommandSurfaceRouting.isLedgerWrite(arguments), "\(arguments)")
        }
    }

    @Test func capabilitiesListNewCommands() {
        let names = Set(capabilityCommandNames)
        for name in ["enact", "amend", "repeal", "history", "audit", "restore", "finding", "exhibit", "exhibit put",
                     "exhibit get", "redact", "summon", "archive", "sync", "dream", "court", "judgment", "contents",
                     "report models", "promote", "world add", "world tenant-map", "world device register",
                     "world dream-device", "hook session", "checkpoint", "index"] {
            #expect(names.contains(name), "\(name)")
        }
        for retired in ["publish", "verify", "classify", "capture", "rollback"] {
            #expect(!names.contains(retired), "\(retired)")
        }
    }

    /// 두 CLI 의 `allowedOptions` 블록을 소스에서 읽어 agent-law 옵션이 양쪽에 다 있는지 본다.
    @Test func lawOptionsAllowedInBothCLIs() throws {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let mains = [
            "apps/agent-wiki-synchronizer/Sources/AgentWikiSynchronizerCLI/main.swift",
            "apps/agent-wiki-indexer/Sources/AgentWikiIndexerCLI/main.swift",
        ]
        for relative in mains {
            let text = try String(contentsOf: repo.appendingPathComponent(relative), encoding: .utf8)
            let start = try #require(text.range(of: "let allowedOptions: Set<String> = ["))
            let end = try #require(text.range(of: "]\n", range: start.upperBound..<text.endIndex))
            let block = text[start.upperBound..<end.lowerBound]
            for option in CommandSurfaceRouting.lawOptions {
                #expect(block.contains("\"\(option)\""), "\(relative) 에 \(option) 없음")
            }
        }
    }

    @Test func citeSyntaxSplitsRelation() {
        #expect(splitCite("abcd1234").rel == "cites")
        #expect(splitCite("abcd1234:testifies").token == "abcd1234")
        #expect(splitCite("abcd1234:testifies").rel == "testifies")
    }

    @Test func optionParserSeparatesValuesFlagsAndPositionals() {
        let parsed = LawOptions.parse(
            ["amend", "abc", "--also", "def", "--title", "t", "--json", "--tag", "a", "--tag", "b"],
            valued: ["--also", "--title", "--tag"], usage: "u")
        #expect(parsed.positionals == ["abc"])
        #expect(parsed.all("--tag") == ["a", "b"])
        #expect(parsed.value("--title") == "t")
        #expect(parsed.has("--json"))
    }
}
