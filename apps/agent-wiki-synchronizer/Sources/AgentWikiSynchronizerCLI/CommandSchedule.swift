import Foundation
import KnowledgeBaseWikiCore
import StateRootKit
import WikiCLIShared
import LocalizationKit
import CommandKit

/// 예약 실행 간격 — 달력 시각(StartCalendarInterval) 또는 초 간격(StartInterval).
enum ScheduleInterval: Equatable {
    case calendar([String: Int])
    case every(seconds: Int)
}

/// LaunchAgent 하나 = CLI 를 부르는 순수 plist 하나(RunAtLoad 없음).
struct ScheduleTick: Equatable {
    let role: String
    /// CLI 뒤에 붙는 인자.
    let arguments: [String]
    let interval: ScheduleInterval
}

/// 예약 실행 틱 목록. 옛 운영 틱은 그대로 두고, agent-law 의 동기화 10분·적재 하루·드리밍 하루를 더한다
/// (docs/architecture.md "agent-law" 예약 실행, 결정 0007). 실제 동작은 각 명령(T5·T7·T10)이 채운다.
let scheduleTicks: [ScheduleTick] = [
    ScheduleTick(role: "checkpoint", arguments: ["tick", "checkpoint"], interval: .calendar(["Hour": 21, "Minute": 30])),
    ScheduleTick(role: "librarian", arguments: ["tick", "librarian"], interval: .calendar(["Hour": 3, "Minute": 30])),
    ScheduleTick(role: "run-reaper", arguments: ["tick", "reaper"], interval: .calendar(["Minute": 45])),
    ScheduleTick(
        role: "verifier", arguments: ["tick", "verifier"],
        interval: .calendar(["Hour": 4, "Minute": 30, "Weekday": 1])),
    ScheduleTick(
        role: "retrospective", arguments: ["tick", "retrospective"],
        interval: .calendar(["Hour": 5, "Minute": 0, "Weekday": 1])),
    ScheduleTick(role: "law-sync", arguments: ["sync"], interval: .every(seconds: 600)),
    ScheduleTick(role: "law-archive", arguments: ["archive"], interval: .calendar(["Hour": 2, "Minute": 0])),
    ScheduleTick(role: "law-dream", arguments: ["dream", "run", "--scheduled"], interval: .calendar(["Hour": 2, "Minute": 30])),
]

func runSchedule(arguments: [String]) {
    let ticks = scheduleTicks
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
    let dict = schedulePlist(tick: tick, cliPath: cliPath, logDir: logDir)
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

/// 순수 plist 내용 — CLI 경로와 인자, 로그, 간격만(RunAtLoad·KeepAlive 없음).
func schedulePlist(tick: ScheduleTick, cliPath: String, logDir: String) -> [String: Any] {
    var dict: [String: Any] = [
        "Label": "net.ranode.memo-citation-ledger.\(tick.role)",
        "ProgramArguments": [cliPath] + tick.arguments,
        "StandardOutPath": "\(logDir)/\(tick.role).log",
        "StandardErrorPath": "\(logDir)/\(tick.role).err.log",
    ]
    switch tick.interval {
    case .calendar(let calendar): dict["StartCalendarInterval"] = calendar
    case .every(let seconds): dict["StartInterval"] = seconds
    }
    return dict
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

private func fmt(_ interval: ScheduleInterval) -> String {
    switch interval {
    case .every(let seconds): return "\(seconds / 60)분마다"
    case .calendar(let calendar): return fmt(calendar)
    }
}

private func fmt(_ i: [String: Int]) -> String {
    if let w = i["Weekday"] { return CLILocalization.format("CommandSchedule.return", w, i["Hour"] ?? 0, String(format: "%02d", i["Minute"] ?? 0)) }
    if i["Hour"] != nil { return CLILocalization.format("CommandSchedule.return-2", i["Hour"] ?? 0, String(format: "%02d", i["Minute"] ?? 0)) }
    return CLILocalization.format("CommandSchedule.return-3", String(format: "%02d", i["Minute"] ?? 0))
}

@discardableResult
private func launchctl(_ args: [String]) -> Int32 {
    // 86c79a277e 의 SafeProcessRunner 이관이 `p`(Process) 선언만 지우고 대기 루프를 남겨
    // 컴파일이 깨졌다. 10초 제한·시간 초과 124 는 그대로 SafeProcessRunner 에 맡긴다.
    let result = SafeProcessRunner.run(executable: "/bin/launchctl", arguments: args, timeout: 10)
    return result.timedOut ? 124 : result.exitCode
}
