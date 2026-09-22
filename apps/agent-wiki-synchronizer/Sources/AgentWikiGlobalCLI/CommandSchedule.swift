import Foundation
import KnowledgeBaseWikiCore
import StateRootKit
import WikiCLIShared
import LocalizationKit
import CommandKit

private struct ScheduleTick {
    let role: String
    let tickArg: String
    let interval: [String: Int]
}

func runSchedule(arguments: [String]) {
    let ticks: [ScheduleTick] = [
        ScheduleTick(role: "checkpoint", tickArg: "checkpoint", interval: ["Hour": 21, "Minute": 30]),
        ScheduleTick(role: "librarian", tickArg: "librarian", interval: ["Hour": 3, "Minute": 30]),
        ScheduleTick(role: "run-reaper", tickArg: "reaper", interval: ["Minute": 45]),
        ScheduleTick(role: "verifier", tickArg: "verifier", interval: ["Hour": 4, "Minute": 30, "Weekday": 1]),
        ScheduleTick(role: "retrospective", tickArg: "retrospective", interval: ["Hour": 5, "Minute": 0, "Weekday": 1]),
    ]
    let agentsDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents")

    if arguments.count >= 2 && arguments[1] == "list" {
        listScheduleTicks(ticks, agentsDir: agentsDir)
        return
    }

    guard let cliPath = DualEntry.resolveCLIPath() else {
        print(CLILocalization.string("CommandSchedule.print"))
        print(CLILocalization.string("CommandSchedule.print-2"))
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
    registerScheduleTicks(ticks, agentsDir: agentsDir, cliPath: cliPath, logDir: logDir)
}

private func plistURL(role: String, agentsDir: URL) -> URL {
    agentsDir.appendingPathComponent("net.ranode.memo-citation-ledger.\(role).plist")
}

private func listScheduleTicks(_ ticks: [ScheduleTick], agentsDir: URL) {
    print(CLILocalization.string("CommandSchedule.print-3"))
    for t in ticks {
        let url = plistURL(role: t.role, agentsDir: agentsDir)
        let exists = FileManager.default.fileExists(atPath: url.path)
        let prog = exists ? programArg0(at: url) : nil
        let bad = prog.map { DualEntry.isGUIMasquerading(at: $0) || !DualEntry.isSafeCLIExecutable($0) } ?? false
        let mark = exists ? (bad ? "⚠" : "●") : "○"
        let note = !exists ? "  (미등록)" : (bad ? "  (GUI/불안전 ProgramArguments!)" : "")
        print("  \(mark) \(t.role)  \(fmt(t.interval))\(note)")
    }
}

private func registerScheduleTicks(
    _ ticks: [ScheduleTick],
    agentsDir: URL,
    cliPath: String,
    logDir: String
) {
    var added = 0
    var repaired = 0
    for t in ticks {
        let url = plistURL(role: t.role, agentsDir: agentsDir)
        if FileManager.default.fileExists(atPath: url.path) {
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
                continue
            }
        }
        if writeSchedulePlist(tick: t, url: url, cliPath: cliPath, logDir: logDir) {
            added += 1
        }
    }
    if added == 0 && repaired == 0 {
        print(CLILocalization.string("CommandSchedule.print-5"))
    } else {
        print(CLILocalization.format("CommandSchedule.print-6", added, repaired > 0 ? CLILocalization.format("CommandSchedule.unsafe-repair", String(repaired)) : ""))
    }
}

private func writeSchedulePlist(
    tick: ScheduleTick,
    url: URL,
    cliPath: String,
    logDir: String
) -> Bool {
    let dict: [String: Any] = [
        "Label": "net.ranode.memo-citation-ledger.\(tick.role)",
        "ProgramArguments": [cliPath, "tick", tick.tickArg],
        "StandardOutPath": "\(logDir)/\(tick.role).log",
        "StandardErrorPath": "\(logDir)/\(tick.role).err.log",
        "StartCalendarInterval": tick.interval,
    ]
    let data: Data
    do {
        data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    } catch {
        print(CLILocalization.format("CommandSchedule.print-7", tick.role, error.localizedDescription))
        return false
    }
    do {
        try data.write(to: url)
        _ = launchctl(["load", "-w", url.path])
        print(CLILocalization.format("CommandSchedule.print-8", tick.role, fmt(tick.interval)))
        return true
    } catch {
        print(CLILocalization.format("CommandSchedule.print-9", tick.role, String(describing: error)))
        return false
    }
}

private func programArg0(at url: URL) -> String? {
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        return nil
    }
    let object: Any
    do {
        object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    } catch {
        return nil
    }
    guard let plist = object as? [String: Any],
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
    let safeResult = SafeProcessRunner.run(
        "/bin/launchctl",
        args
    )
    let deadline = Date().addingTimeInterval(10)
    while p.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if p.isRunning {
        p.terminate()
        return 124
    }
    return p.terminationStatus
}
