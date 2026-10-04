import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// summon — 세션 발화 소환. 본체는 `LawSummonService`(드리밍·심급도 같은 함수로 읽는다).
// 계약: docs/contracts.md "agent-law 명령 (ledger 3)" — `summon [--session <id>] [--since <t>] [--until <t>] [--device <k>] [--runtime <r>] [--role user|assistant|tool] [--query <q>] [--record <발화 번호>]`
// 범위: docs/security.md "agent-law" 격리 표(같은 테넌트 원장과 공유 원장 `law`, 다른 테넌트·`unassigned` 는 거부 1).
// `--record` 의 쓰기 게이트는 명령 표면이 먼저 판정하고, 공포는 `LawEnactService.enact`(증언 확인 포함) 하나다.
// 발화 번호는 세션 안의 번호(0부터, 출력의 `#n`)다.

let summonUsage = """
사용법: summon [--session <id>] [--since <t>] [--until <t>] [--device <k>] [--runtime <r>]
               [--role user|assistant|tool] [--query <q>] [--record <발화 번호>] [--json]
  <t>: ISO 8601(예 2026-10-04T09:00:00+09:00) 또는 yyyy-MM-dd(한국 시간)
"""

let summonValueOptions: Set<String> = [
    "--session", "--since", "--until", "--device", "--runtime", "--role", "--query", "--record",
]

public func runSummon(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: summonValueOptions, usage: summonUsage)
    guard options.positionals.isEmpty else { usageFail(summonUsage) }
    guard context.isLedgerThree else { usageFail("summon 은 ledger 3 원장 전용") }
    let asJSON = options.has("--json")

    if let role = options.value("--role") {
        switch role {
        case "user", "assistant":
            break
        case "tool":
            // 공용 세션 리더는 user·assistant 발화만 준다. 도구 발화는 소환할 수 없다.
            FileHandle.standardError.write(Data("도구 발화는 세션 리더가 주지 않아 결과가 없음 (--role user|assistant)\n".utf8))
            if asJSON { printSummon(LawSummonResult(ledgerKeys: [], utterances: [], redactedChunks: 0, offline: nil)) }
            return
        default:
            usageFail("--role 은 user|assistant|tool\n\(summonUsage)")
        }
    }
    func time(_ name: String) -> Date? {
        guard let raw = options.value(name) else { return nil }
        guard let date = LawSummonQuery.parseTime(raw) else { usageFail("\(name) 시각을 읽을 수 없음: \(raw)\n\(summonUsage)") }
        return date
    }
    if let runtime = options.value("--runtime"), LawRuntime(rawValue: runtime) == nil {
        usageFail("--runtime 은 " + LawRuntime.allCases.map(\.rawValue).joined(separator: "|"))
    }
    let query = LawSummonQuery(
        session: options.value("--session"), since: time("--since"), until: time("--until"),
        device: options.value("--device"), runtime: options.value("--runtime"), role: options.value("--role"),
        query: options.value("--query"))
    let target = context.lawTarget()

    if let raw = options.value("--record") {
        guard let index = Int(raw), index >= 0 else { usageFail("--record 는 발화 번호(0 이상 정수)\n\(summonUsage)") }
        let outcome: LawSummonRecordOutcome
        do {
            outcome = try LawSummonService.record(
                index: index, query: query, target: target, actor: context.actor(explicit: LawModelRecord()))
        } catch {
            lawFail(error)
        }
        if let reason = outcome.uploadError {
            FileHandle.standardError.write(Data("증거물 R2 올리기 보류(다음 sync 가 올림): \(reason)\n".utf8))
        }
        printEnacted([outcome.record.id], asJSON: asJSON)
        return
    }

    let result: LawSummonResult
    do {
        result = try LawSummonService.search(query, target: target)
    } catch {
        lawFail(error)
    }
    if let offline = result.offline {
        FileHandle.standardError.write(Data("R2 를 읽지 못해 로컬 소환 색인만 씀: \(offline)\n".utf8))
    }
    if asJSON {
        printSummon(result)
        return
    }
    for utterance in result.utterances {
        let head = "\(utterance.at ?? "-")  \(utterance.ledgerKey)  \(utterance.device)  "
            + "\(utterance.runtime)/\(utterance.session) #\(utterance.index) [\(utterance.role)]"
        print(head) // allow:debug — 명령 결과 출력
        print("  " + preview(utterance.text)) // allow:debug
    }
    FileHandle.standardError.write(Data(
        "발화 \(result.utterances.count)  범위 \(result.ledgerKeys.joined(separator: ", "))  가린 조각 \(result.redactedChunks)\n".utf8))
}

private func printSummon(_ result: LawSummonResult) {
    struct Envelope: Encodable { let ok: Bool; let result: LawSummonResult }
    printJSON(Envelope(ok: true, result: result))
}

/// 한 줄 미리보기(줄바꿈은 공백, 400자까지).
private func preview(_ text: String) -> String {
    let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
    return flat.count > 400 ? String(flat.prefix(400)) + "…" : flat
}
