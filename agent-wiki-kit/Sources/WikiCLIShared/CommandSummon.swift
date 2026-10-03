import Foundation
import KnowledgeBaseWikiCore

// summon — 자리만 둔 명령. 작업 T8 이 이 파일의 `runSummon` 만 채운다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `summon [--session <id>] [--since <t>] [--until <t>] [--device <k>] [--runtime <r>] [--role user|assistant|tool] [--query <q>] [--record <발화 번호>]`
// 지금은 "구현 전" 안내와 종료 코드 1.

public func runSummon(context: LawCommandContext, arguments: [String]) {
    lawNotImplemented(arguments.prefix(2).joined(separator: " "), task: "T8")
}
