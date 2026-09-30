import InteropKit
import Foundation
import KnowledgeBaseWikiCore
import StateRootKit

private func waitWithTimeout(_ process: Process, seconds: TimeInterval = 30) {
    let src = DispatchSource.makeTimerSource()
    src.schedule(deadline: .now() + seconds)
    src.setEventHandler { process.terminate() }
    src.resume()
    process.waitUntilExit()
    src.cancel()
}

// restic 야간 백업 — objects·events·blobs(정본)만, state/(파생)는 제외.
struct BackupConfig: Codable {
    var repository: String
    var password: String

    static var path: String { StateRootKit.path(".memo-citation-ledger/backup.json") }

    /// 저장소 기본값은 없다 — 옛 sftp 저장소 호스트는 50 대역과 함께 퇴역했다(2026-09-25).
    /// 설정이 없거나 읽을 수 없으면 restic 을 부르지 않고 설정 방법을 알린다.
    static func load() -> BackupConfig {
        guard let data = FileManager.default.contents(atPath: path) else {
            fail("restic 백업 저장소가 설정되지 않았다(기본값 없음). \(path) 에 "
                + "{\"repository\": \"sftp:<host>:<path>\", \"password\": \"<restic 비밀번호>\"} 를 써라.")
        }
        do {
            return try JSONDecoder().decode(BackupConfig.self, from: data)
        } catch {
            fail("백업 설정(\(path))을 읽지 못했다 — repository·password 가 필요하다: \(error.localizedDescription)")
        }
    }
}

public func runBackup(arguments: [String]) {
    let wikiRoot = StateRootKit.path("gujo-wiki")
    let config = BackupConfig.load()
    func restic(_ resticArguments: [String]) -> Int32 {
        // TODO(commandkit): migrate raw Process() to ProcessCommandRunner — see swiftkit/Documentation/command-kit.md
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["restic", "-r", config.repository] + resticArguments
        var environment = ProcessInfo.processInfo.environment
        environment["RESTIC_PASSWORD"] = config.password
        environment["PATH"] = "\(HostPlatform.homebrewBin):" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        try? process.run()
        waitWithTimeout(process)
        return process.terminationStatus
    }
    // state/ 는 파생(index.db·graph.db·WAL) — md 정본·events·blobs 에서 언제든 재생성되므로
    // 불변 백업에서 제외해 스냅샷 팽창을 막는다. objects·events·blobs 는 정본이라 백업 유지.
    guard restic(["backup", wikiRoot, "--tag", "nightly",
                  "--exclude", wikiRoot + "/state"]) == 0 else { fail("restic backup 실패") }
    _ = restic(["forget", "--keep-daily", "30", "--keep-weekly", "12", "--keep-monthly", "12", "--prune"])
    if Calendar.current.component(.weekday, from: Date()) == 1 {  // 일요일
        _ = restic(["check"])
    }
    print("\(nowISO()) backup 완료") // allow:debug
}
