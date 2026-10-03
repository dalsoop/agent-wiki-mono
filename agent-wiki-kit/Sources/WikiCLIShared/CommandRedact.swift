import Foundation
import KnowledgeBaseWikiCore

// redact — 자리만 둔 명령. 작업 T7 이 이 파일의 `runRedact` 만 채운다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `redact <R2 키 또는 sha> --reason <r>` (증거물 가림)
// 지금은 "구현 전" 안내와 종료 코드 1.

public func runRedact(context: LawCommandContext, arguments: [String]) {
    lawNotImplemented(arguments.prefix(2).joined(separator: " "), task: "T7")
}
