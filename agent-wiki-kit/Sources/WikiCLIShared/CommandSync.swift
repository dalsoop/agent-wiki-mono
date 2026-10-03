import Foundation
import KnowledgeBaseWikiCore

// sync — agent-law git 동기화: 커밋 대기 기록 커밋 → origin pull(파일 합집합) → push.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `sync`. 규칙: docs/business-rules.md "공포·개정·폐지·원상회복".
// 원장 셋이 한 저장소라 어느 ledger 3 원장에서 불러도 저장소 전체를 동기화한다.
// 전신(ledger 1·2)은 결정 0007 에 따라 `gujo sync`(읽기 pull 만)로 한다.

let syncUsage = "사용법: sync [--json]"

public func runSync(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], usage: syncUsage)
    guard options.positionals.isEmpty else { usageFail(syncUsage) }
    guard context.isLedgerThree else {
        usageFail("sync 는 ledger 3 원장 전용 — 전신 원장은 gujo sync(읽기 pull 만)")
    }
    let sync = LawGitSync(ledgerRoot: context.lawTarget().root)
    switch sync.sync() {
    case .success(let outcome):
        if options.has("--json") {
            struct Envelope: Encodable { let ok: Bool; let result: LawSyncOutcome }
            printJSON(Envelope(ok: outcome.pushed, result: outcome))
        } else {
            print("커밋 대기 커밋: \(outcome.committedPending)") // allow:debug — 명령 결과 출력
            print("받아온 기록: \(outcome.received)") // allow:debug
            print("push: \(outcome.pushed ? "완료" : "실패")  \(outcome.branch) \(outcome.head ?? "?")") // allow:debug
            for message in outcome.messages { print("  \(message)") } // allow:debug
        }
        // push 실패는 숨기지 않는다 — 결과를 낸 뒤 거부 종료.
        if !outcome.pushed { exit(1) }
    case .failure(let error):
        if options.has("--json") {
            struct Failure: Encodable { let ok: Bool; let error: String }
            printJSON(Failure(ok: false, error: error.description))
            exit(1)
        }
        fail("sync 실패: \(error.description)")
    }
}
