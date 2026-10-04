import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// dream — 드리밍. 본체는 `LawDreamService`(적재 → 재료 → AI 제안 → 안전 검사 → 묶음 공포 → 목차 → 보고 → 동기화 → R2 요약).
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `dream run` · `dream status` · `dream resume`.
// 근거: docs/business-rules.md "드리밍", docs/security.md agent-law 격리 표(드리밍 기기만 `dream run`, `dream resume` 은 사람만).
// 쓰기 게이트(기기 키 미등록 거부)는 명령 표면이 먼저 판정한다. 예약 실행(LaunchAgent 라벨)은 24시간·새 세션·정지 조건을 본다.

let dreamUsage = """
사용법: dream run [--scheduled] [--json]  (드리밍 기기에서만. --scheduled 는 예약 틱이 붙이며 24시간·새 세션·정지 조건을 본다)
       dream status [--json]
       dream resume [--json]   (사람 작성자만 — 원상회복으로 멈춘 자동 드리밍을 다시 켠다)
"""

public func runDream(context: LawCommandContext, arguments: [String]) {
    guard arguments.count >= 2 else { usageFail(dreamUsage) }
    guard context.isLedgerThree else { usageFail("dream 은 ledger 3 원장 전용") }
    let options = LawOptions.parse(
        arguments, skip: 2, valued: [], flags: ["--json", "-j", LawDreamTrigger.scheduledFlag], usage: dreamUsage)
    guard options.positionals.isEmpty else { usageFail(dreamUsage) }
    let asJSON = options.has("--json")

    switch arguments[1] {
    case "run": dreamRun(context: context, asJSON: asJSON, scheduled: options.has(LawDreamTrigger.scheduledFlag))
    case "status": dreamStatus(context: context, asJSON: asJSON)
    case "resume": dreamResume(context: context, asJSON: asJSON)
    default: usageFail(dreamUsage)
    }
}

/// 실제 R2·적재·동기화를 단 서비스. R2 키가 없으면 nil 저장소(실행은 거부된다).
func standardDreamService(context: LawCommandContext) -> (LawDreamService, String?) {
    var storeError: String?
    var objectStore: (any LawObjectStore)?
    do {
        objectStore = try LawR2Client.standard(file: context.file)
    } catch {
        storeError = "\(error)"
    }
    let file = context.file
    let catalog = context.catalog
    let device = file.currentDevice ?? ""
    let archiveStore = objectStore
    let service = LawDreamService(
        file: file, catalog: catalog, objectStore: objectStore,
        stateStore: LawDreamStateStore(directory: LawDreamStateStore.standardDirectory),
        archive: {
            try LawArchiveRunner(
                device: device, file: file, source: LawAgentSessionSource(), registry: .standard,
                stateDirectory: LawArchiveStateStore.standardDirectory, store: archiveStore
            ).run(dryRun: false)
        },
        finish: { dreamFinishSync(file: file, catalog: catalog, objectStore: archiveStore) })
    return (service, storeError)
}

/// 드리밍 끝 동기화 — git(`LawGitSync`), 원장마다 가림 기록에 따른 로컬 삭제(`LawRedactionSweep`)와 증거물(`LawExhibitSync`).
/// `sync` 와 같은 순서다. 결과 문구만 돌려준다.
func dreamFinishSync(file: BoundLedgerFile, catalog: WorldBindingCatalog, objectStore: (any LawObjectStore)?) -> [String] {
    var messages: [String] = []
    let roots = catalog.worlds.filter { catalog.isLedgerThree($0.name) && $0.key != nil && !catalog.isArchived($0.name) }
    guard let first = roots.first(where: { FileManager.default.fileExists(atPath: $0.rootPath) }) else {
        return ["동기화할 원장 없음"]
    }
    switch LawGitSync(ledgerRoot: URL(fileURLWithPath: first.rootPath)).sync() {
    case .success(let outcome):
        messages.append("git: 커밋 대기 \(outcome.committedPending), 받아온 기록 \(outcome.received), push \(outcome.pushed ? "완료" : "실패")")
    case .failure(let error):
        messages.append("git 동기화 실패: \(error.description)")
    }
    for world in roots where FileManager.default.fileExists(atPath: world.rootPath) {
        guard let key = world.key else { continue }
        let store = LawStore(root: URL(fileURLWithPath: world.rootPath))
        let deleted = LawRedactionSweep.applyLocalDeletions(store: store, ledgerKey: key)
        if !deleted.isEmpty { messages.append("가림 기록에 따른 로컬 삭제 \(world.name): \(deleted.count)") }
        guard let objectStore else { continue }
        let outcome = LawExhibitSync.sync(store: store, ledgerKey: key, objectStore: objectStore)
        messages.append("증거물 \(world.name): 올림 \(outcome.uploaded.count) 받음 \(outcome.downloaded.count) 실패 \(outcome.failed.count)")
    }
    if objectStore == nil { messages.append("증거물 동기화 건너뜀: R2 없음") }
    return messages
}

private func dreamRun(context: LawCommandContext, asJSON: Bool, scheduled: Bool = false) {
    let (service, storeError) = standardDreamService(context: context)
    let trigger = LawDreamTrigger.detect(environment: context.environment, scheduledFlag: scheduled)
    do {
        try service.checkDevice()
    } catch {
        // 예약 틱은 모든 기기에 등록되므로, 드리밍 기기가 아닌 곳에서는 조용히 성공으로 끝낸다(수동 실행은 거부 1).
        if trigger == .scheduled {
            if asJSON {
                struct Envelope: Encodable { let ok: Bool; let result: LawDreamOutcome }
                printJSON(Envelope(ok: true, result: LawDreamOutcome(trigger: .scheduled, skipped: "\(error)")))
            }
            exit(0)
        }
        fail("\(error)")
    }
    if let storeError, service.objectStore == nil { fail("드리밍에 R2 가 필요함: \(storeError)") }
    let outcome: LawDreamOutcome
    do {
        outcome = try service.run(trigger: trigger)
    } catch {
        fail("\(error)")
    }
    if asJSON {
        struct Envelope: Encodable { let ok: Bool; let result: LawDreamOutcome }
        printJSON(Envelope(ok: outcome.ok, result: outcome))
    } else {
        printDreamOutcome(outcome)
    }
    if !outcome.ok { exit(1) }
}

func printDreamOutcome(_ outcome: LawDreamOutcome) {
    if let skipped = outcome.skipped {
        print("드리밍 건너뜀(\(outcome.trigger.rawValue)): \(skipped)") // allow:debug — 명령 결과 출력
        return
    }
    print("드리밍 \(outcome.run ?? "")  묶음 \(outcome.batch ?? "")  (\(outcome.trigger.rawValue))") // allow:debug
    if let archive = outcome.archive {
        print("적재: 조각 \(archive.chunks) 발화 \(archive.utterances) unassigned \(archive.unassigned.values.reduce(0, +)) 실패 \(archive.failures)") // allow:debug
    }
    if let error = outcome.archiveError { print("적재 실패: \(error)") } // allow:debug
    for ledger in outcome.ledgers {
        let m = ledger.materials
        var line = "\(ledger.world): 조각 \(m.chunks) 발화 \(m.utterances) 전신 \(m.predecessors.count)"
        line += ledger.active ? "  적용 \(ledger.applied.count) 버림 \(ledger.discarded.count) 미룸 \(ledger.deferred) 경보 \(ledger.alerts.count) 이관 \(ledger.migrations)" : "  (정리 안 함)"
        print(line) // allow:debug
        for item in ledger.applied {
            print("  \(item.kind) \(item.ids.joined(separator: " "))\(item.note.map { "  (\($0))" } ?? "")") // allow:debug
        }
        for item in ledger.discarded { print("  버림 \(item.proposal): \(item.reason)") } // allow:debug
        for alert in ledger.alerts { print("  경보: \(alert)") } // allow:debug
        if let contents = ledger.contents { print("  목차 \(contents)") } // allow:debug
        if let report = ledger.report { print("  보고 \(report)") } // allow:debug
        if let error = ledger.aiError { print("  AI 응답 오류(아무것도 공포하지 않음): \(error)") } // allow:debug
        if let error = ledger.materialError { print("  \(error)") } // allow:debug
    }
    for message in outcome.sync { print("동기화 \(message)") } // allow:debug
    for key in outcome.summaries { print("요약 \(key)") } // allow:debug
    for failure in outcome.failures { print("실패 \(failure)") } // allow:debug
}

private func dreamStatus(context: LawCommandContext, asJSON: Bool) {
    let service = LawDreamService(
        file: context.file, catalog: context.catalog, objectStore: nil,
        stateStore: LawDreamStateStore(directory: LawDreamStateStore.standardDirectory))
    let status = service.status()
    if asJSON {
        struct Envelope: Encodable { let ok: Bool; let result: LawDreamStatus }
        printJSON(Envelope(ok: true, result: status))
        return
    }
    print("드리밍 기기: \(status.dreamDevice ?? "미지정")  이 기기: \(status.currentDevice ?? "미등록")\(status.isDreamDevice ? " (드리밍 기기)" : "")") // allow:debug
    print("실행 도구: \(status.runner)") // allow:debug
    print("마지막 실행: \(status.lastRun ?? "없음")\(status.lastRunAt.map { " \($0)" } ?? "")") // allow:debug
    print("다음 예정: \(status.nextDue ?? "다음 예약 실행")") // allow:debug
    print("정지: \(status.paused ? "예 — 원상회복 \(status.pausedBy.map { String($0.prefix(8)) }.joined(separator: " ")), 사람이 dream resume" : "아니오")") // allow:debug
    print("미룬 제안: \(status.deferred)") // allow:debug
    print("열린 경보: \(status.alerts.count)") // allow:debug
    for entry in status.alerts { print("  \(entry.world): \(entry.alert)") } // allow:debug
}

private func dreamResume(context: LawCommandContext, asJSON: Bool) {
    let service = LawDreamService(
        file: context.file, catalog: context.catalog, objectStore: nil,
        stateStore: LawDreamStateStore(directory: LawDreamStateStore.standardDirectory))
    // 사람이 아닌 작성자는 모델 기록을 풀기 전에 거부한다(docs/security.md: `dream resume` 은 사람만).
    guard LawActorResolution.kind(of: context.author) == .human else {
        fail(LawDreamError.notHuman(context.author).description)
    }
    let actor = context.actor(explicit: LawModelRecord())
    do {
        if let stored = try service.resume(actor: actor, target: context.lawTarget()) {
            printEnacted([stored.id], asJSON: asJSON)
        } else if asJSON {
            printEnacted([], asJSON: true)
        } else {
            FileHandle.standardError.write(Data("자동 드리밍이 정지 상태가 아님\n".utf8))
        }
    } catch {
        lawFail(error)
    }
}
