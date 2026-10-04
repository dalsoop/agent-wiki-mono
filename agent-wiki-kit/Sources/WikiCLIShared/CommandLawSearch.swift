import Foundation
import KnowledgeBaseWikiCore

// search·context (ledger 3 원장) — 범위는 `WorldSearchScope.entries`(같은 원장·상위·그 각각의 전신)이고
// 전신 결과에는 `[전신 <world>]` 표시(JSON 은 `predecessor: true`)를 붙인다. 검색 본체는 엔진 `LawScopedSearch`.
// 근거: docs/business-rules.md "전신"(검색·컨텍스트 범위도 같고 전신 객체에는 표시가 붙는다).

public func runLawSearchOrContext(context: LawCommandContext, arguments: [String]) {
    guard let command = arguments.first else { return }
    if arguments.contains("--fleet") || arguments.contains("--remote") {
        usageFail("--fleet·--remote 는 ledger 2 원장 전용")
    }
    let parsed = WorldScopedSearchArgs.parse(arguments)
    guard !parsed.queryText.isEmpty else { usageFail("사용법: \(command) <질의> [--limit N] [--json]") }
    let index = context.scopeIndex()
    FileHandle.standardError.write(Data((
        "# world: " + index.entries.map { $0.predecessor ? "\($0.name)(전신)" : $0.name }.joined(separator: " + ")
        + "\n").utf8))
    let top = LawScopedSearch.hits(index: index, parsed: parsed)
    if command == "search" {
        if parsed.asJSON {
            struct Hit: Encodable {
                let id: String; let title: String?; let author: String; let type: String?; let world: String
                let predecessor: Bool; let predecessorOf: String?; let score: Int
            }
            printJSON(top.map {
                Hit(id: $0.item.id, title: $0.item.object.title, author: $0.item.object.author,
                    type: $0.item.law?.type ?? $0.item.object.effectiveType, world: $0.item.world,
                    predecessor: $0.item.isPredecessor, predecessorOf: $0.item.entry.predecessorOf,
                    score: $0.score)
            })
            return
        }
        if top.isEmpty { print("(결과 없음)") } // allow:debug
        for hit in top {
            print("\(hit.item.id.prefix(8))  \(hit.item.object.title ?? "(무제)")  — \(hit.item.object.author)" // allow:debug
                + scopeMark(hit.item, current: index.current))
        }
        return
    }
    print("# 질의: \(parsed.queryText)") // allow:debug
    if top.isEmpty { print("(관련 기록 없음)") } // allow:debug
    for (position, hit) in top.enumerated() {
        let object = hit.item.object
        print("## \(object.title ?? "(무제)") (\(object.id.prefix(8)))\(scopeMark(hit.item, current: index.current))") // allow:debug
        guard position < 3 else { continue }
        let lines = object.body.split(separator: "\n", omittingEmptySubsequences: false)
        print(lines.prefix(40).joined(separator: "\n")) // allow:debug
        if lines.count > 40 { print("… (show \(object.id.prefix(8)) 로 전문)") } // allow:debug
        print("") // allow:debug
    }
}

/// index rebuild|sync|status (ledger 3) — 같은 파생 색인(`state/index.db`)에 ledger 3 기록을 투영으로 싣는다.
public func runLawIndex(context: LawCommandContext, arguments: [String]) {
    let root = context.root
    let sub = arguments.count >= 2 ? arguments[1] : "sync"
    switch sub {
    case "rebuild", "sync":
        if sub == "rebuild" {
            for ext in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: root.appendingPathComponent("state/index.db\(ext)").path)
            }
        }
        let index = LedgerIndex(root: root)
        let result = index.sync(objectsDir: root.appendingPathComponent("objects"))
        print("인덱스 \(sub == "rebuild" ? "재구성" : "동기화"): +\(result.upserted) -\(result.removed), " // allow:debug
            + "총 \(index.objectCount())개")
    case "status":
        let index = LedgerIndex(root: root)
        print("인덱스 기록 \(index.objectCount())개 · \(index.path)") // allow:debug
    default:
        usageFail("사용법: index rebuild|sync|status")
    }
}
