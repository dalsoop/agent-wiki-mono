import Foundation
import KnowledgeBaseWikiCore

// judgment — 자리만 둔 명령. 작업 T11 이 이 파일의 `runJudgment` 만 채운다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `judgment register|list|show` (판결 등록)
// 지금은 "구현 전" 안내와 종료 코드 1.

public func runJudgment(context: LawCommandContext, arguments: [String]) {
    lawNotImplemented(arguments.prefix(2).joined(separator: " "), task: "T11")
}
