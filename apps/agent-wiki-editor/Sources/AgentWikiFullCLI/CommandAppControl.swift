import Foundation
import KnowledgeBaseWikiCore
import StateRootKit
import LocalizationKit

/// 앱 조종 — orca 식 공식 제어 표면. 컨트롤 파일을 쓰면 앱이 2초 내 적용하고 지운다.
/// 결과 확인은 상태 미러(swift-app-router state memo-citation-ledger)로 닫힌 루프.
func runAppControl(arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    let command = arguments[1]
    let argument = arguments.count >= 3 ? arguments[2] : ""
    let valid = ["area", "destination", "jump", "select", "world-picker"]
    guard valid.contains(command) else {
        fail("app 하위명령: area <이름> | destination <목적지> | jump <id> | select <id>")
    }
    if command == "area" {
        // 영역 목록은 Core 의 단일 진실원천을 쓴다 — 앱 매핑과 손으로 갈라지지 않게.
        guard LedgerAreaKey.isValid(argument) else { fail("영역: \(LedgerAreaKey.all.joined(separator: " | "))") }
    } else if command == "destination" {
        guard RepositoryDestinationKey.isValid(argument) else {
            fail("목적지: \(RepositoryDestinationKey.all.joined(separator: " | "))")
        }
    } else if argument.isEmpty {
        fail(usage)
    }
    let dir = StateRootKit.path(".memo-citation-ledger")
    let payload = "{\"command\":\"\(command)\",\"argument\":\"\(argument)\",\"issuedAt\":\"\(nowISO())\"}"
    do {
        try payload.write(toFile: dir + "/control.json", atomically: true, encoding: .utf8)
        print(CLILocalization.string("CommandAppControl.print"))
    } catch { fail("\(error)") }
}
