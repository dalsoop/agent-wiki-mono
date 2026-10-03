import Foundation
import KnowledgeBaseWikiCore

// report models — 자리만 둔 명령. 작업 T10 이 이 파일의 `runReport` 만 채운다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `report models [--since <t>]` (모델별 공포 보고)
// 지금은 "구현 전" 안내와 종료 코드 1.

public func runReport(context: LawCommandContext, arguments: [String]) {
    lawNotImplemented(arguments.prefix(2).joined(separator: " "), task: "T10")
}
