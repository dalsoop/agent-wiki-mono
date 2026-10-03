import Foundation
import KnowledgeBaseWikiCore

// exhibit put <파일> · exhibit get <sha> — 증거물(원자료 바이트, 이름 = sha256). ledger 3 전용.
// R2 올리기·받기는 동기화·적재 작업(T5·T7)이 붙인다. 근거: docs/contracts.md "agent-law 명령 (ledger 3)".

let exhibitUsage = "사용법: exhibit put <파일> [--json] · exhibit get <sha>"

public func runExhibit(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, skip: 2, valued: [], usage: exhibitUsage)
    guard arguments.count >= 2, options.positionals.count == 1 else { usageFail(exhibitUsage) }
    guard context.isLedgerThree else { usageFail("exhibit 는 ledger 3 원장 전용 — ledger 2 원장은 blob get|info") }
    let store = context.lawTarget().store
    switch arguments[1] {
    case "put":
        let path = (options.positionals[0] as NSString).expandingTildeInPath
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
            fail("파일을 읽을 수 없음: \(path): \(error.localizedDescription)")
        }
        do {
            let sha = try store.putExhibit(data)
            printEnacted([sha], asJSON: options.has("--json"))
        } catch {
            lawFail(error)
        }
    case "get":
        do {
            FileHandle.standardOutput.write(try store.exhibit(sha256: options.positionals[0].lowercased()))
        } catch {
            lawFail(error)
        }
    default:
        usageFail(exhibitUsage)
    }
}
