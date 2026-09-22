import Foundation
import KnowledgeBaseWikiCore
import CommandKit
import StateRootKit

// 에이전트 오케스트레이션 — 셸 tick 스크립트를 제품(CLI)으로 흡수한 것.
// launchd 는 이 바이너리를 직접 부른다: agent-wiki tick <이름> / agent run.
// 감독 루프(워치독·재시도·Reflexion)·역할 동기화·distill·tick(checkpoint/librarian/verifier/…).

// 모듈 공유(backup·appcontrol 도 사용)
public func nowISO() -> String { LedgerObject.iso.string(from: Date()) }

private func agentValue(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

private func agentStdinBody() -> String {
    guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else { return "" }
    return String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

/// run 별 하트비트 — .runs/status/<pid>.json. 동시 run 이 서로를 지우지 못한다.
private func statusFile(root: URL) -> URL {
    let dir = root.appendingPathComponent(".runs/status")
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        fputs("warning: createDirectory \(dir.path): \(error.localizedDescription)\n", stderr)
    }
    return dir.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier).json")
}

func writeStatus(root: URL, label: String, detail: String) {
    let payload = "{\"label\":\"\(label)\",\"detail\":\"\(detail)\",\"updatedAt\":\"\(nowISO())\"}"
    do {
        try payload.write(to: statusFile(root: root), atomically: true, encoding: .utf8)
    } catch {
        fputs("warning: writeStatus: \(error.localizedDescription)\n", stderr)
    }
}

func clearStatus(root: URL) {
    do {
        try FileManager.default.removeItem(at: statusFile(root: root))
    } catch {
        let ns = error as NSError
        if ns.domain != NSCocoaErrorDomain || ns.code != NSFileNoSuchFileError {
            fputs("warning: clearStatus: \(error.localizedDescription)\n", stderr)
        }
    }
}

/// 역할 frontmatter engine: → 실행 커맨드라인. 엔진 정본은 역할 정의 파일.
private func engineArguments(role: String, root: URL, prompt: String) -> [String] {
    let repoRoot = RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: root)
    let engine = (try? RepositoryAgentRoleStore(repositoryRoot: repoRoot).load(id: role).engine) ?? "codex"
    switch engine {
    case "codex": return ["codex", "exec", prompt]
    case "grok": return ["grok", "--single", prompt, "--output-format", "plain"]
    case "opencode": return ["opencode", "run", prompt]
    default: return ["claude", "-p", prompt, "--output-format", "text"]
    }
}

@discardableResult
/// 에이전트 실행 하네스 — 한 방 fire-and-forget 이 아니라 감독 루프:
/// ① 워치독(타임아웃 초과 시 SIGTERM→SIGKILL, 영원히 매달리는 것 방지)
/// ② 경계 재시도 + Reflexion(실패하면 실패 요약을 프롬프트에 붙여 다시)
/// ③ 시도별 사건(step) — 하네스 동작이 관찰·학습 재료가 된다.
/// ④ SPL 주입(경험칙) — 배운 걸 매 실행 프롬프트에 되먹임.
func runEngine(role: String, root: URL, prompt basePromptIn: String, logURL: URL? = nil,
                       maxAttempts: Int = 2, timeoutSeconds: Int = 1800) -> Int32 {
    var basePrompt = basePromptIn
    if role != "retrospective" {
        let store = LedgerStore(root: root)
        basePrompt += store.experienceRulesPrompt(store.scan(), forRole: role)
    }
    // T1 작업 사건 — run 시작(pending). run-reaper 는 이 pending 으로 좌초를 판정.
    let log = EventLog(root: root)
    let runEvent = Event(writer: role, subject: role, rel: "역할 실행", level: .run, extras: Event.Extras(outcome: .pending))
    do { try log.append(runEvent) } catch { fputs("warn: event log: \(error)\n", stderr) }

    var lastFailure = ""
    var finalCode: Int32 = 127
    for attempt in 1...max(1, maxAttempts) {
        let attemptPrompt = basePrompt + (lastFailure.isEmpty ? "" :
            "\n\n## 지난 시도 실패 — 원인을 고쳐서 다시 하라 (Reflexion)\n\(lastFailure)\n")
        let (code, timedOut) = spawnEngine(role: role, root: root, prompt: attemptPrompt,
                                           logURL: logURL, runID: runEvent.id, timeoutSeconds: timeoutSeconds)
        let relText = "시도 \(attempt) " + (code == 0 ? "성공" : timedOut ? "타임아웃" : "실패")
        let stepExtras = Event.Extras(
            parent: runEvent.id,
            attrs: ["attempt": String(attempt), "exit": String(code)])
        do { try log.append(Event(
            writer: role, subject: role, rel: relText,
            level: .step, extras: stepExtras))
        } catch { fputs("warn: event log step: \(error)\n", stderr) }
        finalCode = code
        if code == 0 { break }
        lastFailure = "시도 \(attempt): exit \(code)"
            + (timedOut ? " (타임아웃 \(timeoutSeconds)s 초과 → 강제 종료)" : "")
        if attempt < maxAttempts { print("\(nowISO()) \(role) 시도 \(attempt) 실패 — 재시도") } // allow:debug
    }
    let runExtras = Event.Extras(
        parent: runEvent.id,
        outcome: finalCode == 0 ? .ok : .fail,
        attrs: ["exit": String(finalCode)])
    do { try log.append(Event(
        writer: role, subject: role,
        rel: finalCode == 0 ? "성공" : "실패",
        level: .run, extras: runExtras))
    } catch { fputs("warn: event log run: \(error)\n", stderr) }
    return finalCode
}

/// 엔진 프로세스 1회 실행 + 워치독. 반환: (종료코드, 타임아웃여부).
private func spawnEngine(role: String, root: URL, prompt: String, logURL: URL?,
                        runID: String, timeoutSeconds: Int) -> (code: Int32, timedOut: Bool) {
    let arguments = engineArguments(role: role, root: root, prompt: prompt)
    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = "\(StateRootKit.path(".local/bin")):/opt/homebrew/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
    environment["MEMO_LEDGER_RUN"] = runID   // 자식 capture·event step 이 이 작업에 매달리게

    let safeResult = SafeProcessRunner.run(
        "/usr/bin/env",
        arguments,
        environment: environment,
        workingDirectory: RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: root),
        timeout: TimeInterval(timeoutSeconds)
    )
    if let logURL {
        do { try safeResult.combinedOutput.write(to: logURL, atomically: true, encoding: .utf8) } catch { _ = error }
    }
    return (safeResult.exitCode, safeResult.timedOut)
}

/// 역할정의 head 본문에서 "개정 사유:" 머리줄을 벗겨 파일 본문과 대조 가능한 형태로.
private func roleDefinitionBody(_ object: LedgerObject) -> String {
    var lines = object.body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    if let first = lines.first, first.hasPrefix("개정 사유:") {
        lines.removeFirst()
        while let head = lines.first, head.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeFirst() }
    }
    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// agent sync — .agents/roles/*.md 파일과 원장 역할정의 head 를 대조해
/// 어긋난/새 파일을 개정판으로 발행한다. 외부 편집(직접 수정)도 이력에 남는다.
public func runAgentSync(store: LedgerStore, root: URL) {
    let roleStore = RepositoryAgentRoleStore(
        repositoryRoot: RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: root))
    let dir = roleStore.rolesDirectory
    let urls: [URL]
    do { urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) }
    catch { print("역할 디렉터리 없음: \(error.localizedDescription)"); return } // allow:debug
    let objects = store.scan()
    var synced = 0
    for url in urls where url.pathExtension == "md" {
        let name = url.deletingPathExtension().lastPathComponent
        guard let fileBody = try? String(contentsOf: url, encoding: .utf8) else { continue } // try?: continue-skip
        let trimmed = fileBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = objects
            .filter { $0.effectiveType == "role-definition" && $0.title == "역할정의: \(name)" }
        let head = store.heads(history).first ?? history.sorted { ($0.published, $0.id) > ($1.published, $1.id) }.first
        if let head, roleDefinitionBody(head) == trimmed { continue }  // 변경 없음
        let reason = head == nil ? "파일 신규 감지 (동기화)" : "파일 변경 감지 (외부 편집 동기화)"
        do {
            _ = try store.publish(author: "run-reaper", title: "역할정의: \(name)", type: "role-definition", body: "개정 사유: \(reason)\n\n" + trimmed, extras: LedgerPublishExtras(supersedes: head?.id, origin: "file://" + url.path))
            print("동기화: \(name)  (\(reason))") // allow:debug
            synced += 1
        } catch { fail("\(error)") }
    }
    if synced == 0 { print("\(nowISO()) 역할 정의 드리프트 없음") } // allow:debug
}

private func recordRunResult(
    store: LedgerStore, root: URL, role: String, task: String, code: Int32,
    canonicalTaskID: String?, runtimeTaskID: String?, dispatchID: String?
) {
    if code == 0, let canonicalTaskID, let runtimeTaskID, let dispatchID {
        do {
            _ = try RepositoryTaskService(store: store, repository: nil, author: role)
                .recordWorkerDone(
                    taskID: canonicalTaskID,
                    runtimeTaskID: runtimeTaskID,
                    dispatchID: dispatchID,
                    worker: role,
                    result: "에이전트 실행 성공: \(task)")
        } catch {
            clearStatus(root: root)
            fail("worker_done 기록 실패: \(error)")
        }
    } else if code != 0, let canonicalTaskID, let runtimeTaskID, let dispatchID {
        do {
            _ = try RepositoryTaskService(store: store, repository: nil, author: role)
                .recordWorkerFailure(
                    taskID: canonicalTaskID,
                    runtimeTaskID: runtimeTaskID,
                    dispatchID: dispatchID,
                    worker: role,
                    exitCode: code,
                    message: "에이전트 프로세스가 종료 코드 \(code)로 실패했습니다. 엔진 상태를 확인한 뒤 재시도하세요.")
        } catch {
            FileHandle.standardError.write(Data("worker failure 기록 실패: \(error)\n".utf8))
        }
    }
}

public func runAgentCommand(store: LedgerStore, root: URL, author: String, arguments: [String]) {
    if arguments.count >= 2, arguments[1] == "role" {
        runAgentRoleCommand(store: store, root: root, author: author, arguments: arguments)
        return
    }
    if arguments.count >= 2, arguments[1] == "sync" { runAgentSync(store: store, root: root); return }
    if arguments.count >= 3, arguments[1] == "evolve" { runEvolve(store: store, root: root, role: arguments[2]); return }
    guard arguments.count >= 4, arguments[1] == "run" else { fail(usage) }
    runAgentRun(store: store, root: root, arguments: arguments)
}

private func parseRunTaskParts(_ arguments: [String]) -> [String] {
    var taskParts: [String] = []
    var index = 3
    while index < arguments.count {
        if ["--canonical-task", "--runtime-task", "--dispatch"].contains(arguments[index]) {
            index += 2
        } else {
            taskParts.append(arguments[index])
            index += 1
        }
    }
    return taskParts
}

private func runAgentRun(store: LedgerStore, root: URL, arguments: [String]) {
    let role = arguments[2]
    let canonicalTaskID = agentValue(after: "--canonical-task", in: arguments)
    let runtimeTaskID = agentValue(after: "--runtime-task", in: arguments)
    let dispatchID = agentValue(after: "--dispatch", in: arguments)
    let task = parseRunTaskParts(arguments).joined(separator: " ")
    guard !task.isEmpty else { fail("agent run 작업 본문이 필요합니다") }
    let roleStore = RepositoryAgentRoleStore(
        repositoryRoot: RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: root))
    guard (try? roleStore.load(id: role)) != nil else {
        fail("저장소 역할 없음: .agents/roles/\(role).md")
    }
    writeStatus(root: root, label: "\(role) 실행 중", detail: String(task.prefix(60)))
    let identityText = canonicalTaskID.map {
        " canonical task: \($0), runtime task: \(runtimeTaskID ?? "-"), dispatch: \(dispatchID ?? "-")."
    } ?? ""
    let prompt = "\(role) 역할(.agents/roles/\(role).md)을 수행해라. 저장소 AGENTS.md와 작업 범위를 지켜라.\(identityText) 작업: \(task)"
    let code = runEngine(role: role, root: root, prompt: prompt)
    recordRunResult(store: store, root: root, role: role, task: task, code: code,
                    canonicalTaskID: canonicalTaskID, runtimeTaskID: runtimeTaskID, dispatchID: dispatchID)
    clearStatus(root: root)
    exit(code == 0 ? 0 : 1)
}

private func runAgentRoleCommand(
    store: LedgerStore,
    root: URL,
    author: String,
    arguments: [String]
) {
    let roleStore = RepositoryAgentRoleStore(
        repositoryRoot: RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: root))
    let sub = arguments.count >= 3 ? arguments[2] : "list"
    switch sub {
    case "list":
        struct Row: Encodable {
            let id: String
            let displayName: String
            let summary: String
            let engine: String
            let mode: String
            let path: String
        }
        let rows = roleStore.list().map {
            Row(id: $0.id, displayName: $0.displayName, summary: $0.summary,
                engine: $0.engine, mode: $0.mode, path: $0.fileURL.path)
        }
        if arguments.contains("--json") { printJSON(rows) }
        else { rows.forEach { print("\($0.id)\t\($0.engine)\t\($0.summary)") } } // allow:debug

    case "create":
        createAgentRole(store: store, roleStore: roleStore, author: author, arguments: arguments)

    default:
        fail("agent role 하위명령: list [--json] | create <kebab-id> …")
    }
}

private func createAgentRole(
    store: LedgerStore, roleStore: RepositoryAgentRoleStore,
    author: String, arguments: [String]
) {
    guard arguments.count >= 4 else {
        fail("사용법: agent role create <kebab-id> [--name <표시명>] [--summary <설명>] [--engine claude|codex|grok|opencode] [담당범위=stdin]")
    }
    let id = arguments[3]
    let name = agentValue(after: "--name", in: arguments) ?? id
    let summary = agentValue(after: "--summary", in: arguments) ?? "저장소 담당 역할"
    let engine = agentValue(after: "--engine", in: arguments) ?? "codex"
    let responsibility = agentStdinBody()
    guard !responsibility.isEmpty else { fail("담당 범위를 stdin으로 입력하세요") }
    do {
        let definition = try roleStore.makeDefinition(
            id: id, displayName: name, summary: summary,
            engine: engine, responsibilities: responsibility)
        let role = try roleStore.save(id: id, definition: definition)
        let history = store.scan().filter {
            $0.effectiveType == "role-definition" && $0.title == "역할정의: \(id)"
        }
        let previous = store.heads(history).first
        let object = try store.publish(author: author, title: "역할정의: \(id)", type: "role-definition", body: "개정 사유: 저장소 담당 역할 생성\n\n" + definition, extras: LedgerPublishExtras(supersedes: previous?.id, origin: "file://" + role.fileURL.path))
        if arguments.contains("--json") {
            struct Output: Encodable { let id: String; let engine: String; let path: String; let ledgerObjectId: String }
            printJSON(Output(id: role.id, engine: role.engine, path: role.fileURL.path, ledgerObjectId: object.id))
        } else { print(role.id) } // allow:debug
    } catch { fail("역할 생성 실패: \(error)") }
}

/// agent evolve <role> — 사람이 반려한 심사 피드백을 모아 역할(.agents/roles/<role>.md)을
/// 다음 세대로 개정한다. 반려 코멘트를 프롬프트에 주입해 에이전트가 역할 파일을 직접 고치게 하고,
/// agent sync 로 새 role-definition 버전(= 새 세대)을 발행한다. 카르파시식 경험학습의 체화 단계.
public func runEvolve(store: LedgerStore, root: URL, role: String) {
    let objects = store.scan()
    // 이 역할이 낸 정제본(digest)들에 대한 '반려' 심사 + 코멘트를 모은다.
    let digestIDs = Set(objects.filter { $0.author == role }.map { $0.id })
    let rejects = objects.filter { obj in
        obj.effectiveType == "review" && (obj.title ?? "").hasPrefix("심사: 반려")
            && obj.cites.contains { $0.rel == "reviews" && digestIDs.contains($0.id) }
    }.sorted { ($0.published, $0.id) > ($1.published, $1.id) }
    guard !rejects.isEmpty else {
        print("반려된 심사가 없습니다 — 개정할 학습 신호가 아직 없음. (심사대에서 반려하면 쌓입니다)") // allow:debug
        return
    }
    // 최근 반려 코멘트 모음(과도한 길이 방지 위해 최근 12건).
    let feedback = rejects.prefix(12).enumerated().map { i, r in
        let body = r.body.components(separatedBy: "\n---\n").last ?? r.body
        return "\(i + 1). [\(r.title ?? "")] \(body.trimmingCharacters(in: .whitespacesAndNewlines))"
    }.joined(separator: "\n")

    writeStatus(root: root, label: "\(role) 세대 진화", detail: "반려 \(rejects.count)건 반영")
    let prompt = """
    너는 역할 진화 담당이다. 대상 역할 파일: .agents/roles/\(role).md
    아래는 이 역할이 낸 정제본이 사람 심사에서 **반려**된 사유(코멘트)들이다. 같은 지적으로
    다시 반려당하지 않도록 역할 파일을 개정해라 — 지적을 예방하는 구체 지침을 역할에 추가/수정한다.

    ## 반려 피드백 (최근순)
    \(feedback)

    ## 지침 (자동 파이프라인 — 승인 대기 금지)
    - 이건 무인 자동 진화 단계다. **사람 승인을 기다리지 말고 지금 바로** Write/Edit 도구로
      .agents/roles/\(role).md 파일을 실제로 편집해라. "승인해주면 적용하겠다"는 실패로 친다.
    - 전면 재작성 말고, 위 반려 사유를 예방하는 구체 규칙을 역할에 보강/수정한다.
    - 기존 역할의 핵심(원문 왜곡 금지·digests 인용·위키 직접발행 금지·루브릭 자가채점)은 유지한다.
    - 파일을 실제로 저장한 뒤 `agent-wiki agent sync` 를 실행해 새 세대(role-definition)를
      발행한다. (호출측도 마지막에 sync 를 한 번 더 보장하지만, 네가 직접 실행하는 게 정석이다.)
    - run 카드 규약(AGENTS.md)을 지켜라 — run 은 finally 로 닫아라.
    """
    let code = runEngine(role: role, root: root, prompt: prompt)
    // 에이전트가 sync 를 못 했을 수 있으니 한 번 더 보장(변경 없으면 무동작).
    runAgentSync(store: store, root: root)
    clearStatus(root: root)
    exit(code == 0 ? 0 : 1)
}

/// distill <capture-id> — 수집물 하나를 distiller 역할로 정제해 심사대 초안으로.
/// `agent run distiller` 의 사탕발림이지만, 대상 수집물 id 를 프롬프트에 못 박아 준다.
/// distiller 는 위키 객체를 직접 발행하지 않는다 — digests 로 원문을 인용한 정제본만 낸다.
public func runDistill(store: LedgerStore, root: URL, arguments: [String]) {
    guard arguments.count >= 2 else { fail("distill <capture-id> — 수집물 하나를 정제해 심사대로") }
    let target = arguments[1]
    let objects = store.scan()
    guard let capture = objects.first(where: { $0.id == target || $0.id.hasPrefix(target) }) else {
        fail("수집물을 찾을 수 없음: \(target)")
    }
    writeStatus(root: root, label: "distiller 정제 중", detail: String((capture.title ?? "").prefix(60)))
    let prompt = """
    distiller 역할(.agents/roles/distiller.md)을 수행해라. run 카드 규약(AGENTS.md)을 지켜라.
    대상 수집물(원문 근거) id: \(capture.id)
    이 원문을 정제해 digests 로 인용한 정제본 하나를 심사대로 발행해라. 위키 객체(concept/entity/index)는
    직접 만들지 마라 — 확립은 사람 심사 뒤 wiki-maintainer 몫이다. 루브릭 자가채점을 본문 말미에 남겨라.
    """
    let code = runEngine(role: "distiller", root: root, prompt: prompt)
    clearStatus(root: root)
    exit(code == 0 ? 0 : 1)
}

fileprivate func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let src = DispatchSource.makeTimerSource()
    src.schedule(deadline: .now() + seconds)
    src.setEventHandler { process.terminate() }
    src.resume()
    process.waitUntilExit()
    src.cancel()
}

