import Foundation
import KnowledgeBaseWikiCore
import LocalizationKit

/// UUIDv7 원장을 content-addressed 로 일괄 재주소화한다(제1조 v2).
///   migrate                 — dry-run 리포트만(기본, 안전)
///   migrate --apply         — in-place: 새 content-id 파일 쓰고 remap 된 구 uuid 파일 삭제
///   migrate --to <dir> [--apply] — 원본 안 건드리고 새 v2 원장을 <dir> 에 쓴다(비파괴)
func runMigrate(store: LedgerStore, arguments: [String]) {
    let apply = arguments.contains("--apply")
    var target: URL?
    if let index = arguments.firstIndex(of: "--to"), arguments.count > index + 1 {
        target = URL(fileURLWithPath: (arguments[index + 1] as NSString).expandingTildeInPath)
    }

    let objects = store.scan()
    let report = LedgerMigration.readdress(objects)
    let unchanged = report.migrated.filter(\.unchanged).count
    var summary = "객체 \(objects.count) · 재주소화 \(report.changed) · 무변경 \(unchanged)"
        + " · dedup \(report.deduped) · 라운드 \(report.rounds)"
    if report.cycleForced > 0 { summary += " · ⚠교착강제 \(report.cycleForced)" }
    print(summary)

    guard apply else {
        print(CLILocalization.string("CommandMigrate.print"))
        return
    }

    let destRoot = target ?? store.root
    let inPlace = target == nil
    let objectsDir = destRoot.appendingPathComponent("objects")
    let calendar = Calendar(identifier: .gregorian)
    var written = 0
    for item in report.migrated {
        let components = calendar.dateComponents(in: TimeZone(identifier: "UTC")!, from: item.published)
        let dir = objectsDir
            .appendingPathComponent(String(format: "%04d", components.year ?? 0))
            .appendingPathComponent(String(format: "%02d", components.month ?? 0))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("\(item.newID).md")
            try Data(item.serialized.utf8).write(to: url)
            written += 1
        } catch {
            fail("migrate 쓰기 실패(\(item.newID)): \(error.localizedDescription)")
        }
    }
    print(CLILocalization.text("CommandMigrate.print-2", values: written, objectsDir.path))

    if inPlace {
        // remap 으로 id 가 바뀐 구 uuid 파일만 삭제(무변경 content-id 객체 파일은 유지).
        var removed = 0
        if let enumerator = FileManager.default.enumerator(
            at: objectsDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator where url.pathExtension == "md" {
                let name = url.deletingPathExtension().lastPathComponent
                if let newID = report.remap[name], newID != name {   // 구 id → 삭제
                    do {
                        try FileManager.default.removeItem(at: url)
                    } catch {
                        fputs("warning: removeItem \(url.path): \(error.localizedDescription)\n", stderr)
                    }
                    removed += 1
                }
            }
        }
        print(CLILocalization.text("CommandMigrate.print-3", values: removed))
    }
    print(CLILocalization.string("CommandMigrate.print-4"))
}
