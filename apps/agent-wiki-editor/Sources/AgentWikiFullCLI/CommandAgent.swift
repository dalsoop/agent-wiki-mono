import Foundation
import KnowledgeBaseWikiCore
import CommandKit
import LocalizationKit
import StateRootKit

// 에이전트 오케스트레이션 — 셸 tick 스크립트를 제품(CLI)으로 흡수한 것.
// launchd 는 이 바이너리를 직접 부른다: agent-wiki tick <이름> / agent run.
// 감독 루프(워치독·재시도·Reflexion)·역할 동기화·distill·tick(checkpoint/librarian/verifier/…).

// 모듈 공유(backup·appcontrol 도 사용)
func nowISO() -> String { LedgerObject.iso.string(from: Date()) }

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

private func writeStatus(root: URL, label: String, detail: String) {
    let payload = "{\"label\":\"\(label)\",\"detail\":\"\(detail)\",\"updatedAt\":\"\(nowISO())\"}"
    do {
        try payload.write(to: statusFile(root: root), atomically: true, encoding: .utf8)
    } catch {
        fputs("warning: writeStatus: \(error.localizedDescription)\n", stderr)
    }
}

private func clearStatus(root: URL) {
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
private func runEngine(role: String, root: URL, prompt basePromptIn: String, logURL: URL? = nil,
                       maxAttempts: Int = 2, timeoutSeconds: Int = 1800) -> Int32 {
    var basePrompt = basePromptIn
    if role != "retrospective" {
        let store = LedgerStore(root: root)
        basePrompt += store.experienceRulesPrompt(store.scan(), forRole: role)
    }
    // T1 작업 사건 — run 시작(pending). run-reaper 는 이 pending 으로 좌초를 판정.
    let log = EventLog(root: root)
    let runEvent = Event(writer: role, subject: role, rel: "역할 실행", level: .run, extras: Event.Extras(outcome: .pending))
    try? log.append(runEvent)

    var lastFailure = ""
    var finalCode: Int32 = 127
    for attempt in 1...max(1, maxAttempts) {
        let attemptPrompt = basePrompt + (lastFailure.isEmpty ? "" :
            "\n\n## 지난 시도 실패 — 원인을 고쳐서 다시 하라 (Reflexion)\n\(lastFailure)\n")
        let (code, timedOut) = spawnEngine(role: role, root: root, prompt: attemptPrompt,
                                           logURL: logURL, runID: runEvent.id, timeoutSeconds: timeoutSeconds)
        let attemptRel = "시도 \(attempt) " + (code == 0 ? "성공" : timedOut ? "타임아웃" : "실패")
        do {
            try log.append(Event(
                writer: role,
                subject: role,
                rel: attemptRel,
                level: .step,
                extras: Event.Extras(
                    parent: runEvent.id,
                    attrs: ["attempt": String(attempt), "exit": String(code)]
                )
            ))
        } catch {
            fputs("warning: agent attempt event: \(error.localizedDescription)\n", stderr)
        }
        finalCode = code
        if code == 0 { break }
        lastFailure = "시도 \(attempt): exit \(code)"
            + (timedOut ? " (타임아웃 \(timeoutSeconds)s 초과 → 강제 종료)" : "")
        if attempt < maxAttempts { print(CLILocalization.format("CommandAgent.print", nowISO(), role, attempt)) }
    }
    do {
        try log.append(Event(
            writer: role,
            subject: role,
            rel: finalCode == 0 ? "성공" : "실패",
            level: .run,
            extras: Event.Extras(
                parent: runEvent.id,
                outcome: finalCode == 0 ? .ok : .fail,
                attrs: ["exit": String(finalCode)]
            )
        ))
    } catch {
        fputs("warning: agent final event: \(error.localizedDescription)\n", stderr)
    }
    return finalCode
}

/// 엔진 프로세스 1회 실행 + 워치독. 반환: (종료코드, 타임아웃여부).
private func spawnEngine(role: String, root: URL, prompt: String, logURL: URL?,
                        runID: String, timeoutSeconds: Int) -> (code: Int32, timedOut: Bool) {
    let arguments = engineArguments(role: role, root: root, prompt: prompt)
    // TODO(commandkit): migrate raw Process() to ProcessCommandRunner — see swiftkit/Documentation/command-kit.md
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
func runAgentSync(store: LedgerStore, root: URL) {
    let roleStore = RepositoryAgentRoleStore(
        repositoryRoot: RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: root))
    let dir = roleStore.rolesDirectory
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil) else { print(CLILocalization.string("CommandAgent.print-2")); return }
    let objects = store.scan()
    var synced = 0
    for url in urls where url.pathExtension == "md" {
        let name = url.deletingPathExtension().lastPathComponent
        guard let fileBody = try? String(contentsOf: url, encoding: .utf8) else { continue }
        let trimmed = fileBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let history = objects
            .filter { $0.effectiveType == "role-definition" && $0.title == "역할정의: \(name)" }
        let head = store.heads(history).first ?? history.sorted { ($0.published, $0.id) > ($1.published, $1.id) }.first
        if let head, roleDefinitionBody(head) == trimmed { continue }  // 변경 없음
        let reason = head == nil ? "파일 신규 감지 (동기화)" : "파일 변경 감지 (외부 편집 동기화)"
        do {
            _ = try store.publish(
                author: "run-reaper", title: CLILocalization.format("CommandAgent.title", name), type: "role-definition",
                body: "개정 사유: \(reason)\n\n" + trimmed,
                supersedes: head?.id, origin: "file://" + url.path)
            print(CLILocalization.format("CommandAgent.print-3", name, reason))
            synced += 1
        } catch { fail("\(error)") }
    }
    if synced == 0 { print(CLILocalization.format("CommandAgent.print-4", nowISO())) }
}

func runAgentCommand(store: LedgerStore, root: URL, author: String, arguments: [String]) {
    if arguments.count >= 2, arguments[1] == "role" {
        runAgentRoleCommand(store: store, root: root, author: author, arguments: arguments)
        return
    }
    if arguments.count >= 2, arguments[1] == "sync" { runAgentSync(store: store, root: root); return }
    if arguments.count >= 3, arguments[1] == "evolve" { runEvolve(store: store, root: root, role: arguments[2]); return }
    // agent run <role> [--canonical-task <id> --runtime-task <id> --dispatch <id>] <작업...>
    guard arguments.count >= 4, arguments[1] == "run" else { fail(usage) }
    let role = arguments[2]
    let canonicalTaskID = agentValue(after: "--canonical-task", in: arguments)
    let runtimeTaskID = agentValue(after: "--runtime-task", in: arguments)
    let dispatchID = agentValue(after: "--dispatch", in: arguments)
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
    let task = taskParts.joined(separator: " ")
    guard !task.isEmpty else { fail("agent run 작업 본문이 필요합니다") }
    let roleStore = RepositoryAgentRoleStore(
        repositoryRoot: RepositoryAgentRoleStore.repositoryRoot(forWorldRoot: root))
    guard (try? roleStore.load(id: role)) != nil else {
        fail("저장소 역할 없음: .agents/roles/\(role).md")
    }
    writeStatus(root: root, label: CLILocalization.format("CommandAgent.label", role), detail: String(task.prefix(60)))
    let identityText = canonicalTaskID.map {
        " canonical task: \($0), runtime task: \(runtimeTaskID ?? "-"), dispatch: \(dispatchID ?? "-")."
    } ?? ""
    let prompt = "\(role) 역할(.agents/roles/\(role).md)을 수행해라. 저장소 AGENTS.md와 작업 범위를 지켜라.\(identityText) 작업: \(task)"
    let code = runEngine(role: role, root: root, prompt: prompt)
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
                    message: CLILocalization.format("CommandAgent.message", String(code)))
        } catch {
            FileHandle.standardError.write(Data("worker failure 기록 실패: \(error)\n".utf8))
        }
    }
    clearStatus(root: root)  // exit 는 defer 를 건너뛴다 — 반드시 명시 정리
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
        else { rows.forEach { print("\($0.id)\t\($0.engine)\t\($0.summary)") } }

    case "create":
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
                id: id,
                displayName: name,
                summary: summary,
                engine: engine,
                responsibilities: responsibility)
            let role = try roleStore.save(id: id, definition: definition)
            let history = store.scan().filter {
                $0.effectiveType == "role-definition" && $0.title == "역할정의: \(id)"
            }
            let previous = store.heads(history).first
            let object = try store.publish(
                author: author,
                title: CLILocalization.format("CommandAgent.title", id),
                type: "role-definition",
                body: "개정 사유: 저장소 담당 역할 생성\n\n" + definition,
                supersedes: previous?.id,
                origin: "file://" + role.fileURL.path)
            if arguments.contains("--json") {
                struct Output: Encodable { let id: String; let engine: String; let path: String; let ledgerObjectId: String }
                printJSON(Output(id: role.id, engine: role.engine, path: role.fileURL.path, ledgerObjectId: object.id))
            } else { print(role.id) }
        } catch { fail("역할 생성 실패: \(error)") }

    default:
        fail("agent role 하위명령: list [--json] | create <kebab-id> …")
    }
}

/// agent evolve <role> — 사람이 반려한 심사 피드백을 모아 역할(.agents/roles/<role>.md)을
/// 다음 세대로 개정한다. 반려 코멘트를 프롬프트에 주입해 에이전트가 역할 파일을 직접 고치게 하고,
/// agent sync 로 새 role-definition 버전(= 새 세대)을 발행한다. 카르파시식 경험학습의 체화 단계.
func runEvolve(store: LedgerStore, root: URL, role: String) {
    let objects = store.scan()
    // 이 역할이 낸 정제본(digest)들에 대한 '반려' 심사 + 코멘트를 모은다.
    let digestIDs = Set(objects.filter { $0.author == role }.map { $0.id })
    let rejects = objects.filter { obj in
        obj.effectiveType == "review" && (obj.title ?? "").hasPrefix("심사: 반려")
            && obj.cites.contains { $0.rel == "reviews" && digestIDs.contains($0.id) }
    }.sorted { ($0.published, $0.id) > ($1.published, $1.id) }
    guard !rejects.isEmpty else {
        print(CLILocalization.string("CommandAgent.print-5"))
        return
    }
    // 최근 반려 코멘트 모음(과도한 길이 방지 위해 최근 12건).
    let feedback = rejects.prefix(12).enumerated().map { i, r in
        let body = r.body.components(separatedBy: "\n---\n").last ?? r.body
        return "\(i + 1). [\(r.title ?? "")] \(body.trimmingCharacters(in: .whitespacesAndNewlines))"
    }.joined(separator: "\n")

    writeStatus(root: root, label: CLILocalization.format("CommandAgent.label-2", role), detail: CLILocalization.format("CommandAgent.detail", rejects.count))
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
func runDistill(store: LedgerStore, root: URL, arguments: [String]) {
    guard arguments.count >= 2 else { fail("distill <capture-id> — 수집물 하나를 정제해 심사대로") }
    let target = arguments[1]
    let objects = store.scan()
    guard let capture = objects.first(where: { $0.id == target || $0.id.hasPrefix(target) }) else {
        fail("수집물을 찾을 수 없음: \(target)")
    }
    writeStatus(root: root, label: CLILocalization.string("CommandAgent.label-3"), detail: String((capture.title ?? "").prefix(60)))
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

func runTick(store: LedgerStore, root: URL, author: String, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    switch arguments[1] {
    case "checkpoint":
        runAgentSync(store: store, root: root)  // 역할 파일 변경을 체크포인트 전에 원장에 포착
        LedgerIndex(root: root).sync(objectsDir: root.appendingPathComponent("objects"))  // 파생 인덱스 최신화
        let objects = store.scan()
        // 파생 그래프도 최신화 — 객체+사건을 순회 store 에 재구성(index 와 같은 틱에서, 둘 다 캐시)
        let events = EventLog(root: root).all()
        LedgerGraph(root: root).rebuild(objects: objects, events: events)
        let last = store.latestCheckpoint(objects)
        let newCount = objects.filter { $0.id > (last?.id ?? "") }.count
        if last == nil || newCount > 0 {
            do {
                let object = try store.publishCheckpoint(author: author)
                print(CLILocalization.format("CommandPublish.print-5", String(object.id.prefix(8)), object.title ?? ""))
                // 사건 발생 — 체크포인트는 기계적 사실이므로 사건 로그에 append(고volume 사건의 첫 생산자).
                // 하트비트(.runs/status)와 별개의 durable 사실 기록이다.
                do {
                    try EventLog(root: root).append(Event(
                        writer: "tick-checkpoint",
                        subject: object.id,
                        rel: "체크포인트",
                        extras: Event.Extras(attrs: ["objects": String(objects.count)])
                    ))
                } catch {
                    fputs("warning: tick-checkpoint event: \(error.localizedDescription)\n", stderr)
                }
            } catch { fail("\(error)") }
        } else {
            print(CLILocalization.format("CommandAgent.print-7", nowISO()))
        }

    case "librarian":
        let cut = Date().addingTimeInterval(-24 * 3600)
        let recent = store.scan().filter { object in
            object.published > cut
                && !["checkpoint", "concept", "entity", "index"].contains(object.effectiveType ?? "")
        }.count
        // 자율성의 마지막 고리 — 미분류 유입 자동 분류(분류 스탬프 없는 근거)
        let all = store.scan()
        let classification = LedgerClassification(objects: all)
        let unclassified = store.heads(all).filter {
            $0.effectiveType == "evidence" && $0.retracts == nil
                && classification.domain[$0.id] == nil
        }.prefix(20)
        if !unclassified.isEmpty {
            writeStatus(root: root, label: CLILocalization.string("CommandAgent.label-4"),
                        detail: CLILocalization.format("CommandAgent.detail-2", unclassified.count))
            let ids = unclassified.map(\.id).joined(separator: "\n")
            runEngine(role: "taxonomy-drafter", root: root, prompt: """
                taxonomy-drafter 역할(.agents/roles/taxonomy-drafter.md)을 수행해라. 아래 미분류 근거를 \
                show 로 읽고 각각 '분류: <제목요약>' 스탬프(rel=screens)를 발행하라 — 본문에 domain/kind/knowledge \
                세 줄 + 판정 근거 2문장. 확신 없으면 건너뛰고 사유 기록. run 카드 규약 준수.

                \(ids)
                """)
        }
        guard recent > 0 else { print(CLILocalization.format("CommandAgent.print-7", nowISO())); clearStatus(root: root); return }
        print(CLILocalization.format("CommandAgent.print-8", nowISO(), recent))
        writeStatus(root: root, label: CLILocalization.string("CommandAgent.label-5"), detail: CLILocalization.format("CommandAgent.detail-3", recent))
        runEngine(role: "wiki-maintainer", root: root, prompt: """
            wiki-maintainer 역할을 수행해라(.agents/roles/wiki-maintainer.md). 최근 24시간 발행분을 훑고: \
            ① 영향받는 개념 페이지를 개정(역방향 갱신) ② 없는 주제면 새 개념 페이지 발행 ③ 색인 개정. \
            전부 근거 cite, 인식론 표기 준수. 발행·개정하는 모든 위키 페이지에 --tag 를 단다 \
            (도메인 1개 + 주제 태그 1~3개, kebab-case). 태그 없는 기존 페이지를 개정할 때도 태그를 소급한다. \
            미응답 토론(이의·질문·수정요청) 최우선. 끝나면 발행 id 목록만 보고.
            """)
        writeStatus(root: root, label: CLILocalization.string("CommandAgent.label-6"), detail: CLILocalization.string("CommandAgent.detail-4"))
        runEngine(role: "consistency-checker", root: root, prompt: """
            consistency-checker 역할(.agents/roles/consistency-checker.md)을 수행해라. 오늘 개정된 위키 페이지와 \
            그 인용 근거들 사이의 상충(모순 주장·설정 충돌)을 찾아 contradicts 로 표면화하라. run 카드 규약을 지켜라. \
            상충 없으면 '상충 없음' 요약만 발행.
            """)
        clearStatus(root: root)

    case "verifier":
        let objects = store.scan()
        // 재방문 가능한(origin http) 지식 head 를 신선도 낮은 순으로 정렬
        let ranked = store.heads(objects)
            .filter { !$0.isProcess && $0.retracts == nil && ($0.origin?.hasPrefix("http") ?? false) }
            .map { ($0, store.strength(objects, of: $0)) }
            .sorted { $0.1.freshness < $1.1.freshness }
        guard !ranked.isEmpty else { print(CLILocalization.format("CommandAgent.print-9", nowISO())); return }
        // 순환 선정 — 최근 7일 내 "재검증 선정" 사건이 있는 근거는 뒤로 미룬다. md 는 성공한
        // 재검증만 아는데, 사건은 "선정했으나 LLM 이 못 끝낸 것"까지 알아서 매주 같은 12개가
        // 다시 뽑히는 걸 막고 커버리지를 넓힌다. (사건층이 실제로 선정 결정을 바꾸는 소비자)
        let eventLog = EventLog(root: root)
        let recentlySelected = eventLog.subjectsWithEvent(
            rel: "재검증 선정", since: Date().addingTimeInterval(-7 * 86400))
        let rankedIDs = ranked.map(\.0.id)
        let selectedIDs = EventLog.rotatedTargets(
            ranked: rankedIDs, recentlySelected: recentlySelected, limit: 12)
        let byID = Dictionary(uniqueKeysWithValues: ranked.map { ($0.0.id, $0.0) })
        let candidates = selectedIDs.compactMap { byID[$0] }
        // 선정 사건 발행 — 이 선정 자체가 다음 회차 순환의 근거가 된다.
        for id in selectedIDs {
            try? eventLog.append(Event(writer: "verifier", subject: id, rel: "재검증 선정", level: .step))
        }
        let skipped = recentlySelected.intersection(Set(rankedIDs)).count
        if skipped > 0 { print(CLILocalization.format("CommandAgent.print-10", skipped)) }
        // --dry: LLM 엔진 없이 선정 결과만 출력(+선정 사건은 발행). 순환을 눈으로 확인할 때.
        if arguments.contains("--dry") {
            print(CLILocalization.format("CommandAgent.print-11", candidates.count, ranked.count))
            for c in candidates { print("  \(c.id.prefix(8))  \((c.title ?? "").prefix(50))") }
            return
        }
        let targets = candidates.map(\.id).joined(separator: "\n")
        let history = root.appendingPathComponent(".runs/history")
        do {
            try FileManager.default.createDirectory(at: history, withIntermediateDirectories: true)
        } catch {
            fputs("warning: createDirectory \(history.path): \(error.localizedDescription)\n", stderr)
        }
        let stamp = nowISO().replacingOccurrences(of: ":", with: "").prefix(15)
        let logURL = history.appendingPathComponent("verifier-\(stamp).log")
        writeStatus(root: root, label: CLILocalization.string("CommandAgent.label-7"), detail: CLILocalization.format("CommandAgent.detail-5", candidates.count))
        runEngine(role: "verifier", root: root, prompt: """
            너는 verifier 다(.agents/roles/verifier.md). run 카드 규약(AGENTS.md)을 지켜라: \
            ① 'run: 주간 재검증' 발행(batch 발급) ② 아래 각 근거를 show 로 읽고 origin 이 http 면 재방문해 대조 — \
            맞으면 supports(재현), 틀렸으면 contradicts(반박) 를 사유와 함께 발행. 재방문 불가면 건너뛰고 사유 기록. \
            ③ 종료 요약 발행(확신도/어려웠던 점/배운 점).

            대상:
            \(targets)
            """, logURL: logURL)
        clearStatus(root: root)
        print(CLILocalization.format("CommandAgent.print-12", nowISO(), logURL.path))

    case "retrospective":
        // 회고·학습 tick — 카르파시식 반영 스텝. 사건 로그를 씹어 경험칙을 발행하게 기동.
        let log = EventLog(root: root)
        guard !log.tail(20).isEmpty else { print(CLILocalization.format("CommandAgent.print-13", nowISO())); return }
        writeStatus(root: root, label: CLILocalization.string("CommandAgent.label-8"), detail: CLILocalization.string("CommandAgent.detail-6"))
        runEngine(role: "retrospective", root: root, prompt: """
            retrospective 역할(.agents/roles/retrospective.md)을 수행하라. `event tree`·`event tail`·`learn` 으로 \
            최근 작업 성공/실패와 지표를 읽고, 성공↔실패 궤적을 대조해 경험칙을 뽑아 '회고: <교훈>' 으로 \
            발행하라(관찰·경험칙·적용대상, 근거 cite, 인식론 표기). 반복 실패가 뚜렷하면 해당 역할 정의 \
            수정요청도 발행하라. 자기강화 오류 주의: 표본 얇으면 〔불확실〕.
            """)
        clearStatus(root: root)

    case "reaper":
        // 좌초 run 수습 — 순수 로직, LLM 불요. 하트비트 살아있으면 개입 금지.
        let statusDir = root.appendingPathComponent(".runs/status")
        let alive = ((try? FileManager.default.contentsOfDirectory(atPath: statusDir.path)) ?? [])
            .contains { $0.hasSuffix(".json") }
        let legacy = FileManager.default.fileExists(atPath: root.appendingPathComponent(".runs/status.json").path)
        guard !alive && !legacy else { print(CLILocalization.string("CommandAgent.print-14")); return }
        let objects = store.scan()
        var byBatch: [String: [LedgerObject]] = [:]
        for object in objects {
            if let batch = object.batch { byBatch[batch, default: []].append(object) }
        }
        var reaped = 0
        for (batch, members) in byBatch {
            let runs = members.filter { $0.effectiveType == "run" }
            guard runs.count == 1, let start = runs.first else { continue }
            guard let last = members.map(\.published).max(),
                  Date().timeIntervalSince(last) > 1800 else { continue }
            let title = (start.title ?? "run:").replacingOccurrences(of: "run: ", with: "")
            let body = """
            수습: 이 run 은 종료 기록 없이 멈췄다 — 마지막 발행 \(LedgerObject.iso.string(from: last)), 하트비트 없음.
            run-reaper 가 사슬을 닫는다. 산출물은 batch \(batch) 그대로 유효하며, 원인은 로그
            (.runs/history 또는 대화기록) 참조. 재개가 필요하면 같은 작업을 새 run 으로 시작하라.
            """
            do {
                let object = try store.publish(
                    author: "run-reaper", title: CLILocalization.format("CommandAgent.title-2", title), type: "run",
                    body: body, cites: [.init(id: start.id, rel: "cites")], batch: batch)
                print(CLILocalization.format("CommandAgent.print-15", String(object.id.prefix(8)), String(title.prefix(40))))
                reaped += 1
            } catch { fail("\(error)") }
        }
        // 사건 로그 기반 좌초 감지 — level=run·pending 이고 30분+ 완료 없는 작업을 닫는다(fail).
        // 파일 뒤짐(.runs/history) 대신 사건 질의. append-only 라 새 fail 사건으로 사슬을 닫는다.
        let eventLog = EventLog(root: root)
        let stranded = eventLog.openRuns(olderThan: Date().addingTimeInterval(-1800))
        for run in stranded {
            do {
                try eventLog.append(Event(
                    writer: "run-reaper",
                    subject: run.subject,
                    rel: "좌초 수습",
                    level: .run,
                    extras: Event.Extras(
                        parent: run.id,
                        outcome: .fail,
                        attrs: ["reaped": "true"]
                    )
                ))
            } catch {
                fputs("warning: run-reaper event: \(error.localizedDescription)\n", stderr)
            }
            print(CLILocalization.format("CommandAgent.print-16", run.subject, run.rel, LedgerObject.iso.string(from: run.occurred)))
            reaped += 1
        }
        if reaped == 0 { print(CLILocalization.format("CommandAgent.print-17", nowISO())) }

    default: fail(usage)
    }
}

/// Process 워치독 — 상대 hang 시 호출측 영구 대기 방지 (MR !547).

