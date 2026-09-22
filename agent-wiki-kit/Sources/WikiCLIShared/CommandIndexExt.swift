import Foundation
import KnowledgeBaseWikiCore

/// blob-event 인덱스 조회 — `index blob-event …` 서브커맨드.
/// 기존 `index rebuild|sync|status` 는 CommandIndex 가 담당; main 에서 분기.
private func blobEventList(_ idx: BlobEventIndex, json: Bool) {
    do {
        let recs = try idx.listBlobs()
        if json {
            printJSON(recs)
        } else {
            for r in recs {
                print("\(r.sha.prefix(12))…  events=\(r.eventIDs.count)  \(r.kindLabel ?? "?")  \(r.size.map(String.init) ?? "?")B") // allow:debug
            }
            print("총 \(recs.count) blob") // allow:debug
        }
    } catch { fail("\(error)") }
}

private func blobEventRefs(_ idx: BlobEventIndex, sha: String, json: Bool) {
    do {
        let rows = try idx.eventsReferencing(sha: sha)
        if json { printJSON(rows); return }
        if rows.isEmpty { print("(없음)") } // allow:debug
        for e in rows {
            print("\(e.id.prefix(8))  [\(e.rel)] \(e.subject)  level=\(e.level)") // allow:debug
        }
    } catch { fail("\(error)") }
}

private func blobEventFilter(_ idx: BlobEventIndex, arguments: [String]) {
    func opt(_ name: String) -> String? {
        guard let i = arguments.firstIndex(of: name), arguments.count > i + 1 else { return nil }
        return arguments[i + 1]
    }
    do {
        let rows = try idx.filterEvents(
            subject: opt("--subject"), rel: opt("--rel"), source: opt("--source"))
        if arguments.contains("--json") { printJSON(rows); return }
        for e in rows {
            print("\(e.id.prefix(8))  [\(e.rel)] sub=\(e.subject.prefix(12)) src=\(e.source?.prefix(12) ?? "-")") // allow:debug
        }
        print("총 \(rows.count)") // allow:debug
    } catch { fail("\(error)") }
}

public func runBlobEventIndex(store: LedgerStore, root: URL, arguments: [String]) {
    let sub = arguments.count >= 3 ? arguments[2] : "status"
    let idx = BlobEventIndex(root: root)
    let json = arguments.contains("--json")
    switch sub {
    case "rebuild":
        do {
            let snap = try idx.rebuild()
            print("blob-event index: blobs \(snap.records.count) · events \(snap.events.count)") // allow:debug
        } catch { fail("\(error)") }
    case "list":
        blobEventList(idx, json: json)
    case "refs":
        guard arguments.count >= 4 else { fail("index blob-event refs <sha>") }
        blobEventRefs(idx, sha: arguments[3], json: json)
    case "events":
        blobEventFilter(idx, arguments: arguments)
    case "status":
        do {
            let snap = try idx.ensureFresh()
            print("blob-event index: blobs \(snap.records.count) · events \(snap.events.count)") // allow:debug
        } catch { fail("\(error)") }
    default:
        fail("index blob-event rebuild|list|refs|events|status")
    }
}
