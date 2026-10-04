import Foundation
import KnowledgeBaseWikiCore

// hook session — 세션 시작 훅. 표준 입력의 훅 JSON 과 환경으로 세션 등록 파일 하나를 남기고,
// 그 세션 원장(테넌트)과 공유 원장의 현행 목차를 표준 출력으로 보여 준다(실행 도구가 출력을 대화에 넣는다).
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `hook session` (세션 등록 `~/.agent-wiki/sessions/<세션 id>.json`),
// docs/business-rules.md "드리밍"(목차는 세션 시작 훅이 보여 준다).
// 원장을 열기 전에 불리므로 `context.world` 는 nil 일 수 있다(원장에 쓰지 않는다, 목차는 읽기만).
// 훅은 어떤 경우에도 세션을 막지 않는다: 잘못된 입력·쓰기 실패·목차 없음에도 종료 코드 0 으로 끝난다.

/// `hook session [--session <id>] [--runtime <r>] [--runtime-version <v>] [--model <m>] [--effort <e>]`.
/// 옵션은 관대하게 읽는다 — 모르는 옵션이나 값 없는 옵션도 훅을 실패시키지 않는다.
public func runHookSession(context: LawCommandContext, arguments: [String]) {
    let valued: Set<String> = ["--session", "--runtime", "--runtime-version", "--model", "--effort"]
    var values: [String: String] = [:]
    var index = 2
    while index < arguments.count {
        let token = arguments[index]
        if valued.contains(token), index + 1 < arguments.count {
            values[token] = arguments[index + 1]
            index += 2
        } else {
            index += 1
        }
    }
    let explicit = LawModelRecord(
        runtime: values["--runtime"], runtimeVersion: values["--runtime-version"],
        model: values["--model"], effort: values["--effort"])
    let payload = (try? FileHandle.standardInput.readToEnd()) ?? Data()
    let currentDirectory = FileManager.default.currentDirectoryPath
    LawSessionHook.run(
        payload: payload, registry: .standard, explicit: explicit, explicitSessionID: values["--session"],
        environment: context.environment, device: context.file.currentDevice,
        currentDirectory: currentDirectory)
    // 세션의 테넌트는 등록과 같은 판정(환경의 테넌트 context)으로 정한다. 등록을 못 남겨도 목차는 보여 준다.
    let tenant = LawSessionHook.registration(
        payload: payload, explicit: explicit, explicitSessionID: values["--session"],
        environment: context.environment, device: context.file.currentDevice,
        currentDirectory: currentDirectory)?.tenant
    let text = LawContents.sessionStartText(tenant: tenant, file: context.file, catalog: context.catalog)
    if !text.isEmpty { print(text, terminator: "") } // allow:debug — 세션 시작 훅의 목차 출력
}

/// `hook` 분기 — `hook session` 만 남고 `hook authoring` 은 폐지(앞 단계에서 64), 그 밖은 사용법 오류.
public func runHook(context: LawCommandContext, arguments: [String]) -> Never {
    guard arguments.dropFirst().first == "session" else { usageFail("사용법: hook session") }
    runHookSession(context: context, arguments: arguments)
    exit(0)
}
