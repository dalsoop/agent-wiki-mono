import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// index rebuild|sync|status — 파생 SQLite 인덱스 관리 (md 정본, 인덱스는 캐시).
func runIndex(store: LedgerStore, root: URL, arguments: [String]) {
    let sub = arguments.count >= 2 ? arguments[1] : "sync"
    if sub == "blob-event" {
        runBlobEventIndex(store: store, root: root, arguments: arguments)
        return
    }
    if sub == "rebuild" {
        for ext in ["", "-wal", "-shm"] {
            let path = root.appendingPathComponent("state/index.db\(ext)").path
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                let ns = error as NSError
                if ns.domain != NSCocoaErrorDomain || ns.code != NSFileNoSuchFileError {
                    fputs("warning: removeItem \(path): \(error.localizedDescription)\n", stderr)
                }
            }
        }
    }
    let index = LedgerIndex(root: root)
    switch sub {
    case "rebuild", "sync":
        let r = index.sync(objectsDir: root.appendingPathComponent("objects"))
        let b = index.syncBlobs(root: root)   // 원본층도 같이 — 봉인만 하고 색인 안 하면 못 찾는다
        let op = sub == "rebuild" ? CLILocalization.string("cli.rebuild") : CLILocalization.string("cli.sync")
        print(CLILocalization.text("CommandIndex.print", values: op, r.upserted, r.removed)
            + "총 \(index.objectCount())개 · 원본 +\(b.indexed) -\(b.removed)")
    case "status":
        print(CLILocalization.text("CommandIndex.print-2", values: index.objectCount(), index.blobRowCount(), index.path))
    default: fail(usage)
    }
}
