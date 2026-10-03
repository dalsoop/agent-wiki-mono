import Foundation
import KnowledgeBaseWikiCore

// archive — 자리만 둔 명령. 작업 T7 이 이 파일의 `runArchive` 만 채운다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `archive [--dry-run]` (세션 조각 R2 적재)
// 지금은 "구현 전" 안내와 종료 코드 1.

public func runArchive(context: LawCommandContext, arguments: [String]) {
    lawNotImplemented(arguments.prefix(2).joined(separator: " "), task: "T7")
}
