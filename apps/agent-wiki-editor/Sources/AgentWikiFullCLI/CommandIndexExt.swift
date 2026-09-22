import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// blob-event 인덱스 조회 — `index blob-event …` 서브커맨드.
/// 기존 `index rebuild|sync|status` 는 CommandIndex 가 담당; main 에서 분기.
func runBlobEventIndex(store: LedgerStore, root: URL, arguments: [String]) {
    // arguments[0] == "index", [1] == "blob-event"
    let sub = arguments.count >= 3 ? arguments[2] : "status"
    let idx = BlobEventIndex(root: root)
    switch sub {
    case "rebuild":
        do {
            let snap = try idx.rebuild()
            print("blob-event index: blobs \(snap.records.count) · events \(snap.events.count)")
        } catch { fail("\(error)") }
    case "list":
        do {
            let recs = try idx.listBlobs()
            if arguments.contains("--json") {
                printJSON(recs)
            } else {
                for r in recs {
                    print("\(r.sha.prefix(12))…  events=\(r.eventIDs.count)  \(r.kindLabel ?? "?")  \(r.size.map(String.init) ?? "?")B")
                }
                print(CLILocalization.format("CommandIndexExt.print", recs.count))
            }
        } catch { fail("\(error)") }
    case "refs":
        guard arguments.count >= 4 else { fail("index blob-event refs <sha>") }
        do {
            let rows = try idx.eventsReferencing(sha: arguments[3])
            if arguments.contains("--json") { printJSON(rows); return }
            if rows.isEmpty { print(CLILocalization.string("CommandIndexExt.print-2")) }
            for e in rows {
                print("\(e.id.prefix(8))  [\(e.rel)] \(e.subject)  level=\(e.level)")
            }
        } catch { fail("\(error)") }
    case "events":
        // index blob-event events [--subject s] [--rel r] [--source sha] [--json]
        func opt(_ name: String) -> String? {
            guard let i = arguments.firstIndex(of: name), arguments.count > i + 1 else { return nil }
            return arguments[i + 1]
        }
        do {
            let rows = try idx.filterEvents(
                subject: opt("--subject"), rel: opt("--rel"), source: opt("--source"))
            if arguments.contains("--json") { printJSON(rows); return }
            for e in rows {
                print("\(e.id.prefix(8))  [\(e.rel)] sub=\(e.subject.prefix(12)) src=\(e.source?.prefix(12) ?? "-")")
            }
            print(CLILocalization.format("CommandIndexExt.print-3", rows.count))
        } catch { fail("\(error)") }
    case "status":
        do {
            let snap = try idx.ensureFresh()
            print("blob-event index: blobs \(snap.records.count) · events \(snap.events.count)")
        } catch { fail("\(error)") }
    default:
        fail("index blob-event rebuild|list|refs|events|status")
    }
}
