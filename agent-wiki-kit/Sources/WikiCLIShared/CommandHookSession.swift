import Foundation
import KnowledgeBaseWikiCore

// hook session — 자리만 둔 명령. 작업 T6 이 이 파일의 `runHookSession` 만 채운다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `hook session` (세션 등록 `~/.agent-wiki/sessions/<세션 id>.json`).
// 원장을 열기 전에 불리므로 `context.world` 는 nil 일 수 있다. 지금은 "구현 전" 안내와 종료 코드 1.

public func runHookSession(context: LawCommandContext, arguments: [String]) {
    lawNotImplemented("hook session", task: "T6")
}

/// `hook` 분기 — `hook session` 만 남고 `hook authoring` 은 폐지(앞 단계에서 64), 그 밖은 사용법 오류.
public func runHook(context: LawCommandContext, arguments: [String]) -> Never {
    guard arguments.dropFirst().first == "session" else { usageFail("사용법: hook session") }
    runHookSession(context: context, arguments: arguments)
    exit(0)
}
