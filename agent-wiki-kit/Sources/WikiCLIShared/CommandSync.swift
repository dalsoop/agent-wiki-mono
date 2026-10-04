import Foundation
import KnowledgeBaseWikiCore

// sync — agent-law git 동기화: 커밋 대기 기록 커밋 → origin pull(파일 합집합) → push.
// 이어서 원장마다 가림 기록에 따른 로컬 삭제(`LawRedactionSweep`)와 증거물 R2 동기화(`LawExhibitSync`)를 한다.
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `sync`. 규칙: docs/business-rules.md "공포·개정·폐지·원상회복",
// docs/security.md "R2 와 세션"(다른 기기의 가림은 다음 동기화 때 로컬 사본을 지운다).
// 원장 셋이 한 저장소라 어느 ledger 3 원장에서 불러도 저장소 전체를 동기화한다.
// 전신(ledger 1·2)은 결정 0007 에 따라 `gujo sync`(읽기 pull 만)로 한다.

let syncUsage = "사용법: sync [--json]"

/// 원장 하나의 가림·증거물 동기화 결과.
struct LawEvidenceSyncReport: Encodable {
    let world: String
    let redactionDeletes: [String]
    let exhibits: LawExhibitSyncOutcome?
}

public func runSync(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], usage: syncUsage)
    guard options.positionals.isEmpty else { usageFail(syncUsage) }
    guard context.isLedgerThree else {
        usageFail("sync 는 ledger 3 원장 전용 — 전신 원장은 gujo sync(읽기 pull 만)")
    }
    let sync = LawGitSync(ledgerRoot: context.lawTarget().root)
    let gitResult = sync.sync()

    // 가림 기록을 받은 뒤 로컬 삭제 → 증거물 차집합 동기화(가린 것은 옮기지 않는다).
    var evidenceMessages: [String] = []
    let objectStore: LawR2Client?
    do {
        objectStore = try LawR2Client.standard(file: context.file)
    } catch {
        objectStore = nil
        evidenceMessages.append("증거물 R2 동기화 건너뜀: \(error)")
    }
    var reports: [LawEvidenceSyncReport] = []
    for world in context.catalog.worlds where context.catalog.isLedgerThree(world.name) {
        guard let key = world.key, context.catalog.successorNames(of: world.name).isEmpty,
              FileManager.default.fileExists(atPath: world.rootPath)
        else { continue }
        let store = LawStore(root: URL(fileURLWithPath: world.rootPath))
        let deleted = LawRedactionSweep.applyLocalDeletions(store: store, ledgerKey: key)
        let exhibits = objectStore.map { LawExhibitSync.sync(store: store, ledgerKey: key, objectStore: $0) }
        reports.append(LawEvidenceSyncReport(world: world.name, redactionDeletes: deleted, exhibits: exhibits))
    }
    let evidenceOK = reports.allSatisfy { $0.exhibits?.ok ?? true }

    switch gitResult {
    case .success(let outcome):
        if options.has("--json") {
            struct Envelope: Encodable {
                let ok: Bool; let result: LawSyncOutcome; let evidence: [LawEvidenceSyncReport]; let messages: [String]
            }
            printJSON(Envelope(ok: outcome.pushed && evidenceOK, result: outcome, evidence: reports, messages: evidenceMessages))
        } else {
            print("커밋 대기 커밋: \(outcome.committedPending)") // allow:debug — 명령 결과 출력
            print("받아온 기록: \(outcome.received)") // allow:debug
            print("push: \(outcome.pushed ? "완료" : "실패")  \(outcome.branch) \(outcome.head ?? "?")") // allow:debug
            for message in outcome.messages { print("  \(message)") } // allow:debug
            printEvidence(reports, messages: evidenceMessages)
        }
        // push·증거물 실패는 숨기지 않는다 — 결과를 낸 뒤 거부 종료.
        if !outcome.pushed || !evidenceOK { exit(1) }
    case .failure(let error):
        if options.has("--json") {
            struct Failure: Encodable {
                let ok: Bool; let error: String; let evidence: [LawEvidenceSyncReport]; let messages: [String]
            }
            printJSON(Failure(ok: false, error: error.description, evidence: reports, messages: evidenceMessages))
            exit(1)
        }
        printEvidence(reports, messages: evidenceMessages)
        fail("sync 실패: \(error.description)")
    }
}

private func printEvidence(_ reports: [LawEvidenceSyncReport], messages: [String]) {
    for report in reports {
        if !report.redactionDeletes.isEmpty {
            print("가림 기록에 따른 로컬 삭제 \(report.world): \(report.redactionDeletes.count)") // allow:debug
        }
        guard let exhibits = report.exhibits else { continue }
        print("증거물 \(report.world): 올림 \(exhibits.uploaded.count) 받음 \(exhibits.downloaded.count)") // allow:debug
        for sha in exhibits.rejected { print("  sha256 불일치(저장 안 함): \(sha)") } // allow:debug
        for failure in exhibits.failed { print("  실패 \(failure.target): \(failure.reason)") } // allow:debug
    }
    for message in messages { print(message) } // allow:debug
}
