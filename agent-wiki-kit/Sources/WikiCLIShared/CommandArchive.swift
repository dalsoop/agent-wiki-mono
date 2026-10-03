import Foundation
import KnowledgeBaseWikiCore

// archive [--dry-run] — 세션 조각 R2 적재. 본체는 `LawArchiveRunner`(드리밍도 같은 함수로 먼저 적재한다).
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)". 규칙: docs/security.md "R2 와 세션", docs/architecture.md "agent-law".
// 쓰기 게이트(기기 키 미등록 거부)는 명령 표면이 먼저 판정한다. `--dry-run` 은 R2·상태에 쓰지 않는다.

let archiveUsage = "사용법: archive [--dry-run] [--json]"

public func runArchive(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], flags: ["--json", "-j", "--dry-run"], usage: archiveUsage)
    guard options.positionals.isEmpty else { usageFail(archiveUsage) }
    guard context.isLedgerThree else { usageFail("archive 는 ledger 3 원장 전용") }
    guard let device = context.file.currentDevice, !device.isEmpty else {
        fail(LawArchiveError.deviceMissing.description)
    }
    let dryRun = options.has("--dry-run")
    var store: (any LawObjectStore)?
    do {
        store = try LawR2Client.standard(file: context.file)
    } catch {
        // dry-run 은 R2 없이 계획만 보인다. 실제 적재는 키가 없으면 거부.
        if !dryRun { fail("\(error)") }
    }
    let runner = LawArchiveRunner(
        device: device, file: context.file, source: LawAgentSessionSource(), registry: .standard,
        stateDirectory: LawArchiveStateStore.standardDirectory, store: store)
    let outcome: LawArchiveOutcome
    do {
        outcome = try runner.run(dryRun: dryRun)
    } catch {
        if options.has("--json") {
            struct Failure: Encodable { let ok: Bool; let error: String }
            printJSON(Failure(ok: false, error: "\(error)"))
            exit(1)
        }
        fail("archive 실패: \(error)")
    }
    if options.has("--json") {
        struct Envelope: Encodable { let ok: Bool; let result: LawArchiveOutcome }
        printJSON(Envelope(ok: outcome.failures.isEmpty, result: outcome))
    } else {
        print("\(outcome.dryRun ? "[dry-run] " : "")실행 \(outcome.run)  켠 시각 \(outcome.enabledAt)\(outcome.firstRun ? " (이번에 켬)" : "")") // allow:debug — 명령 결과 출력
        print("조각 \(outcome.chunks.count)  발화 \(outcome.utterances)  켠 시각 전 세션 제외 \(outcome.skippedBeforeEnabled)") // allow:debug
        for item in outcome.chunks { print("  \(item.key)  [\(item.from), \(item.to))") } // allow:debug
        for (tenant, count) in outcome.unassigned.sorted(by: { $0.key < $1.key }) {
            print("테넌트 미상 \(tenant): 조각 \(count)") // allow:debug
        }
        for key in outcome.manifests { print("요약 \(key)") } // allow:debug
        for failure in outcome.failures { print("실패 \(failure.target): \(failure.reason)") } // allow:debug
    }
    if !outcome.failures.isEmpty { exit(1) }
}
