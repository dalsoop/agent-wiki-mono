import Foundation
import KnowledgeBaseWikiCore
import WikiLedgerKit

// ledger 3 원장의 조회 — show·list·status·history·cited-by·path. 이름과 뜻은 옛 명령과 같고,
// 읽기 범위는 같은 원장·상위·전신(`WorldSearchScope.entries`)이며 전신 객체에는 표시가 붙는다.
// 근거: docs/contracts.md "조회"·"agent-law 명령 (ledger 3)", docs/business-rules.md "전신"·"사실인정과 4종류".

/// 조회 토큰 → 기록 하나(여러 개면 실패).
func lookupOne(_ token: String, index: LawScopeIndex) -> LawScopeObject {
    let hits = index.lookup(token)
    if hits.count == 1 { return hits[0] }
    if hits.count > 1 {
        let sample = hits.prefix(10).map { "  " + String($0.id.prefix(12)) }.joined(separator: "\n")
        fail("여러 개 매칭(\(hits.count)건) — 더 좁혀 주세요:\n\(sample)")
    }
    fail("기록을 못 찾음: \(token)")
}

/// 전신 표시 — `[전신 gujo-wiki]`, 상위 원장은 `[상위 agent-law]`.
func scopeMark(_ item: LawScopeObject, current: String) -> String {
    if item.isPredecessor { return "  [전신 \(item.world)]" }
    if item.world != current { return "  [상위 \(item.world)]" }
    return ""
}

/// 4종류 등 ledger 3 보기(같은 원장 기록일 때).
struct LawRecordViewSummary: Encodable {
    let inForce: Bool
    let memoryKind: String?
    let currentFinding: String?
}

func viewSummary(for item: LawScopeObject, index: LawScopeIndex) -> LawRecordViewSummary? {
    guard item.law != nil else { return nil }
    let records = index.objects.filter { $0.world == item.world }.compactMap { scoped -> LawStoredRecord? in
        scoped.law.map { LawStoredRecord(id: scoped.id, record: $0) }
    }
    let view = LawLedgerView(records: records)
    return LawRecordViewSummary(
        inForce: view.isInForce(item.id), memoryKind: view.memoryKind(of: item.id)?.rawValue,
        currentFinding: view.currentFinding(for: item.id)?.id)
}

func objectFileText(_ item: LawScopeObject, catalog: WorldBindingCatalog) -> String {
    if let law = item.law { return law.serialize(id: item.id) }
    return item.object.serialize()
}

public func runLawShow(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], usage: "사용법: show <id|제목> [--json]")
    guard options.positionals.count == 1 else { usageFail("사용법: show <id|제목> [--json]") }
    let index = context.scopeIndex()
    let item = lookupOne(options.positionals[0], index: index)
    let text = objectFileText(item, catalog: context.catalog)
    let summary = viewSummary(for: item, index: index)
    if options.has("--json") {
        struct Result: Encodable {
            let id: String; let world: String; let predecessor: Bool; let text: String
            let inForce: Bool?; let memoryKind: String?; let currentFinding: String?
        }
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        printJSON(Envelope(ok: true, result: Result(
            id: item.id, world: item.world, predecessor: item.isPredecessor, text: text,
            inForce: summary?.inForce, memoryKind: summary?.memoryKind, currentFinding: summary?.currentFinding)))
        return
    }
    print(text, terminator: "") // allow:debug — 객체 파일 원문
    var notes: [String] = []
    if item.isPredecessor { notes.append("전신 \(item.world) 객체(읽기 전용)") }
    if let summary {
        notes.append(summary.inForce ? "현행" : "현행 아님")
        if let kind = summary.memoryKind { notes.append("종류 \(LawMemoryKindLabel.label(kind))") }
        if let finding = summary.currentFinding { notes.append("사실인정 \(finding.prefix(8))") }
    }
    if !notes.isEmpty {
        FileHandle.standardError.write(Data(("# " + notes.joined(separator: " · ") + "\n").utf8))
    }
}

/// Claude 기억 4종류 표시 이름(사람·지적·진행·위치·미분류).
enum LawMemoryKindLabel {
    static func label(_ raw: String) -> String {
        switch LawMemoryKind(rawValue: raw) {
        case .person: return "사람(person)"
        case .feedback: return "지적(feedback)"
        case .project: return "진행(project)"
        case .reference: return "위치(reference)"
        case .unclassified, nil: return "미분류"
        }
    }
}

public func runLawList(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], flags: ["--json", "-j", "--all"], usage: "사용법: list [--all] [--json]")
    let records = context.lawTarget().store.scan()
    let view = LawLedgerView(records: records)
    let rows = options.has("--all") ? records : view.inForce
    struct Row: Encodable {
        let id: String; let title: String?; let author: String; let promulgated: String; let type: String?
        let speaker: String?; let batch: String?; let amends: String?; let repeals: String?
        let inForce: Bool; let memoryKind: String?
    }
    let output = rows.map { stored in
        Row(id: stored.id, title: stored.record.title, author: stored.record.author,
            promulgated: LawTime.format(stored.record.promulgated), type: stored.record.type,
            speaker: stored.record.speaker, batch: stored.record.batch, amends: stored.record.amends,
            repeals: stored.record.repeals, inForce: view.isInForce(stored.id),
            memoryKind: view.memoryKind(of: stored.id)?.rawValue)
    }
    if options.has("--json") {
        struct Result: Encodable { let objects: [Row]; let note: String }
        struct Envelope: Encodable { let ok: Bool; let result: Result }
        let note = output.isEmpty ? "기록 없음 — agent-wiki enact 로 공포하세요" : "\(output.count) records"
        printJSON(Envelope(ok: true, result: Result(objects: output, note: note)))
        return
    }
    if output.isEmpty { print("(기록 없음)") } // allow:debug
    for row in output {
        let marks = [row.amends != nil ? "개정" : nil, row.repeals != nil ? "폐지" : nil,
                     row.inForce || row.repeals != nil ? nil : "현행 아님"].compactMap { $0 }.joined(separator: ",")
        print("\(row.id.prefix(8))  \(row.title ?? "(무제)")  — \(row.author)" + (marks.isEmpty ? "" : "  [\(marks)]")) // allow:debug
    }
}

public func runLawStatus(context: LawCommandContext, arguments: [String]) {
    let target = context.lawTarget()
    let records = target.store.scan()
    let view = LawLedgerView(records: records)
    let last = records.last
    struct Status: Encodable {
        let world: String; let ledger: Int; let records: Int; let inForce: Int; let lastEnacted: String?
        let lastTitle: String?; let predecessor: String?; let device: String?
    }
    let status = Status(
        world: target.worldName, ledger: 3, records: records.count, inForce: view.inForce.count,
        lastEnacted: last.map { LawTime.format($0.record.promulgated) }, lastTitle: last?.record.title,
        predecessor: context.catalog.predecessorName(of: target.worldName), device: context.file.currentDevice)
    if arguments.contains("--json") || arguments.contains("-j") {
        struct Envelope: Encodable { let ok: Bool; let result: Status }
        printJSON(Envelope(ok: true, result: status))
        return
    }
    print("world \(status.world) (ledger 3) · 기록 \(status.records)개 · 현행 \(status.inForce)개" // allow:debug
        + (status.predecessor.map { " · 전신 \($0)" } ?? ""))
    if let lastEnacted = status.lastEnacted {
        print("최근 공포: \(lastEnacted)  \(status.lastTitle ?? "(무제)")") // allow:debug
    }
}

public func runLawHistory(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], usage: "사용법: history <id>")
    guard options.positionals.count == 1 else { usageFail("사용법: history <id>") }
    let index = context.scopeIndex()
    let item = lookupOne(options.positionals[0], index: index)
    let sameWorld = index.objects.filter { $0.world == item.world }
    let byID = Dictionary(sameWorld.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    let lawRecords = sameWorld.compactMap { scoped in scoped.law.map { LawStoredRecord(id: scoped.id, record: $0) } }
    let view = LawLedgerView(records: lawRecords)
    if item.isPredecessor { FileHandle.standardError.write(Data("# 전신 \(item.world) 객체의 계보\n".utf8)) }
    func printChain(from id: String, indent: String, marker: String, depth: Int) {
        var current = byID[id]
        var position = 0
        while let node = current, position < 1000, depth < 20 {
            let state = node.law == nil ? "" : (view.isInForce(node.id) ? "  [현행]" : "")
            print("\(indent)\(position == 0 ? marker : " ")\(node.id.prefix(8))  " // allow:debug
                + "\(LawTime.format(node.object.published))  \(node.object.author)  \(node.object.title ?? "")\(state)")
            for parent in node.object.supersedesAlso {
                print("\(indent)   ↳ 병합: \(parent.prefix(8)) 갈래") // allow:debug
                printChain(from: parent, indent: indent + "     ", marker: " ", depth: depth + 1)
            }
            current = node.object.supersedes.flatMap { byID[$0] }
            position += 1
        }
    }
    printChain(from: item.id, indent: "", marker: "→", depth: 0)
}

public func runLawCitedBy(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], usage: "사용법: cited-by <id>")
    guard options.positionals.count == 1 else { usageFail("사용법: cited-by <id>") }
    let index = context.scopeIndex()
    let target = lookupOne(options.positionals[0], index: index)
    let citing = index.objects.filter { $0.object.cites.contains { $0.id == target.id } }
    if citing.isEmpty { print("(인용 없음)") } // allow:debug
    for item in citing {
        let rels = item.object.cites.filter { $0.id == target.id }.map(\.rel).joined(separator: ",")
        print("\(item.id.prefix(8))  [\(rels)]  \(item.object.title ?? "(무제)")  — \(item.object.author)" // allow:debug
            + scopeMark(item, current: index.current))
    }
}

public func runLawPath(context: LawCommandContext, arguments: [String]) {
    let options = LawOptions.parse(arguments, valued: [], usage: "사용법: path <id1> <id2>")
    guard options.positionals.count == 2 else { usageFail("사용법: path <id1> <id2>") }
    let index = context.scopeIndex()
    let from = lookupOne(options.positionals[0], index: index)
    let to = lookupOne(options.positionals[1], index: index)
    var adjacency: [String: [(next: String, label: String)]] = [:]
    for item in index.objects {
        for cite in item.object.cites {
            adjacency[item.id, default: []].append((cite.id, cite.rel + " →"))
            adjacency[cite.id, default: []].append((item.id, "← " + cite.rel))
        }
        for target in item.object.allSupersedes {
            adjacency[item.id, default: []].append((target, "amends →"))
            adjacency[target, default: []].append((item.id, "← amends"))
        }
    }
    var previous: [String: (id: String, label: String)] = [:]
    var queue = [from.id]
    var visited: Set<String> = [from.id]
    while !queue.isEmpty, previous[to.id] == nil {
        let current = queue.removeFirst()
        for (next, label) in adjacency[current] ?? [] where !visited.contains(next) {
            visited.insert(next)
            previous[next] = (current, label)
            queue.append(next)
        }
    }
    guard from.id == to.id || previous[to.id] != nil else {
        print("(경로 없음 — 두 기록이 인용 그래프에서 연결돼 있지 않음)") // allow:debug
        return
    }
    var chain: [(id: String, label: String?)] = [(to.id, nil)]
    var cursor = to.id
    while cursor != from.id, let step = previous[cursor] {
        chain.append((step.id, step.label))
        cursor = step.id
    }
    let ordered = Array(chain.reversed())
    for (position, step) in ordered.enumerated() {
        let item = index.object(id: step.id)
        print("\(step.id.prefix(8))  \(item?.object.title ?? "(무제)")  — \(item?.object.author ?? "?")" // allow:debug
            + (item.map { scopeMark($0, current: index.current) } ?? ""))
        if position + 1 < ordered.count, let label = step.label { print("   │ \(label)") } // allow:debug
    }
}
