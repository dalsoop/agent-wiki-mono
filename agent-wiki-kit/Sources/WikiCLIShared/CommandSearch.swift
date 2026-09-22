import Foundation
import KnowledgeBaseWikiCore

public func runSearchOrContext(
    command: String, store: LedgerStore, worldName: String, arguments: [String]
) {
    guard arguments.count >= 2 else { fail(usage) }
    FileHandle.standardError.write(
        Data("# world: \(worldName) (\(store.root.path))\n".utf8))
    let parsed = parseSearchArguments(arguments)
    guard !parsed.queryText.isEmpty else { fail(usage) }

    if parsed.remoteMode {
        runRemoteSearch(queryText: parsed.queryText, limit: parsed.limit, asJSON: parsed.asJSON)
        return
    }
    if parsed.fleetMode {
        runFleetSearchOrContext(
            command: command, queryText: parsed.queryText,
            domain: parsed.domainFilter, kind: parsed.kindFilter,
            knowledge: parsed.knowledgeFilter,
            limit: parsed.limit, asJSON: parsed.asJSON, agentID: parsed.agentID)
        return
    }
    if command == "search",
       FileManager.default.fileExists(
           atPath: store.root.appendingPathComponent("state/index.db").path) {
        runIndexedSearch(store: store, parsed: parsed)
        return
    }
    runScanSearch(command: command, store: store, parsed: parsed)
}

private struct ParsedSearchArgs {
    var queryText: String
    var domainFilter: String?
    var kindFilter: String?
    var knowledgeFilter: String?
    var limit: Int = 8
    var asJSON: Bool = false
    var fleetMode: Bool = false
    var remoteMode: Bool = false
    var agentID: String?
}

private func parseSearchArguments(_ arguments: [String]) -> ParsedSearchArgs {
    var result = ParsedSearchArgs(queryText: "")
    var query: [String] = []
    var index = 1
    while index < arguments.count {
        switch arguments[index] {
        case "--domain": index += 1; result.domainFilter = arguments[index]
        case "--kind": index += 1; result.kindFilter = arguments[index]
        case "--knowledge": index += 1; result.knowledgeFilter = arguments[index]
        case "--limit": index += 1; result.limit = Int(arguments[index]) ?? 8
        case "--json": result.asJSON = true
        case "--fleet": result.fleetMode = true
        case "--remote": result.remoteMode = true
        case "--as-agent": index += 1; result.agentID = arguments[index]
        default: query.append(arguments[index])
        }
        index += 1
    }
    result.queryText = query.joined(separator: " ")
    return result
}

private func runRemoteSearch(queryText: String, limit: Int, asJSON: Bool) {
    let hub = GujoHubClient.fromEnvironment()
    FileHandle.standardError.write(Data("# remote: \(hub.baseURL.absoluteString)\n".utf8))
    switch hub.search(query: queryText, limit: limit) {
    case .failure(let error):
        fail("원격 질의 실패 — \(error.message)")
    case .success(let response):
        if asJSON {
            print(String(decoding: response.raw, as: UTF8.self)) // allow:debug
        } else {
            if response.result.items.isEmpty { print("(결과 없음)") } // allow:debug
            for item in response.result.items {
                let score = item.score.map { String(format: "  %.2f", $0) } ?? ""
                print("\(item.id.prefix(8))  \(item.title ?? "(무제)")\(score)") // allow:debug
                if !item.snippet.isEmpty { print("    \(item.snippet.prefix(120))") } // allow:debug
            }
            if response.result.truncated { print("(잘림 — --limit 로 늘릴 수 있음)") } // allow:debug
        }
    }
}

private func runIndexedSearch(store: LedgerStore, parsed: ParsedSearchArgs) {
    guard let index = freshIndex(store) else { return }
    let rows = index.search(parsed.queryText, domain: parsed.domainFilter, kind: parsed.kindFilter,
                            knowledge: parsed.knowledgeFilter, limit: parsed.limit)
    if parsed.asJSON {
        struct Hit: Encodable { let id: String; let title: String?; let author: String
            let domain: String?; let kind: String?; let knowledge: String? }
        printJSON(rows.map { Hit(id: $0.id, title: $0.title, author: $0.author,
                                 domain: $0.domain, kind: $0.kind, knowledge: $0.knowledge) })
    } else {
        let blobHits = index.searchBlobs(parsed.queryText, limit: 5)
        if rows.isEmpty && blobHits.isEmpty { print("(결과 없음)") } // allow:debug
        for r in rows {
            let tag = [r.domain, r.kind, r.knowledge].compactMap { $0 }.joined(separator: "/")
            print("\(r.id.prefix(8))  \(r.title ?? "(무제)")" + (tag.isEmpty ? "" : "  [\(tag)]") + "  — \(r.author)") // allow:debug
        }
        if !blobHits.isEmpty {
            print("\n원본(blob) \(blobHits.count)건 — `blob get <sha>` 로 원문을 꺼낸다") // allow:debug
            for b in blobHits {
                print("  \(b.sha.prefix(8))  [\(b.kind) \(b.size)B]  \(b.snippet)") // allow:debug
            }
        }
    }
}

private func runScanSearch(command: String, store: LedgerStore, parsed: ParsedSearchArgs) {
    let objects = store.scan()
    let search = LedgerSearch(
        store: store, objects: objects, query: parsed.queryText,
        domain: parsed.domainFilter, kind: parsed.kindFilter, knowledge: parsed.knowledgeFilter)

    func classifiers(_ hit: LedgerSearch.Hit) -> String {
        [hit.domain, hit.kind, hit.knowledge].compactMap { $0 }.joined(separator: "/")
    }

    if command == "search" {
        printScanSearchResults(search: search, limit: parsed.limit, asJSON: parsed.asJSON, classifiers: classifiers)
    } else {
        printContextResults(search: search, queryText: parsed.queryText, limit: parsed.limit, classifiers: classifiers)
    }
}

private func printScanSearchResults(
    search: LedgerSearch, limit: Int, asJSON: Bool,
    classifiers: (LedgerSearch.Hit) -> String
) {
    let top = search.hits.prefix(limit)
    if asJSON {
        struct Hit: Encodable {
            let id: String; let title: String?; let author: String
            let domain: String?; let kind: String?; let knowledge: String?
            let score: Int; let supports: Int
        }
        printJSON(top.map { hit in
            Hit(id: hit.object.id, title: hit.object.title, author: hit.object.author,
                domain: hit.domain, kind: hit.kind, knowledge: hit.knowledge,
                score: hit.score, supports: hit.strength.supportCount)
        })
    } else {
        if top.isEmpty { print("(결과 없음)") } // allow:debug
        for hit in top {
            let tag = classifiers(hit)
            print("\(hit.object.id.prefix(8))  \(hit.object.title ?? "(무제)")" // allow:debug
                + (tag.isEmpty ? "" : "  [\(tag)]")
                + "  지지 \(hit.strength.supportCount)  — \(hit.object.author)")
        }
    }
}

private func printContextResults(
    search: LedgerSearch, queryText: String, limit: Int,
    classifiers: (LedgerSearch.Hit) -> String
) {
    print("# 조회: \(queryText)\n") // allow:debug
    let wiki = search.hits.filter {
        ["concept", "entity"].contains($0.object.effectiveType ?? "")
    }.prefix(3)
    if !wiki.isEmpty {
        print("## 위키 층 (종합된 지식 — 서술마다 근거 cite)\n") // allow:debug
        for hit in wiki {
            print("### \(hit.object.title ?? "") (\(hit.object.id.prefix(8)))") // allow:debug
            let lines = hit.object.body.split(separator: "\n", omittingEmptySubsequences: false)
            print(lines.prefix(40).joined(separator: "\n")) // allow:debug
            if lines.count > 40 { print("… (전문: show \(hit.object.id.prefix(8)))") } // allow:debug
            print("") // allow:debug
        }
    }
    let evidence = search.hits.filter {
        !["concept", "entity", "index"].contains($0.object.effectiveType ?? "")
    }.prefix(limit)
    if !evidence.isEmpty {
        print("## 근거 층 (원 기록 — 전문은 show <id>)\n") // allow:debug
        for hit in evidence {
            let tag = classifiers(hit)
            print("- \(hit.object.id.prefix(8)) \(hit.object.title ?? "(무제)")" // allow:debug
                + (tag.isEmpty ? "" : " [\(tag)]")
                + " 지지 \(hit.strength.supportCount)"
                + (hit.strength.contradictCount > 0 ? " ⚠반박 \(hit.strength.contradictCount)" : ""))
        }
    }
    if wiki.isEmpty && evidence.isEmpty { print("(해당 지식 없음 — capture/publish 로 먼저 쌓아야 함)") } // allow:debug
}


public func runFleetSearchOrContext(
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
            if hits.isEmpty { print("(결과 없음)") } // allow:debug
            for h in hits {
                print(String(format: "%.3f", h.score) + "  [\(h.world)] \(h.id.prefix(8))  \(h.title ?? "(무제)")") // allow:debug
            }
        }
        return
    }
    let hits = fq.contextHits(query: queryText, limit: limit)
    if asJSON { printJSON(hits); return }
    print("# 조회: \(queryText)  (fleet · agent=\(aid))\n") // allow:debug
    for hit in hits.prefix(limit) {
        print("- [\(hit.world)] \(hit.id.prefix(8)) \(hit.title ?? "(무제)") score=\(String(format: "%.3f", hit.score))") // allow:debug
    }
    if hits.isEmpty { print("(해당 지식 없음)") } // allow:debug
}
