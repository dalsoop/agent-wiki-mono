import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// 작업그래프 — 원장 위에 얹는 검증 가능한 TODO/위임 층.
/// 예약어를 안 늘리고(SPEC 제3조) type + cite rel 로만 표현한다:
///   - task     : 할 일 (본문 = 무엇)
///   - handoff  : task 를 cite(delegates) + 대상 에이전트 명시 = 위임 기록
///   - done     : task 를 cite(completes) + 결과 = 완료 기록(author = 실제 한 에이전트)
/// 하청의 하청 = task 를 cite 하는 하위 task 의 사슬(= 인용 경로 `path` 로 추적).
func runTask(
    store: LedgerStore,
    author: String,
    repository: RepositoryIdentity? = nil,
    arguments: [String]
) {
    let sub = arguments.count >= 2 ? arguments[1] : "list"
    let service = RepositoryTaskService(store: store, repository: repository, author: author)
    switch sub {
    case "new":
        // task new "<제목>" [본문 = stdin]
        guard arguments.count >= 3 else { fail("사용법: task new \"<제목>\" [본문=stdin]") }
        if CLIArgv.isHelpToken(arguments[2]) {
            print(CLILocalization.string("CommandTask.print"))
            return
        }
        do { print(try service.createTask(title: arguments[2], body: stdinBody()).id) }
        catch { fail("task 생성 실패: \(error)") }

    case "handoff":
        // task handoff <task접두어> --to <에이전트> [메모 = stdin]
        guard arguments.count >= 3 else { fail("사용법: task handoff <task> --to <에이전트> [메모=stdin]") }
        guard let to = value(after: "--to", in: arguments) else { fail("--to <에이전트> 필요") }
        do { print(try service.handoff(taskID: arguments[2], assignee: to, note: stdinBody()).id) }
        catch { fail("task 위임 실패: \(error)") }

    case "bind":
        guard arguments.count >= 3 else {
            fail("사용법: task bind <task> --runtime-task <id> --dispatch <id> [--knowledge <id[,id...]>] [--rule <text>] [--json]")
        }
        guard let runtimeTaskId = value(after: "--runtime-task", in: arguments),
              let dispatchId = value(after: "--dispatch", in: arguments)
        else { fail("--runtime-task <id>와 --dispatch <id>가 필요합니다") }
        let knowledgeIDs = values(after: "--knowledge", in: arguments)
            .flatMap { $0.split(separator: ",").map(String.init) }
        let rules = values(after: "--rule", in: arguments)
        do {
            let result = try service.bind(
                taskID: arguments[2],
                runtimeTaskID: runtimeTaskId,
                dispatchID: dispatchId,
                knowledgeObjectIDs: knowledgeIDs,
                rules: rules)
            if arguments.contains("--json") {
                struct Output: Encodable { let bindingObjectId: String; let binding: RepositoryAgentTaskBinding }
                printJSON(Output(bindingObjectId: result.object.id, binding: result.binding))
            } else { print(result.object.id) }
        } catch { fail("binding 실패: \(error)") }

    case "verify":
        guard arguments.count >= 3 else {
            fail("사용법: task verify <task> --checker <id> --outcome verified|rejected [--json]")
        }
        let checker = value(after: "--checker", in: arguments) ?? author
        guard let outcomeText = value(after: "--outcome", in: arguments),
              let outcome = RepositoryAgentVerificationReceipt.Outcome(rawValue: outcomeText)
        else { fail("--outcome verified|rejected 필요") }
        do {
            let result = try service.verify(taskID: arguments[2], checker: checker, outcome: outcome)
            if arguments.contains("--json") {
                struct Output: Encodable { let receiptObjectId: String; let receipt: RepositoryAgentVerificationReceipt }
                printJSON(Output(receiptObjectId: result.object.id, receipt: result.receipt))
            } else { print(result.object.id) }
        } catch { fail("verification receipt 실패: \(error)") }

    case "adapter":
        let data: Data
        if let path = value(after: "--file", in: arguments) {
            do { data = try Data(contentsOf: URL(fileURLWithPath: path)) }
            catch { fail("adapter JSON 파일 읽기 실패: \(error)") }
        } else {
            guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else {
                fail("사용법: task adapter [--file <event.json>] --json (또는 JSON stdin)")
            }
            data = FileHandle.standardInput.readDataToEndOfFile()
        }
        do {
            let event = try RepositoryAgentAdapterEvent.decode(data: data)
            let task = resolve(store, event.canonicalTaskId)
            guard task.effectiveType == "task" else { fail("adapter canonicalTaskId 대상은 task여야 합니다") }
            let objects = store.scan()
            switch event.event {
            case .task, .dispatch:
                guard repository != nil else {
                    fail("adapter task/dispatch는 Git remote가 있는 repo .wiki에서만 가능합니다")
                }
                let knowledgeIDs = event.knowledgeObjectIds.map { resolve(store, $0).id }
                let snapshot = RepositoryAgentOrchestration.knowledgeSnapshotHash(
                    knowledgeObjectIds: knowledgeIDs, objects: objects)
                if let supplied = event.knowledgeSnapshotHash, supplied != snapshot {
                    fail("adapter knowledgeSnapshotHash가 현재 lineage snapshot과 다릅니다")
                }
                let binding = try RepositoryAgentTaskBinding(
                    canonicalTaskId: task.id,
                    runtimeTaskId: event.runtimeTaskId,
                    dispatchId: event.dispatchId,
                    knowledgeObjectIds: knowledgeIDs,
                    knowledgeSnapshotHash: snapshot,
                    sourceCommit: event.sourceCommit ?? "",
                    rulesCapsule: event.rulesCapsule,
                    boundAt: event.occurredAt,
                    knowledgeCapturedAt: event.occurredAt)
                let previous = RepositoryAgentOrchestration.activeBinding(
                    canonicalTaskId: task.id, objects: objects)?.object
                let object = try store.publish(
                    author: author,
                    title: "Orca \(event.event.rawValue): \(task.title ?? String(task.id.prefix(8)))",
                    type: RepositoryAgentTaskBinding.objectType,
                    body: try binding.json(),
                    cites: [.init(id: task.id, rel: RepositoryAgentOrchestration.bindsRelation)]
                        + knowledgeIDs.map { .init(id: $0, rel: RepositoryAgentOrchestration.contextRelation) },
                    supersedes: previous?.id,
                    now: event.occurredAt)
                struct Output: Encodable {
                    let schemaVersion: String
                    let event: RepositoryAgentAdapterEvent.Kind
                    let bindingObjectId: String
                    let binding: RepositoryAgentTaskBinding
                }
                printJSON(Output(
                    schemaVersion: RepositoryAgentAdapterEvent.schemaVersion,
                    event: event.event, bindingObjectId: object.id, binding: binding))

            case .workerDone:
                guard let active = RepositoryAgentOrchestration.activeBinding(
                    canonicalTaskId: task.id, objects: objects),
                      active.binding.runtimeTaskId == event.runtimeTaskId,
                      active.binding.dispatchId == event.dispatchId
                else { fail("worker_done runtimeTaskId/dispatchId가 active binding과 다릅니다") }
                let receipt = try RepositoryAgentWorkerDoneReceipt(
                    event: event, bindingObjectId: active.object.id)
                let object = try store.publish(
                    author: event.worker ?? author,
                    title: "Worker done (verification pending): \(task.title ?? String(task.id.prefix(8)))",
                    type: RepositoryAgentWorkerDoneReceipt.objectType,
                    body: try receipt.json(),
                    cites: [
                        .init(id: task.id, rel: RepositoryAgentOrchestration.reportsWorkerDoneRelation),
                        .init(id: active.object.id, rel: RepositoryAgentOrchestration.reportsBindingRelation),
                    ],
                    now: event.occurredAt)
                let projection = RepositoryAgentOrchestration.projection(
                    task: task, objects: store.scan(), currentSourceCommit: repository?.sourceCommit)
                struct Output: Encodable {
                    let schemaVersion: String
                    let workerDoneObjectId: String
                    let state: RepositoryAgentTaskProjection.State
                    let completionAllowed: Bool
                }
                printJSON(Output(
                    schemaVersion: RepositoryAgentWorkerDoneReceipt.schemaVersion,
                    workerDoneObjectId: object.id, state: projection.state,
                    completionAllowed: false))

            case .checker:
                guard let active = RepositoryAgentOrchestration.activeBinding(
                    canonicalTaskId: task.id, objects: objects),
                      active.binding.runtimeTaskId == event.runtimeTaskId,
                      active.binding.dispatchId == event.dispatchId,
                      event.bindingObjectId == nil || event.bindingObjectId == active.object.id
                else { fail("checker event identity가 active binding과 다릅니다") }
                let receipt = try RepositoryAgentVerificationReceipt(
                    canonicalTaskId: task.id,
                    runtimeTaskId: active.binding.runtimeTaskId,
                    dispatchId: active.binding.dispatchId,
                    bindingObjectId: active.object.id,
                    knowledgeSnapshotHash: active.binding.knowledgeSnapshotHash,
                    sourceCommit: active.binding.sourceCommit,
                    checker: event.checker ?? author,
                    outcome: event.outcome ?? .rejected,
                    checkedAt: event.occurredAt)
                let object = try store.publish(
                    author: receipt.checker,
                    title: "Checker \(receipt.outcome.rawValue): \(task.title ?? String(task.id.prefix(8)))",
                    type: RepositoryAgentVerificationReceipt.objectType,
                    body: try receipt.json(),
                    cites: [
                        .init(id: task.id, rel: RepositoryAgentOrchestration.verifiesRelation),
                        .init(id: active.object.id, rel: RepositoryAgentOrchestration.verifiesBindingRelation),
                    ],
                    now: event.occurredAt)
                struct Output: Encodable {
                    let schemaVersion: String
                    let verificationReceiptObjectId: String
                    let outcome: RepositoryAgentVerificationReceipt.Outcome
                    let permitsDone: Bool
                }
                printJSON(Output(
                    schemaVersion: RepositoryAgentVerificationReceipt.schemaVersion,
                    verificationReceiptObjectId: object.id, outcome: receipt.outcome,
                    permitsDone: receipt.outcome == .verified))
            }
        } catch { fail("adapter 실패: \(error)") }

    case "capsule", "context":
        guard arguments.count >= 3 else {
            fail("사용법: task \(sub) <task> --json")
        }
        let task = resolve(store, arguments[2])
        let projection = RepositoryAgentOrchestration.projection(
            task: task, objects: store.scan(), currentSourceCommit: repository?.sourceCommit)
        printJSON(RepositoryAgentCapsule(canonicalTaskId: task.id, projection: projection))

    case "done":
        // Write-time fail-closed: receipt validation happens before any append.
        guard arguments.count >= 3 else { fail("사용법: task done <task> --verification <receipt-id> [결과=stdin]") }
        guard let receiptPrefix = value(after: "--verification", in: arguments) else {
            fail("task done은 --verification <verified checker receipt>가 필요합니다")
        }
        do {
            print(try service.complete(
                taskID: arguments[2],
                verificationReceiptID: receiptPrefix,
                result: stdinBody()).id)
        } catch { fail("task done 거부: \(error)") }

    case "knowledge-candidate":
        guard arguments.count >= 4 else {
            fail("사용법: task knowledge-candidate <task> \"<제목>\" [본문=stdin]")
        }
        do {
            print(try service.publishKnowledgeCandidate(
                taskID: arguments[2],
                title: arguments[3],
                body: stdinBody()).id)
        } catch { fail("노하우 후보 발행 실패: \(error)") }

    case "list":
        let graph = LedgerTaskGraph(
            objects: store.scan(), currentSourceCommit: repository?.sourceCommit)
        let openOnly = arguments.contains("--open")
        if arguments.contains("--json") {
            let contract = RepositoryTaskListContract(graph: graph, repoId: repository?.repoId)
            if openOnly {
                let items = contract.summary.items.filter { $0.status != .completed }
                let filtered = RepositoryTaskSummary(
                    total: items.count,
                    open: items.filter { $0.status == .open }.count,
                    delegated: items.filter { $0.status == .delegated }.count,
                    completed: 0,
                    items: items)
                struct OpenTaskList: Encodable {
                    let schemaVersion: String
                    let generatedAt: Date
                    let repoId: String?
                    let sourceUpdatedAt: Date?
                    let summary: RepositoryTaskSummary
                }
                printJSON(OpenTaskList(
                    schemaVersion: contract.schemaVersion,
                    generatedAt: contract.generatedAt,
                    repoId: contract.repoId,
                    sourceUpdatedAt: contract.sourceUpdatedAt,
                    summary: filtered))
            } else {
                printJSON(contract)
            }
            return
        }
        for task in graph.tasks {
            let isDone = graph.isDone(task.id)
            if openOnly && isDone { continue }
            let mark = isDone ? "✓" : "○"
            let who = graph.assignee[task.id].map { " → \($0)" } ?? ""
            let gate = graph.orchestration[task.id]?.state.rawValue ?? "unbound"
        print(CLILocalization.format("CommandTask.print-2", mark, String(task.id.prefix(8)), task.title ?? CLILocalization.string("cli.no-title"), who, task.author, gate))
        }
        if !openOnly {
            print(CLILocalization.format("CommandTask.print-3", graph.open.count, graph.tasks.count))
        }

    case "chain":
        // 이 task 를 둘러싼 위임·완료 사슬 — task ← handoff(delegates) ← done(completes),
        // 그리고 이 task 를 부모로 cite 하는 하위 task(하청). 재귀로 하청의 하청까지.
        guard arguments.count >= 3 else { fail("사용법: task chain <task>") }
        let objects = store.scan()
        let root = resolve(store, arguments[2])
        printChain(root, objects: objects, depth: 0, seen: [])

    default:
        fail(
            "task 하위명령: adapter | capsule|context | new | handoff | bind | verify | "
                + "done --verification <receipt> | knowledge-candidate | list [--open] [--json] | chain <id>"
        )
    }
}

// MARK: - 파생·헬퍼

/// 위임·완료·하청 사슬을 트리로 출력(재귀). cycle 방어(seen).
private func printChain(_ object: LedgerObject, objects: [LedgerObject], depth: Int, seen: Set<String>) {
    let indent = String(repeating: "  ", count: depth)
    let type = object.effectiveType ?? "-"
    print("\(indent)\(type == "task" ? "○" : "·") [\(type)] \(object.id.prefix(8))  \(object.title ?? "")  — \(object.author)")
    guard depth < 20, !seen.contains(object.id) else { return }
    let next = seen.union([object.id])
    // 이 객체를 cite 하는 것들(위임·완료·하위 task) = 사슬의 다음 마디.
    let children = objects.filter { child in child.cites.contains { $0.id == object.id } }
        .sorted { ($0.published, $0.id) < ($1.published, $1.id) }
    for child in children { printChain(child, objects: objects, depth: depth + 1, seen: next) }
}

private func publishTask(_ store: LedgerStore, author: String, title: String, type: String,
                         body: String, cites: [LedgerObject.Cite]) {
    do {
        let object = try store.publish(author: author, title: title, type: type, body: body, cites: cites)
        print(object.id)
    } catch { fail("\(error)") }
}

private func stdinBody() -> String {
    // 파이프/리다이렉트로 본문이 들어오면 읽고, tty(대화형)면 빈 본문.
    guard isatty(FileHandle.standardInput.fileDescriptor) == 0 else { return "" }
    return (String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func value(after flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), arguments.count > index + 1 else { return nil }
    return arguments[index + 1]
}

private func values(after flag: String, in arguments: [String]) -> [String] {
    arguments.indices.compactMap { index in
        guard arguments[index] == flag, arguments.count > index + 1 else { return nil }
        return arguments[index + 1]
    }
}
