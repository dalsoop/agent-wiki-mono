import Foundation
import KnowledgeBaseWikiCore

// sync — 자리만 둔 명령. 작업 T5 이 이 파일의 `runSync` 만 채운다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `sync` (git pull·push, 커밋 대기 처리)
// 지금은 "구현 전" 안내와 종료 코드 1.

public func runSync(context: LawCommandContext, arguments: [String]) {
    lawNotImplemented(arguments.prefix(2).joined(separator: " "), task: "T5")
}
