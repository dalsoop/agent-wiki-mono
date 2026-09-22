import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// `agent-wiki status` — **원장이 지금 어떠냐를 한 마디로.**
///
/// 관측 계약(`InteropKit.ObservabilityContract`)이 요구하는 표준 질문이다. 함대가
/// 물어보는 쪽은 이 앱의 인자 규약을 모르므로 **인자 없이** 답해야 한다.
///
/// `verify` 를 여기서 돌리지 않는다 — 실측 2.9초다. status 는 자주·여러 앱을 한꺼번에
/// 묻는 자리라 그 값이면 함대 조회가 통째로 느려진다. 무결성은 `verify` 가 정본이고,
/// status 는 그쪽을 가리키기만 한다.
func runStatus(store: LedgerStore, worldName: String, arguments: [String]) {
    let asJSON = arguments.contains("--json") || arguments.contains("-j")

    // 인덱스가 있으면 SQL 한 방, 없으면 md 전체 스캔(~5s) — list 와 같은 경로를 쓴다.
    let indexPath = store.root.appendingPathComponent("state/index.db")
    var heads = 0
    var total = 0
    var latest: String?
    var indexed = false

    if FileManager.default.fileExists(atPath: indexPath.path) {
        indexed = true
        let index = LedgerIndex(root: store.root)
        index.ensureFresh(objectsDir: store.root.appendingPathComponent("objects"))
        let headRows = index.headRows(all: false)
        heads = headRows.count
        total = index.headRows(all: true).count
        latest = headRows.map(\.published).max()
    } else {
        let objects = store.scan()
        total = objects.count
        heads = store.heads(objects).count
        // 인덱스 경로는 문자열(ISO8601), 스캔 경로는 Date 다. 표시 형식을 맞춘다.
        let iso = ISO8601DateFormatter()
        latest = store.heads(objects).map(\.published).max().map(iso.string(from:))
    }

    if asJSON {
        struct Result: Encodable {
            let world: String
            let root: String
            let heads: Int
            let objects: Int
            let latestPublished: String?
            let indexed: Bool
        }
        struct Envelope: Encodable {
            let ok: Bool
            let result: Result
        }
        printJSON(Envelope(ok: true, result: Result(
            world: worldName, root: store.root.path, heads: heads, objects: total,
            latestPublished: latest, indexed: indexed)))
        return
    }

    print("world: \(worldName)  (\(store.root.path))")
    print(CLILocalization.format("CommandStatus.print", heads, total) + (indexed ? "" : CLILocalization.string("cli.no-index")))
    print(CLILocalization.format("CommandStatus.print-2", latest ?? CLILocalization.string("cli.none")))
    print(CLILocalization.string("CommandStatus.print-3"))
}
