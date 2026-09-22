import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit
import WikiCLIShared

func runShow(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    print(resolve(store, arguments[1]).serialize(), terminator: "")
}

func runList(store: LedgerStore, arguments: [String]) {
    let all = arguments.contains("--all")
    let asJSON = arguments.contains("--json")
    // 인덱스 경로 — 무상태 CLI 라 매번 md 전체 스캔(~5s)하던 걸 SQL 한 방으로.
    let indexPath = store.root.appendingPathComponent("state/index.db")
    if FileManager.default.fileExists(atPath: indexPath.path) {
        let index = LedgerIndex(root: store.root)
        index.ensureFresh(objectsDir: store.root.appendingPathComponent("objects"))
        let rows = index.headRows(all: all)
        if asJSON {
            struct JRow: Encodable {
                let id: String; let title: String?; let author: String; let published: String; let batch: String?
            }
            struct ListEnvelope: Encodable {
                let ok: Bool
                let result: ListResult
            }
            struct ListResult: Encodable {
                let objects: [JRow]
                let note: String
            }
            let mapped = rows.map {
                JRow(id: $0.id, title: $0.title, author: $0.author, published: $0.published, batch: $0.batch)
            }
            printJSON(ListEnvelope(
                ok: true,
                result: ListResult(
                    objects: mapped,
                    note: mapped.isEmpty
                        ? "객체 없음 — agent-wiki publish 로 발행하세요"
                        : "\(mapped.count) objects")))
        } else {
            if rows.isEmpty { print(CLILocalization.string("CommandQuery.print")) }
            for r in rows {
                let marks = [r.supersedes != nil ? "개정" : nil, r.retracts != nil ? "철회발행" : nil]
                    .compactMap { $0 }.joined(separator: ",")
                print(CLILocalization.format("CommandQuery.print-2", String(r.id.prefix(8)), r.title ?? CLILocalization.string("cli.untitled"), r.author) + (marks.isEmpty ? "" : "  [\(marks)]"))
            }
        }
        return
    }
    // 폴백: 인덱스 없으면 전체 스캔.
    let objects = store.scan()
    let rows = all ? objects : store.heads(objects)
    if asJSON {
        struct Row: Encodable {
            let id: String; let title: String?; let author: String; let published: Date; let batch: String?
        }
        struct ListEnvelope: Encodable {
            let ok: Bool
            let result: ListResult
        }
        struct ListResult: Encodable {
            let objects: [Row]
            let note: String
        }
        let mapped = rows.map {
            Row(id: $0.id, title: $0.title, author: $0.author, published: $0.published, batch: $0.batch)
        }
        printJSON(ListEnvelope(
            ok: true,
            result: ListResult(
                objects: mapped,
                note: mapped.isEmpty
                    ? "객체 없음 — agent-wiki publish 로 발행하세요"
                    : "\(mapped.count) objects")))
    } else {
        if rows.isEmpty { print(CLILocalization.string("CommandQuery.print")) }
        for object in rows {
            let marks = [object.supersedes != nil ? "개정" : nil, object.retracts != nil ? "철회발행" : nil]
                .compactMap { $0 }.joined(separator: ",")
            print(CLILocalization.format("CommandQuery.print-2", String(object.id.prefix(8)), object.title ?? CLILocalization.string("cli.untitled"), object.author)
                + (marks.isEmpty ? "" : "  [\(marks)]"))
        }
    }
}

func runSearchOrContext(
    command: String, store: LedgerStore, worldName: String, arguments: [String]
) {
    guard arguments.count >= 2 else { fail(usage) }
    // 어느 원장이 답했는지 stderr 로 밝힌다. 조회가 조용히 다른 world 를 뒤지던
    // 사고(MR !2111)의 재발을 사람이 즉시 알아채게 하는 값싼 장치다.
    // stdout 이 아니라 stderr 인 이유: `--json` 파이프라인을 깨지 않기 위해서.
    FileHandle.standardError.write(
        Data("# world: \(worldName) (\(store.root.path))\n".utf8))
    var query: [String] = []
    var domainFilter: String?
    var kindFilter: String?
    var knowledgeFilter: String?
    var limit = 8
    var asJSON = false
    var fleetMode = false
    var remoteMode = false
    var agentID: String?
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--domain": index += 1; domainFilter = arguments[index]
        case "--kind": index += 1; kindFilter = arguments[index]
        case "--knowledge": index += 1; knowledgeFilter = arguments[index]
        case "--limit": index += 1; limit = Int(arguments[index]) ?? 8
        case "--json": asJSON = true
        case "--fleet": fleetMode = true
        case "--remote": remoteMode = true
        case "--as-agent": index += 1; agentID = arguments[index]
        default: query.append(arguments[index])
        }
        index += 1
    }
    let queryText = query.joined(separator: " ")
    guard !queryText.isEmpty else { fail(usage) }
    if remoteMode {
        // 로컬 world 없이 wiki.50.internal.kr(wiki-hub) 질의. 응답은 FleetPullResult
        // 계약 — 디코드 성공이 곧 계약 검증이다. --json 은 서버 바이트 그대로(파이프라인 보존).
        let hub = GujoHubClient.fromEnvironment()
        FileHandle.standardError.write(Data("# remote: \(hub.baseURL.absoluteString)\n".utf8))
        switch hub.search(query: queryText, limit: limit) {
        case .failure(let error):
            fail("원격 질의 실패 — \(error.message)")
        case .success(let response):
            if asJSON {
                print(String(decoding: response.raw, as: UTF8.self))
            } else {
                if response.result.items.isEmpty { print(CLILocalization.string("CommandQuery.print-3")) }
                for item in response.result.items {
                    let score = item.score.map { String(format: "  %.2f", $0) } ?? ""
                    print(CLILocalization.format("CommandQuery.print-4", String(item.id.prefix(8)), item.title ?? CLILocalization.string("cli.untitled"), score))
                    if !item.snippet.isEmpty { print("    \(item.snippet.prefix(120))") }
                }
                if response.result.truncated { print(CLILocalization.string("CommandQuery.print-5")) }
            }
        }
        return
    }
    if fleetMode {
        runFleetSearchOrContext(
            command: command, queryText: queryText,
            domain: domainFilter, kind: kindFilter, knowledge: knowledgeFilter,
            limit: limit, asJSON: asJSON, agentID: agentID)
        return
    }
    // 인덱스가 있으면 파일 스캔 없이 검색 (100만 대비). 없으면 스캔 폴백.
    //
    // 반드시 `store.root` 를 쓴다. `LedgerConfig.load().rootURL` 은 **기본 world**
    // 의 루트라 선두 `--world` 로 고른 원장을 무시한다. 그러면 `--world gujo-wiki
    // search` 가 repo 원장 index.db 를 뒤져서, gujo 에 없는 객체를 결과로 내놓고
    // gujo 에 있는 객체는 못 찾는다 — 조용히 틀린 답을 준다(빈 결과가 아니라).
    // `context` 는 아래 `store.scan()` 폴백을 타서 원래부터 옳았다. 이 한 줄만
    // world 를 흘리고 있었다.
    if command == "search",
       FileManager.default.fileExists(
           atPath: store.root.appendingPathComponent("state/index.db").path) {
        //
        // 그리고 **반드시 `freshIndex` 를 탄다**. 예전엔 여기서 `LedgerIndex(root:)` 를
        // 바로 만들어 곧장 질의했다 — 읽기 경로 셋(`show`·`resolve`·`list`) 중 `search`
        // 만 신선도 보장을 안 하는 상태였다. `publish` 는 인덱스를 안 건드리므로,
        // 방금 발행한 객체는 누군가 우연히 `show` 를 칠 때까지 검색에 안 잡혔다.
        // "발행했는데 못 찾는다"의 실제 원인이 이것이고, `index rebuild` 로 고쳐졌던 건
        // 필수 단계라서가 아니라 이 결함을 우회한 것이었다. (분류 유무와는 무관 —
        // 미분류 객체도 FTS 에는 정상적으로 잡힌다.)
        guard let index = freshIndex(store) else { return }
        let rows = index.search(queryText, domain: domainFilter, kind: kindFilter,
                                knowledge: knowledgeFilter, limit: limit)
        if asJSON {
            struct Hit: Encodable { let id: String; let title: String?; let author: String
                let domain: String?; let kind: String?; let knowledge: String? }
            printJSON(rows.map { Hit(id: $0.id, title: $0.title, author: $0.author,
                                     domain: $0.domain, kind: $0.kind, knowledge: $0.knowledge) })
        } else {
            // 원본(blob) 히트는 표를 나눠 보여준다 — 객체는 해석이고 blob 은 날것이라,
            // 같은 목록에 섞으면 "무엇을 인용해야 하나"가 흐려진다.
            let blobHits = index.searchBlobs(queryText, limit: 5)
            if rows.isEmpty && blobHits.isEmpty { print(CLILocalization.string("CommandQuery.print-3")) }
            for r in rows {
                let tag = [r.domain, r.kind, r.knowledge].compactMap { $0 }.joined(separator: "/")
                print(CLILocalization.format("CommandQuery.print-6", String(r.id.prefix(8)), r.title ?? CLILocalization.string("cli.untitled")) + (tag.isEmpty ? "" : "  [\(tag)]") + "  — \(r.author)")
            }
            if !blobHits.isEmpty {
                print(CLILocalization.format("CommandQuery.print-7", blobHits.count))
                for b in blobHits {
                    print("  \(b.sha.prefix(8))  [\(b.kind) \(b.size)B]  \(b.snippet)")
                }
            }
        }
        return
    }
    let objects = store.scan()
    let search = LedgerSearch(
        store: store, objects: objects, query: queryText,
        domain: domainFilter, kind: kindFilter, knowledge: knowledgeFilter)

    func classifiers(_ hit: LedgerSearch.Hit) -> String {
        [hit.domain, hit.kind, hit.knowledge].compactMap { $0 }.joined(separator: "/")
    }

    if command == "search" {
        let top = search.hits.prefix(limit)
        if asJSON {
            struct Hit: Encodable {
                let id: String
                let title: String?
                let author: String
                let domain: String?
                let kind: String?
                let knowledge: String?
                let score: Int
                let supports: Int
            }
            printJSON(top.map { hit in
                Hit(id: hit.object.id, title: hit.object.title, author: hit.object.author,
                    domain: hit.domain, kind: hit.kind, knowledge: hit.knowledge,
                    score: hit.score, supports: hit.strength.supportCount)
            })
        } else {
            if top.isEmpty { print(CLILocalization.string("CommandQuery.print-3")) }
            for hit in top {
                let tag = classifiers(hit)
                print(CLILocalization.format("CommandQuery.print-6", String(hit.object.id.prefix(8)), hit.object.title ?? CLILocalization.string("cli.untitled"))
                    + (tag.isEmpty ? "" : "  [\(tag)]")
                    + "  지지 \(hit.strength.supportCount)  — \(hit.object.author)")
            }
        }
    } else {
        // context — 색인 → 개념·엔티티 → 근거 계층 블록
        print(CLILocalization.format("CommandQuery.print-8", queryText))
        let wiki = search.hits.filter {
            ["concept", "entity"].contains($0.object.effectiveType ?? "")
        }.prefix(3)
        if !wiki.isEmpty {
            print(CLILocalization.string("CommandQuery.print-9"))
            for hit in wiki {
                print("### \(hit.object.title ?? "") (\(hit.object.id.prefix(8)))")
                let lines = hit.object.body.split(separator: "\n", omittingEmptySubsequences: false)
                print(lines.prefix(40).joined(separator: "\n"))
                if lines.count > 40 { print(CLILocalization.format("CommandQuery.print-10", String(hit.object.id.prefix(8)))) }
                print("")
            }
        }
        let evidence = search.hits.filter {
            !["concept", "entity", "index"].contains($0.object.effectiveType ?? "")
        }.prefix(limit)
        if !evidence.isEmpty {
            print(CLILocalization.string("CommandQuery.print-11"))
            for hit in evidence {
                let tag = classifiers(hit)
                print(CLILocalization.format("CommandQuery.print-12", String(hit.object.id.prefix(8)), hit.object.title ?? CLILocalization.string("cli.auto3"))
                    + (tag.isEmpty ? "" : " [\(tag)]")
                    + " 지지 \(hit.strength.supportCount)"
                    + (hit.strength.contradictCount > 0 ? " ⚠반박 \(hit.strength.contradictCount)" : ""))
            }
        }
        if wiki.isEmpty && evidence.isEmpty { print(CLILocalization.string("CommandQuery.print-13")) }
    }
}


func runFleetSearchOrContext(
    command: String, queryText: String, domain: String?, kind: String?, knowledge: String?,
    limit: Int, asJSON: Bool, agentID: String?
) {
    let fleet: FleetRegistry
    do { fleet = try FleetStore().load() } catch { fail("fleet: \(error)") }
    guard !fleet.enabledWorlds.isEmpty else { fail("fleet empty — run: fleet scan --apply") }
    let aid = agentID ?? defaultAgentID()
    let profile: AgentProfile
    do { profile = try AgentProfileStore().load(id: aid) } catch { fail("\(error)") }
    let fq = FleetQuery(registry: fleet, profile: profile)
    if command == "search" {
        let hits = fq.search(query: queryText, domain: domain, kind: kind, knowledge: knowledge, limit: limit)
        if asJSON { printJSON(hits) }
        else {
            if hits.isEmpty { print(CLILocalization.string("CommandQuery.print-3")) }
            for h in hits {
                print(String(format: "%.3f", h.score) + "  [\(h.world)] \(h.id.prefix(8))  \(h.title ?? "(무제)")")
            }
        }
        return
    }
    let hits = fq.contextHits(query: queryText, limit: limit)
    if asJSON { printJSON(hits); return }
    print(CLILocalization.format("CommandQuery.print-14", queryText, aid))
    for hit in hits.prefix(limit) {
        print(CLILocalization.format("CommandQuery.print-15", hit.world, String(hit.id.prefix(8)), hit.title ?? CLILocalization.string("cli.auto10"), String(format: "%.3f", hit.score)))
    }
    if hits.isEmpty { print(CLILocalization.string("CommandQuery.print-16")) }
}

func runPath(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 3 else { fail(usage) }
    let from = resolve(store, arguments[1])
    let to = resolve(store, arguments[2])
    // 인용/개정 간선(양방향) — 인덱스(cites+supersedes)에서 세우면 파일 스캔 0, 없으면 스캔 폴백.
    var adjacency: [String: [(next: String, label: String)]] = [:]
    let label: (String) -> (title: String?, author: String)
    if let index = freshIndex(store) {
        for e in index.citeEdges() {
            adjacency[e.src, default: []].append((e.dst, e.rel + " →"))
            adjacency[e.dst, default: []].append((e.src, "← " + e.rel))
        }
        for e in index.supersedesEdges() {
            adjacency[e.id, default: []].append((e.target, "supersedes →"))
            adjacency[e.target, default: []].append((e.id, "← supersedes"))
        }
        label = { index.titleAuthor($0) }
    } else {
        let objects = store.scan()
        for object in objects {
            for cite in object.cites {
                adjacency[object.id, default: []].append((cite.id, cite.rel + " →"))
                adjacency[cite.id, default: []].append((object.id, "← " + cite.rel))
            }
            if let target = object.supersedes {
                adjacency[object.id, default: []].append((target, "supersedes →"))
                adjacency[target, default: []].append((object.id, "← supersedes"))
            }
        }
        let byID = Dictionary(uniqueKeysWithValues: objects.map { ($0.id, $0) })
        label = { (byID[$0]?.title, byID[$0]?.author ?? "?") }
    }
    var previous: [String: (id: String, label: String)] = [:]
    var queue = [from.id]
    var visited: Set<String> = [from.id]
    var found = false
    while !queue.isEmpty && !found {
        let current = queue.removeFirst()
        for (next, label) in adjacency[current] ?? [] where !visited.contains(next) {
            visited.insert(next)
            previous[next] = (current, label)
            if next == to.id { found = true; break }
            queue.append(next)
        }
    }
    guard found else {
        print(CLILocalization.string("CommandQuery.print-17"))
        exit(0)
    }
    var chain: [(id: String, label: String?)] = [(to.id, nil)]
    var cursor = to.id
    while cursor != from.id, let previousStep = previous[cursor] {
        chain.append((previousStep.id, previousStep.label))
        cursor = previousStep.id
    }
    let ordered = Array(chain.reversed())  // from → to. 각 원소의 label = 다음 원소로 가는 간선
    for (index, step) in ordered.enumerated() {
        let (t, a) = label(step.id)
        print(CLILocalization.format("CommandQuery.print-2", String(step.id.prefix(8)), t ?? CLILocalization.string("cli.auto16"), a))
        if index + 1 < ordered.count, let label = step.label {
            print("   │ \(label)")
        }
    }
}

func runHistory(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    let target = resolve(store, arguments[1])
    if let index = freshIndex(store) {   // 인덱스로 supersedes 사슬 순회(파일 스캔 0)
        for (i, r) in index.lineage(of: target.id).enumerated() {
            print("\(i == 0 ? "→" : " ")\(r.id.prefix(8))  \(r.published)  \(r.author)  \(r.title ?? "")")
        }
        return
    }
    let objects = store.scan()
    for (index, object) in store.lineage(objects, of: target.id).enumerated() {
        print("\(index == 0 ? "→" : " ")\(object.id.prefix(8))  \(LedgerObject.iso.string(from: object.published))  \(object.author)  \(object.title ?? "")")
    }
}

func runCitedBy(store: LedgerStore, arguments: [String]) {
    guard arguments.count >= 2 else { fail(usage) }
    let target = resolve(store, arguments[1])
    if let index = freshIndex(store) {   // cites 테이블 역인덱스(파일 스캔 0)
        let citers = index.citers(of: target.id)
        if citers.isEmpty { print(CLILocalization.string("CommandQuery.print-18")) }
        for c in citers {
            print(CLILocalization.format("CommandQuery.print-19", String(c.id.prefix(8)), c.rels, c.title ?? CLILocalization.string("cli.auto21"), c.author))
        }
        return
    }
    let objects = store.scan()
    let citing = store.citedBy(objects, id: target.id)
    if citing.isEmpty { print(CLILocalization.string("CommandQuery.print-18")) }
    for object in citing {
        let rels = object.cites.filter { $0.id == target.id }.map(\.rel).joined(separator: ",")
        print(CLILocalization.format("CommandQuery.print-19", String(object.id.prefix(8)), rels, object.title ?? CLILocalization.string("cli.auto26"), object.author))
    }
}
