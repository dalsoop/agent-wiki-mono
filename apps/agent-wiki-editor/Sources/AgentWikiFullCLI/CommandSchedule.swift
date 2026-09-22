import Foundation
import KnowledgeBaseWikiCore
import StateRootKit
import CommandKit
import LocalizationKit

/// 틱 스케줄 관리 — CLI 가 자기 launchd 에이전트를 Swift 로 소유(하드크래프트 plist 금지).
/// `schedule` = 표준 틱 중 누락된 것만 등록(기존 스케줄 안 건드림). `schedule list` = 상태.
/// 설치를 CLI 가 소유한다는 원칙(install·schedule)의 연장 — 코드는 있는데 안 불리는 사고 방지.
func runSchedule(arguments: [String]) {
    // (label 접미사, tick 인자, 스케줄). run-reaper 는 tick 인자가 reaper 임에 주의.
    let ticks: [(role: String, tickArg: String, interval: [String: Int])] = [
        ("checkpoint", "checkpoint", ["Hour": 21, "Minute": 30]),
        ("librarian", "librarian", ["Hour": 3, "Minute": 30]),
        ("run-reaper", "reaper", ["Minute": 45]),
        ("verifier", "verifier", ["Hour": 4, "Minute": 30, "Weekday": 1]),
        ("retrospective", "retrospective", ["Hour": 5, "Minute": 0, "Weekday": 1]),
    ]
    let agentsDir = StateRootKit.url("Library/LaunchAgents")
    func plistURL(_ role: String) -> URL {
        agentsDir.appendingPathComponent("net.ranode.memo-citation-ledger.\(role).plist")
    }

    if arguments.count >= 2 && arguments[1] == "list" {
        print(CLILocalization.string("CommandSchedule.print"))
        for t in ticks {
            let url = plistURL(t.role)
            let exists = FileManager.default.fileExists(atPath: url.path)
            let prog = exists ? programArg0(at: url) : nil
            let bad = prog.map { DualEntry.isGUIMasquerading(at: $0) || !DualEntry.isSafeCLIExecutable($0) } ?? false
            let mark = exists ? (bad ? "⚠" : "●") : "○"
            let note = !exists ? "  (미등록)" : (bad ? "  (GUI/불안전 ProgramArguments!)" : "")
            print("  \(mark) \(t.role)  \(fmt(t.interval))\(note)")
        }
        return
    }

    // dual-entry: GUI 로 resolve 되는 PATH 는 거부 — LaunchAgent 가 AppKit 폭주 내는 경로 차단.
    guard let cliPath = DualEntry.resolveCLIPath() else {
        print(CLILocalization.string("CommandSchedule.print-2"))
        print(CLILocalization.string("CommandSchedule.print-3"))
        return
    }
    let logDir = StateRootKit.path(".memo-citation-ledger")
    do {
        try FileManager.default.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    } catch {
        fail("로그 디렉터리 생성 실패: \(error.localizedDescription)")
    }
    do {
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
    } catch {
        fail("LaunchAgents 디렉터리 생성 실패: \(error.localizedDescription)")
    }

    var added = 0
    var repaired = 0
    for t in ticks {
        let url = plistURL(t.role)
        if FileManager.default.fileExists(atPath: url.path) {
            // 기존 plist 가 GUI/불안전 바이너리를 가리키면 교체 (폭주 재발 방지).
            if let prog = programArg0(at: url),
               DualEntry.isGUIMasquerading(at: prog) || !DualEntry.isSafeCLIExecutable(prog) {
                _ = launchctl(["unload", "-w", url.path])
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    fail("불안전 plist 제거 실패(\(url.path)): \(error.localizedDescription)")
                }
                print(CLILocalization.format("CommandSchedule.print-4", t.role, prog))
                repaired += 1
            } else {
                continue  // 기존 안전 등록 유지
            }
        }
        let dict: [String: Any] = [
            "Label": "net.ranode.memo-citation-ledger.\(t.role)",
            "ProgramArguments": [cliPath, "tick", t.tickArg],
            "StandardOutPath": "\(logDir)/\(t.role).log",
            "StandardErrorPath": "\(logDir)/\(t.role).err.log",
            "StartCalendarInterval": t.interval,
        ]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else {
            print(CLILocalization.format("CommandSchedule.print-5", t.role)); continue
        }
        do {
            try data.write(to: url)
            _ = launchctl(["load", "-w", url.path])
            print(CLILocalization.format("CommandSchedule.print-6", t.role, fmt(t.interval)))
            added += 1
        } catch { print(CLILocalization.format("CommandSchedule.print-7", t.role, "\(error)")) }
    }
    if added == 0 && repaired == 0 {
        print(CLILocalization.string("CommandSchedule.print-8"))
    } else {
        print(CLILocalization.format("CommandSchedule.print-9", added, repaired > 0 ? CLILocalization.format("cli.repaired", String(repaired)) : ""))
    }
}

/// LaunchAgent plist 의 ProgramArguments[0] (없으면 nil).
private func programArg0(at url: URL) -> String? {
    guard let data = try? Data(contentsOf: url),
          let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
          let args = plist["ProgramArguments"] as? [String],
          let first = args.first, !first.isEmpty else { return nil }
    return first
}

private func fmt(_ i: [String: Int]) -> String {
    if let w = i["Weekday"] { return CLILocalization.format("CommandSchedule.return", w, i["Hour"] ?? 0, String(format: "%02d", i["Minute"] ?? 0)) }
    if i["Hour"] != nil { return CLILocalization.format("CommandSchedule.return-2", i["Hour"] ?? 0, String(format: "%02d", i["Minute"] ?? 0)) }
    return CLILocalization.format("CommandSchedule.return-3", String(format: "%02d", i["Minute"] ?? 0))
}

@discardableResult
private func launchctl(_ args: [String]) -> Int32 {
    CommandKitSync.run("/bin/launchctl", args, timeout: 10).exitCode
}
