import Foundation
import KnowledgeBaseWikiCore
import StateRootKit
import WikiCLIShared
import LocalizationKit
import CommandKit

// 예약 틱 목록(`scheduleTicks`)과 거둘 옛 틱(`retiredScheduleRoles`)은 WikiCLIShared `ScheduleTicks.swift` 한 곳.

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
    reapRetiredScheduleTicks(agentsDir: agentsDir)
    registerScheduleTicks(ticks, agentsDir: agentsDir, cliPath: cliPath, logDir: logDir)
}

/// 등록된 plist 하나를 내리고 지운다(불안전 plist 수리·옛 틱 거두기·인자 바뀐 틱 재등록이 함께 쓴다).
private func reapSchedulePlist(_ url: URL) {
    _ = launchctl(["unload", "-w", url.path])
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        fail("plist 제거 실패(\(url.path)): \(error.localizedDescription)")
    }
}

/// 예약에서 뺀 옛 틱의 plist 를 거둔다.
private func reapRetiredScheduleTicks(agentsDir: URL) {
    for role in retiredScheduleRoles {
        let url = plistURL(role: role, agentsDir: agentsDir)
        guard FileManager.default.fileExists(atPath: url.path) else { continue }
        reapSchedulePlist(url)
        print("옛 예약 틱 거둠: \(role) (ledger 3 대응 없음)") // allow:debug — 명령 결과 출력
    }
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
                reapSchedulePlist(url)
                print(CLILocalization.format("CommandSchedule.print-4", t.role, prog))
                repaired += 1
            } else if programArguments(at: url).map({ Array($0.dropFirst()) }) != t.arguments {
                // 인자가 바뀐 틱(옛 `tick checkpoint|verifier` 등)은 거두고 새 인자로 다시 등록한다.
                reapSchedulePlist(url)
                print("인자가 바뀐 예약 틱 다시 등록: \(t.role)") // allow:debug — 명령 결과 출력
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
    guard let first = programArguments(at: url)?.first, !first.isEmpty else { return nil }
    return first
}

private func programArguments(at url: URL) -> [String]? {
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
    guard let plist = object as? [String: Any], let args = plist["ProgramArguments"] as? [String] else { return nil }
    return args
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
