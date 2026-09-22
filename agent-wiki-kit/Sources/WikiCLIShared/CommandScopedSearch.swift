import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

public struct ScopedSearchCopy: Sendable {
    public var untitled: String
    public var searchEmpty: String
    public var contextEmpty: String

    public init(untitled: String, searchEmpty: String, contextEmpty: String) {
        self.untitled = untitled
        self.searchEmpty = searchEmpty
        self.contextEmpty = contextEmpty
    }

    public static func fromLocalization(
        untitledKey: String = "CommandSearch.untitled",
        searchEmptyKey: String = "CommandSearch.empty",
        contextEmptyKey: String = "CommandSearch.empty"
    ) -> ScopedSearchCopy {
        ScopedSearchCopy(
            untitled: CLILocalization.string(untitledKey),
            searchEmpty: CLILocalization.string(searchEmptyKey),
            contextEmpty: CLILocalization.string(contextEmptyKey))
    }
}

public func runScopedSearchOrContext(
    command: String,
    store: LedgerStore,
    worldName: String,
    arguments: [String],
    catalog: WorldBindingCatalog,
    copy: ScopedSearchCopy = .fromLocalization()
) {
    if arguments.contains("--fleet") || arguments.contains("--remote") {
        runSearchOrContext(command: command, store: store, worldName: worldName, arguments: arguments)
        return
    }
    let scope = WorldSearchScope.names(current: worldName, catalog: catalog)
    if scope.count <= 1 {
        runSearchOrContext(command: command, store: store, worldName: worldName, arguments: arguments)
        return
    }
    guard arguments.count >= 2 else { fail(usage) }
    FileHandle.standardError.write(
        Data("# world: \(scope.joined(separator: " + "))\n".utf8))
    let parsed = WorldScopedSearchArgs.parse(arguments)
    guard !parsed.queryText.isEmpty else { fail(usage) }
    let top = scopedHits(scope: scope, catalog: catalog, parsed: parsed)
    if command == "search" {
        printScopedSearch(top: top, asJSON: parsed.asJSON, copy: copy)
    } else {
        printScopedContext(queryText: parsed.queryText, top: top, limit: parsed.limit, copy: copy)
    }
}

private struct ScopedHit {
    var object: LedgerObject
    var score: Int
    var domain: String?
    var kind: String?
    var knowledge: String?
    var supports: Int
    var contradict: Int
}

private func scopedHits(
    scope: [String],
    catalog: WorldBindingCatalog,
    parsed: WorldScopedSearchParse
) -> [ScopedHit] {
    var merged: [ScopedHit] = []
    for name in scope {
        guard let world = catalog.world(named: name) else { continue }
        let scopedStore = LedgerStore(root: URL(fileURLWithPath: world.rootPath))
        let objects = scopedStore.scan()
        let search = LedgerSearch(
            store: scopedStore, objects: objects, query: parsed.queryText,
            domain: parsed.domainFilter, kind: parsed.kindFilter, knowledge: parsed.knowledgeFilter)
        for hit in search.hits {
            merged.append(ScopedHit(
                object: hit.object,
                score: hit.score,
                domain: hit.domain,
                kind: hit.kind,
                knowledge: hit.knowledge,
                supports: hit.strength.supportCount,
                contradict: hit.strength.contradictCount))
        }
    }
    merged.sort { $0.score > $1.score }
    return Array(merged.prefix(parsed.limit))
}

private func printScopedSearch(top: [ScopedHit], asJSON: Bool, copy: ScopedSearchCopy) {
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
        printJSON(top.map {
            Hit(
                id: $0.object.id, title: $0.object.title, author: $0.object.author,
                domain: $0.domain, kind: $0.kind, knowledge: $0.knowledge,
                score: $0.score, supports: $0.supports)
        })
        return
    }
    if top.isEmpty { print(copy.searchEmpty) } // allow:debug
    for hit in top {
        let tag = [hit.domain, hit.kind, hit.knowledge].compactMap { $0 }.joined(separator: "/")
        let title = hit.object.title ?? copy.untitled
        print("\(hit.object.id.prefix(8))  \(title)" // allow:debug
            + (tag.isEmpty ? "" : "  [\(tag)]")
            + "  \(CLILocalization.format("CommandSearch.support", "\(hit.supports)"))  — \(hit.object.author)")
    }
}

private func printScopedContext(
    queryText: String, top: [ScopedHit], limit: Int, copy: ScopedSearchCopy
) {
    print(CLILocalization.format("CommandSearch.query", queryText)) // allow:debug
    let wiki = top.filter { ["concept", "entity"].contains($0.object.effectiveType ?? "") }.prefix(3)
    if !wiki.isEmpty {
        print(CLILocalization.string("CommandSearch.wikiLayer")) // allow:debug
        for hit in wiki {
            print("### \(hit.object.title ?? "") (\(hit.object.id.prefix(8)))") // allow:debug
            let lines = hit.object.body.split(separator: "\n", omittingEmptySubsequences: false)
            print(lines.prefix(40).joined(separator: "\n")) // allow:debug
            if lines.count > 40 {
                print(CLILocalization.format("CommandSearch.more", String(hit.object.id.prefix(8)))) // allow:debug
            }
            print("") // allow:debug
        }
    }
    let evidence = top.filter {
        !["concept", "entity", "index"].contains($0.object.effectiveType ?? "")
    }.prefix(limit)
    if !evidence.isEmpty {
        print(CLILocalization.string("CommandSearch.evidenceLayer")) // allow:debug
        for hit in evidence {
            let tag = [hit.domain, hit.kind, hit.knowledge].compactMap { $0 }.joined(separator: "/")
            let title = hit.object.title ?? copy.untitled
            var line = "- \(hit.object.id.prefix(8)) \(title)"
                + (tag.isEmpty ? "" : " [\(tag)]")
                + " \(CLILocalization.format("CommandSearch.support", "\(hit.supports)"))"
            if hit.contradict > 0 {
                line += " \(CLILocalization.format("CommandSearch.contradict", "\(hit.contradict)"))"
            }
            print(line) // allow:debug
        }
    }
    if wiki.isEmpty && evidence.isEmpty {
        print(copy.contextEmpty) // allow:debug
    }
}
